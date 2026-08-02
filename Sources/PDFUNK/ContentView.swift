import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese
    case english

    var id: Self { self }
    var localeIdentifier: String { self == .japanese ? "ja" : "en" }
}

private struct ConversionInput {
    let url: URL
    let rootFolder: URL?
    let relativeDirectory: String
}

private struct SproutPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var options: ExportOptions
    var destinationMode: DestinationMode
}

struct ContentView: View {
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue
    @AppStorage("showsAdvancedSettings") private var showsAdvancedSettings = false
    @AppStorage("savedPresets") private var savedPresetsData = ""
    @State private var droppedURLs: [URL] = []
    @State private var destinationURL: URL?
    @State private var destinationMode = DestinationMode.sameLocation
    @State private var options = ExportOptions()
    @State private var includeSubfolders = false
    @State private var preservesFolderStructure = true
    @State private var isTargeted = false
    @State private var isConverting = false
    @State private var progressText = ""
    @State private var alertMessage: String?
    @State private var showsPreferences = false
    @State private var inspection = InputInspection()
    @State private var showsExecutionDetails = true
    @State private var presetName = ""
    @State private var selectedPresetID: UUID?

    private var language: AppLanguage { AppLanguage(rawValue: appLanguage) ?? .japanese }
    private var isJapanese: Bool { language == .japanese }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                dropArea
                presetSettings
                settings
                destination
                executionDetails
                exportArea
            }
            .padding(24)
        }
        .frame(width: 540, height: 900)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("SPROUT", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showsPreferences) {
            PreferencesView(appTheme: $appTheme, appLanguage: $appLanguage)
        }
        .task(id: inspectionKey) {
            await refreshInspection()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(accentGreen.opacity(0.14))
                Image(systemName: "leaf.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentGreen)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("SPROUT")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(t("あらゆる画像をdrop、あらゆる形式へ。", "Drop any image. Convert to any format."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showsPreferences = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .font(.system(size: 18))
            .help(t("環境設定", "Preferences"))
        }
    }

    private var dropArea: some View {
        VStack(spacing: 8) {
            Image(systemName: droppedURLs.isEmpty ? "arrow.down.doc" : "doc.on.doc.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isTargeted ? accentGreen : .secondary)
            Text(droppedFileLabel)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
            Text(t("複数ファイルをまとめてドロップできます", "You can drop multiple files at once"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 124)
        .background(isTargeted ? accentGreen.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isTargeted ? accentGreen : borderColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
        .dropDestination(for: URL.self) { urls, _ in
            let supported = urls.filter { isSupportedFile($0) || isDirectory($0) }
            guard !supported.isEmpty, supported.count == urls.count else {
                alertMessage = t(
                    "対応画像、PDF、またはフォルダをドロップしてください。",
                    "Drop supported images, PDFs, or folders."
                )
                return false
            }
            droppedURLs = supported
            progressText = ""
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var presetSettings: some View {
        GroupBox(t("プリセット", "Presets")) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Picker(t("読み込み", "Load"), selection: $selectedPresetID) {
                        Text(t("選択してください", "Choose a preset")).tag(UUID?.none)
                        ForEach(savedPresets) { preset in
                            Text(preset.name).tag(UUID?.some(preset.id))
                        }
                    }
                    .labelsHidden()
                    Button(t("読み込む", "Load"), action: loadSelectedPreset)
                        .disabled(selectedPresetID == nil)
                    Button(t("削除", "Delete"), action: deleteSelectedPreset)
                        .disabled(selectedPresetID == nil)
                }
                HStack {
                    TextField(t("プリセット名", "Preset name"), text: $presetName)
                    Button(t("保存", "Save"), action: saveCurrentPreset)
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(t("書き出す…", "Export…"), action: exportPresetFile)
                    Button(t("読み込む…", "Import…"), action: importPresetFile)
                }
                HStack {
                    Spacer()
                    Button(t("設定を初期値へ戻す", "Reset settings")) {
                        options = ExportOptions()
                        destinationMode = .sameLocation
                        destinationURL = nil
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var settings: some View {
        GroupBox(t("出力設定", "Output")) {
            VStack(alignment: .leading, spacing: 14) {
                normalSettings

                Divider()

                DisclosureGroup(isExpanded: $showsAdvancedSettings) {
                    advancedSettings
                        .padding(.top, 10)
                } label: {
                    Text(t("詳細設定", "Advanced settings"))
                        .font(.subheadline.weight(.semibold))
                }

                if let validationMessage = options.validationMessage(isJapanese: isJapanese) {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var normalSettings: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    settingLabel(t("保存サイズ", "Save size"))
                    Picker("", selection: $options.saveSizeMode) {
                        Text(t("指定なし", "Not specified")).tag(SaveSizeMode?.none)
                        ForEach(SaveSizeMode.allCases) { mode in
                            Text(saveSizeModeName(mode)).tag(SaveSizeMode?.some(mode))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: options.saveSizeMode) { mode in
                        if mode?.neverUpscales == true { options.allowsUpscaling = false }
                    }
                }
                if options.saveSizeMode == .percent {
                    GridRow {
                        settingLabel(t("値", "Value"))
                        HStack {
                            TextField("100", value: $options.percentage, format: .number)
                                .frame(width: 90)
                            Text("%").foregroundStyle(.secondary)
                        }
                    }
                }
                if options.saveSizeMode == .resolution {
                    GridRow {
                        settingLabel(t("解像度", "Resolution"))
                        HStack {
                            Picker("", selection: $options.saveResolution) {
                                ForEach(SaveResolutionPreset.allCases) { preset in
                                    Text(preset == .custom ? t("カスタム", "Custom") : "\(preset.rawValue) dpi").tag(preset)
                                }
                            }
                            .labelsHidden()
                            if options.saveResolution == .custom {
                                TextField("200", value: $options.customSaveDPI, format: .number)
                                    .frame(width: 72)
                                Text("dpi").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if options.saveSizeMode?.usesPixelValue == true {
                    GridRow {
                        settingLabel(t("値", "Value"))
                        HStack {
                            TextField("2000", value: $options.edgePixels, format: .number)
                                .frame(width: 90)
                            Text("px").foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    settingLabel(t("形式", "Format"))
                    Picker("", selection: $options.format) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .labelsHidden()
                }
                if options.format == .jpg {
                    GridRow {
                        settingLabel(t("JPEG品質", "JPEG quality"))
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(options.jpegQuality) },
                                    set: { options.jpegQuality = Int($0.rounded()) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            .frame(width: 180)
                            Text("\(options.jpegQuality)")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
                if options.format == .webp {
                    GridRow {
                        settingLabel(t("WebP品質", "WebP quality"))
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(options.webPQuality) },
                                    set: { options.webPQuality = Int($0.rounded()) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            .frame(width: 180)
                            Text("\(options.webPQuality)")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
                GridRow {
                    settingLabel(t("カラー", "Color"))
                    Picker("", selection: $options.colorProfile) {
                        ForEach(ColorProfile.allCases) { profile in
                            Text(colorProfileName(profile)).tag(profile)
                        }
                    }
                    .labelsHidden()
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var advancedSettings: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    settingLabel(t("リサイズ方式", "Resize method"))
                    Picker("", selection: $options.resizeMethod) {
                        ForEach(ResizeMethod.allCases) { method in
                            Text(resizeMethodName(method)).tag(method)
                        }
                    }
                    .labelsHidden()
                }
                if inspection.pdfCount > 0 && options.saveSizeMode != .resolution {
                    GridRow {
                        settingLabel(t("PDF読込解像度", "PDF import DPI"))
                        HStack {
                            Picker("", selection: $options.pdfResolution) {
                                ForEach(PDFResolutionPreset.allCases) { preset in
                                    Text(preset == .custom ? t("カスタム", "Custom") : "\(preset.rawValue) dpi").tag(preset)
                                }
                            }
                            .labelsHidden()
                            if options.pdfResolution == .custom {
                                TextField("200", value: $options.customPDFDPI, format: .number)
                                    .frame(width: 72)
                                Text("dpi").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if options.format == .png || options.format == .tiff {
                    GridRow {
                        settingLabel(t("ビット深度", "Bit depth"))
                        Picker("", selection: $options.bitDepth) {
                            Text(t("元のまま", "Match source")).tag(BitDepth.matchSource)
                            Text("8 bit").tag(BitDepth.bit8)
                            Text("16 bit").tag(BitDepth.bit16)
                        }
                        .labelsHidden()
                    }
                }
                if options.format == .png {
                    GridRow {
                        settingLabel(t("PNG圧縮率", "PNG compression"))
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(options.pngCompression) },
                                    set: { options.pngCompression = Int($0.rounded()) }
                                ),
                                in: 0...9,
                                step: 1
                            )
                            .frame(width: 180)
                            Text("\(options.pngCompression)")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
                GridRow {
                    settingLabel("")
                    Toggle(t("カラープロファイルを埋め込む", "Embed color profile"), isOn: $options.embedsColorProfile)
                }
                GridRow {
                    settingLabel(t("出力ファイル名", "Output filename"))
                    Picker("", selection: $options.filenameMode) {
                        Text(t("元の名前", "Original name")).tag(OutputFilenameMode.original)
                        Text(t("新しい名前", "New name")).tag(OutputFilenameMode.customName)
                        Text(t("連番のみ", "Sequence only")).tag(OutputFilenameMode.sequenceOnly)
                    }
                    .labelsHidden()
                }
                if options.filenameMode == .customName {
                    GridRow {
                        settingLabel(t("新しい名前", "New name"))
                        TextField(t("商品画像", "Product image"), text: $options.customFilename)
                    }
                }
                GridRow {
                    settingLabel(t("ファイル名加工", "Filename processing"))
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(t("文字を追加", "Add text"), isOn: $options.addsTextToFilename)
                        Toggle(t("文字を置換", "Replace text"), isOn: $options.replacesFilenameText)
                    }
                }
                if options.addsTextToFilename {
                    GridRow {
                        settingLabel(t("追加文字", "Text to add"))
                        TextField("_web", text: $options.addedFilenameText)
                    }
                    GridRow {
                        settingLabel(t("位置", "Position"))
                        HStack {
                            Picker("", selection: $options.textAdditionPosition) {
                                Text(t("先頭", "Beginning")).tag(TextAdditionPosition.beginning)
                                Text(t("末尾", "End")).tag(TextAdditionPosition.end)
                                Text(t("任意の位置", "Custom position")).tag(TextAdditionPosition.custom)
                            }
                            .labelsHidden()
                            if options.textAdditionPosition == .custom {
                                TextField("0", value: $options.customTextPosition, format: .number)
                                    .frame(width: 60)
                            }
                        }
                    }
                }
                if options.replacesFilenameText {
                    GridRow {
                        settingLabel(t("検索文字", "Find"))
                        TextField("final", text: $options.filenameSearchText)
                    }
                    GridRow {
                        settingLabel(t("置換文字", "Replace"))
                        TextField("web", text: $options.filenameReplacementText)
                    }
                }
                GridRow {
                    settingLabel(t("メタデータ", "Metadata"))
                    Picker("", selection: $options.metadataMode) {
                        Text(t("保持", "Keep")).tag(MetadataMode.keep)
                        Text(t("破棄", "Discard")).tag(MetadataMode.discard)
                    }
                    .labelsHidden()
                }
                GridRow {
                    settingLabel("")
                    Toggle(t("作成日時を保持", "Preserve creation date"), isOn: $options.preservesFileDates)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var executionDetails: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $showsExecutionDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    detailSection(t("入力", "Input"), lines: inputDetailLines)
                    detailSection(t("書き出し", "Export"), lines: exportDetailLines)
                    let warnings = warningDetailLines
                    if !warnings.isEmpty {
                        detailSection(t("注意", "Notes"), lines: warnings, warning: true)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(t("詳細表示", "Details"))
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func detailSection(_ title: String, lines: [String], warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.bold))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(warning ? .orange : .secondary)
            }
        }
    }

    private var inputDetailLines: [String] {
        var lines = [t("ファイル \(inspection.fileCount)件", "Files: \(inspection.fileCount)")]
        let formats = inspection.formatCounts.keys.sorted().map { "\($0) \(inspection.formatCounts[$0]!)" }
        if !formats.isEmpty { lines.append(formats.joined(separator: " / ")) }
        if inspection.pdfCount > 0 {
            lines.append(t(
                "PDF \(inspection.pdfCount)件（合計\(inspection.pdfPageCount)ページ）",
                "PDF: \(inspection.pdfCount) files (\(inspection.pdfPageCount) pages)"
            ))
        }
        if inspection.psdCount > 0 { lines.append(t("PSD \(inspection.psdCount)件", "PSD: \(inspection.psdCount)")) }
        return lines
    }

    private var exportDetailLines: [String] {
        var lines = [t(
            "合計\(inspection.outputImageCount)枚の\(options.format.displayName)を書き出します",
            "Export \(inspection.outputImageCount) \(options.format.displayName) image(s)"
        )]
        lines.append(t("保存サイズ：\(saveSizeDescription)", "Save size: \(saveSizeDescription)"))
        lines.append(t("リサイズ方式：\(resizeMethodName(options.resizeMethod))", "Resize method: \(resizeMethodName(options.resizeMethod))"))
        lines.append(t("カラー：\(colorProfileName(options.colorProfile))", "Color: \(colorProfileName(options.colorProfile))"))
        lines.append(t("保存先：\(destinationDescription)", "Destination: \(destinationDescription)"))
        lines.append(t(
            "メタデータ：\(options.metadataMode == .keep ? "保持" : "破棄")",
            "Metadata: \(options.metadataMode == .keep ? "Keep" : "Discard")"
        ))
        lines.append(t(
            "作成日時：\(options.preservesFileDates ? "保持" : "保持しない")",
            "File dates: \(options.preservesFileDates ? "Preserve" : "Do not preserve")"
        ))
        if inspection.pdfCount > 0 {
            lines.append(t("PDF読込解像度：\(options.effectivePDFDPI)dpi", "PDF import: \(options.effectivePDFDPI) dpi"))
        }
        return lines
    }

    private var warningDetailLines: [String] {
        var lines: [String] = []
        if inspection.pdfCount > 0 {
            lines.append(t("PDFは\(options.effectivePDFDPI)dpiで画像化します", "PDFs are rasterized at \(options.effectivePDFDPI) dpi"))
        }
        if inspection.upscaleImageCount > 0 {
            lines.append(t(
                "\(inspection.upscaleImageCount)枚が拡大されます。画質が低下する可能性があります。",
                "\(inspection.upscaleImageCount) image(s) will be enlarged. Quality may decrease."
            ))
        }
        if inspection.psdCount > 0 {
            lines.append(t("PSDは統合画像として処理します", "PSDs are processed as flattened composites"))
        }
        if inspection.hasMultiPagePDF {
            lines.append(t("複数ページPDFはページごとに書き出します", "Multi-page PDFs are exported page by page"))
        }
        if inspection.gifCount > 0 {
            lines.append(t("アニメーションGIFは先頭フレームのみ使用します", "Animated GIFs use the first frame only"))
        }
        if options.format == .jpg && inspection.mayContainTransparency {
            lines.append(t("JPGでは透過部分を白背景にします", "Transparent areas are flattened onto white for JPG"))
        }
        if inspection.fileCount > 0 {
            lines.append(t("同名ファイルは「(1)」を付けて保存します", "Name conflicts are saved with “(1)”"))
        }
        return lines
    }

    private var inspectionKey: String {
        [
            droppedURLs.map(\.path).joined(separator: "|"),
            String(includeSubfolders),
            options.pdfResolution.rawValue, String(options.customPDFDPI),
            options.saveSizeMode?.rawValue ?? "none", options.saveResolution.rawValue, String(options.customSaveDPI),
            String(options.percentage), String(options.edgePixels), String(options.allowsUpscaling),
            options.resizeMethod.rawValue, options.format.rawValue
        ].joined(separator: "#")
    }

    private func refreshInspection() async {
        let files = (try? expandedInputs(from: droppedURLs).map(\.url)) ?? []
        let snapshot = options
        inspection = await Task.detached {
            InputInspector.inspect(urls: files, options: snapshot)
        }.value
    }

    private func saveSizeModeName(_ mode: SaveSizeMode) -> String {
        switch mode {
        case .percent: t("パーセント", "Percent")
        case .resolution: t("解像度", "Resolution")
        case .longEdge: t("長辺ピクセル", "Long edge pixels")
        case .shortEdge: t("短辺ピクセル", "Short edge pixels")
        case .maxLongEdge: t("長辺px以内", "Long edge maximum")
        case .maxShortEdge: t("短辺px以内", "Short edge maximum")
        case .width: t("幅", "Width")
        case .height: t("高さ", "Height")
        case .maxWidth: t("幅px以内", "Width maximum")
        case .maxHeight: t("高さpx以内", "Height maximum")
        }
    }

    private var saveSizeDescription: String {
        switch options.saveSizeMode {
        case nil: t("変更なし", "Unchanged")
        case .percent?: "\(options.percentage)%"
        case .resolution?: "\(options.saveDPI)dpi"
        case .longEdge?: t("長辺\(options.edgePixels)px", "Long edge \(options.edgePixels)px")
        case .shortEdge?: t("短辺\(options.edgePixels)px", "Short edge \(options.edgePixels)px")
        case .maxLongEdge?: t("長辺\(options.edgePixels)px以内", "Long edge up to \(options.edgePixels)px")
        case .maxShortEdge?: t("短辺\(options.edgePixels)px以内", "Short edge up to \(options.edgePixels)px")
        case .width?: t("幅\(options.edgePixels)px", "Width \(options.edgePixels)px")
        case .height?: t("高さ\(options.edgePixels)px", "Height \(options.edgePixels)px")
        case .maxWidth?: t("幅\(options.edgePixels)px以内", "Width up to \(options.edgePixels)px")
        case .maxHeight?: t("高さ\(options.edgePixels)px以内", "Height up to \(options.edgePixels)px")
        }
    }

    private func resizeMethodName(_ method: ResizeMethod) -> String {
        switch method {
        case .automatic: t("自動（推奨）", "Automatic (Recommended)")
        case .bicubic: t("バイキュービック", "Bicubic")
        case .bicubicSharper: t("バイキュービック・シャープ", "Bicubic Sharper")
        case .bicubicSmoother: t("バイキュービック・スムーズ", "Bicubic Smoother")
        case .nearestNeighbor: t("ニアレストネイバー", "Nearest Neighbor")
        }
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                settingLabel(t("保存先", "Save to"))
                Spacer()
                Picker("", selection: $destinationMode) {
                    Text(t("同じ場所", "Same location")).tag(DestinationMode.sameLocation)
                    Text(t("選択したフォルダ", "Selected folder")).tag(DestinationMode.selectedFolder)
                }
                .labelsHidden()
                .frame(width: 170)
                if destinationMode == .selectedFolder {
                    Button(t("選択…", "Choose…"), action: chooseDestination)
                }
            }
            Text(destinationDescription)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
    }

    private var exportArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !progressText.isEmpty {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(isConverting ? t("変換中…", "Converting…") : t("画像を書き出す", "Export images"), action: export)
                .buttonStyle(.borderedProminent)
                .tint(accentGreen)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(
                    droppedURLs.isEmpty
                        || (destinationMode == .selectedFolder && destinationURL == nil)
                        || isConverting
                        || !selectedOptionsAreImplemented
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var accentGreen: Color { Color(red: 0.16, green: 0.52, blue: 0.30) }
    private var borderColor: Color { Color(nsColor: .separatorColor) }

    private func t(_ japanese: String, _ english: String) -> String {
        isJapanese ? japanese : english
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 116, alignment: .leading)
    }

    private func colorProfileName(_ profile: ColorProfile) -> String {
        switch profile {
        case .matchSource: t("元ファイルに合わせる", "Match source")
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        case .adobeRGB: "Adobe RGB (1998)"
        }
    }

    private var selectedOptionsAreImplemented: Bool {
        options.validationMessage(isJapanese: isJapanese) == nil
    }

    private var savedPresets: [SproutPreset] {
        guard let data = savedPresetsData.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SproutPreset].self, from: data)) ?? []
    }

    private func persistPresets(_ presets: [SproutPreset]) {
        guard let data = try? JSONEncoder().encode(presets),
              let json = String(data: data, encoding: .utf8) else { return }
        savedPresetsData = json
    }

    private func saveCurrentPreset() {
        let cleanName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        var presets = savedPresets
        if let index = presets.firstIndex(where: { $0.name == cleanName }) {
            presets[index].options = options
            presets[index].destinationMode = destinationMode
            selectedPresetID = presets[index].id
        } else {
            let preset = SproutPreset(name: cleanName, options: options, destinationMode: destinationMode)
            presets.append(preset)
            selectedPresetID = preset.id
        }
        persistPresets(presets)
    }

    private func loadSelectedPreset() {
        guard let id = selectedPresetID,
              let preset = savedPresets.first(where: { $0.id == id }) else { return }
        options = preset.options
        destinationMode = preset.destinationMode
        destinationURL = nil
        presetName = preset.name
    }

    private func deleteSelectedPreset() {
        guard let id = selectedPresetID else { return }
        persistPresets(savedPresets.filter { $0.id != id })
        selectedPresetID = nil
        presetName = ""
    }

    private func exportPresetFile() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = SproutPreset(
            name: name.isEmpty ? "SPROUT Preset" : name,
            options: options,
            destinationMode: destinationMode
        )
        guard let data = try? JSONEncoder().encode(preset) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(preset.name).sproutpreset"
        panel.allowedContentTypes = [UTType(filenameExtension: "sproutpreset") ?? .json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func importPresetFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "sproutpreset") ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let preset = try JSONDecoder().decode(SproutPreset.self, from: Data(contentsOf: url))
            var presets = savedPresets.filter { $0.id != preset.id && $0.name != preset.name }
            presets.append(preset)
            persistPresets(presets)
            selectedPresetID = preset.id
            presetName = preset.name
            options = preset.options
            destinationMode = preset.destinationMode
            destinationURL = nil
        } catch {
            alertMessage = t("プリセットを読み込めませんでした。", "Could not import the preset.")
        }
    }

    private var droppedFileLabel: String {
        switch droppedURLs.count {
        case 0: t(
            "（PNG、JPG、PDF、PSD、TIF、GIF、WebP）をここへドロップ",
            "Drop PNG, JPG, PDF, PSD, TIF, GIF, or WebP here"
        )
        case 1: droppedURLs[0].lastPathComponent
        default: t("\(droppedURLs.count)項目を選択中", "\(droppedURLs.count) items selected")
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = t("画像の保存先を選択", "Choose an output folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { destinationURL = panel.url }
    }

    private func export() {
        guard !droppedURLs.isEmpty else { return }
        let roots = droppedURLs
        let conversionLanguageIsJapanese = isJapanese
        isConverting = true
        progressText = t("変換を開始しています…", "Starting conversion…")

        Task {
            let selectedDestination = destinationURL
            let securityScopedURLs = roots + (selectedDestination.map { [$0] } ?? [])
            let accessedURLs = securityScopedURLs.filter { $0.startAccessingSecurityScopedResource() }
            defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

            do {
                let filesToConvert = try expandedInputs(from: roots)
                guard !filesToConvert.isEmpty else {
                    throw ConversionError.incompatibleOptions(
                        conversionLanguageIsJapanese
                            ? "変換できるファイルが見つかりませんでした。"
                            : "No supported files were found."
                    )
                }
                let outputSequence = OutputSequence()
                for (fileIndex, input) in filesToConvert.enumerated() {
                    let outputBase = try outputBaseURL(for: input, selectedDestination: selectedDestination)
                    try await FileConverter().convert(
                        inputURL: input.url,
                        destinationURL: outputBase,
                        options: options,
                        sequence: outputSequence,
                        isJapanese: conversionLanguageIsJapanese
                    ) { completed, total in
                        progressText = conversionLanguageIsJapanese
                            ? "ファイル \(fileIndex + 1)/\(filesToConvert.count)・\(completed)/\(total)"
                            : "File \(fileIndex + 1)/\(filesToConvert.count) · \(completed)/\(total)"
                    }
                }
                isConverting = false
                alertMessage = conversionLanguageIsJapanese
                    ? "\(filesToConvert.count)個のファイルを変換しました。"
                    : "Converted \(filesToConvert.count) file(s)."
            } catch {
                isConverting = false
                alertMessage = error.localizedDescription
            }
        }
    }

    private var containsFolder: Bool { droppedURLs.contains(where: isDirectory) }

    private var destinationDescription: String {
        switch destinationMode {
        case .sameLocation: t("入力ファイルと同じ場所", "Next to each source file")
        case .selectedFolder:
            destinationURL?.path(percentEncoded: false)
                ?? t("保存先を選択してください", "Choose an output folder")
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isSupportedFile(_ url: URL) -> Bool {
        FileConverter.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func expandedInputs(from roots: [URL]) throws -> [ConversionInput] {
        var result: [ConversionInput] = []
        for root in roots {
            if !isDirectory(root) {
                result.append(ConversionInput(url: root, rootFolder: nil, relativeDirectory: ""))
                continue
            }

            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
            let candidates: [URL]
            if includeSubfolders {
                let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                candidates = enumerator?.allObjects.compactMap { $0 as? URL } ?? []
            } else {
                candidates = try FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles]
                )
            }

            for file in candidates where isSupportedFile(file) && !isDirectory(file) {
                let parentPath = file.deletingLastPathComponent().standardizedFileURL.path
                let rootPath = root.standardizedFileURL.path
                var relative = parentPath.hasPrefix(rootPath)
                    ? String(parentPath.dropFirst(rootPath.count))
                    : ""
                if relative.hasPrefix("/") { relative.removeFirst() }
                result.append(ConversionInput(url: file, rootFolder: root, relativeDirectory: relative))
            }
        }
        return result
    }

    private func outputBaseURL(for input: ConversionInput, selectedDestination: URL?) throws -> URL {
        if destinationMode == .sameLocation {
            return input.url.deletingLastPathComponent()
        }
        guard var base = selectedDestination else {
            throw ConversionError.incompatibleOptions(t("保存先を選択してください。", "Choose an output folder."))
        }
        if preservesFolderStructure, let root = input.rootFolder {
            base.appendPathComponent(root.lastPathComponent, isDirectory: true)
            if !input.relativeDirectory.isEmpty {
                base.appendPathComponent(input.relativeDirectory, isDirectory: true)
            }
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }
}

private struct PreferencesView: View {
    @Binding var appTheme: String
    @Binding var appLanguage: String
    @Environment(\.dismiss) private var dismiss

    private var isJapanese: Bool { appLanguage == AppLanguage.japanese.rawValue }
    private func t(_ japanese: String, _ english: String) -> String { isJapanese ? japanese : english }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("環境設定", "Preferences"))
                .font(.title2.bold())

            Form {
                Picker(t("テーマ", "Theme"), selection: $appTheme) {
                    Text(t("システム", "System")).tag(AppTheme.system.rawValue)
                    Text(t("ライト", "Light")).tag(AppTheme.light.rawValue)
                    Text(t("ダーク", "Dark")).tag(AppTheme.dark.rawValue)
                }
                Picker(t("言語", "Language"), selection: $appLanguage) {
                    Text("日本語").tag(AppLanguage.japanese.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                }
            }

            HStack {
                Spacer()
                Button(t("完了", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360, height: 240)
    }
}
