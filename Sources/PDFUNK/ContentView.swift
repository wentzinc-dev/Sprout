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
    var preservesFolderStructure: Bool?
}

private struct PresetWindowView: View {
    @Binding var savedPresetsData: String
    @Binding var options: ExportOptions
    @Binding var destinationMode: DestinationMode
    @Binding var destinationURL: URL?
    @Binding var preservesFolderStructure: Bool
    @Binding var presetName: String
    @Binding var selectedPresetID: UUID?
    @Binding var alertMessage: String?
    let isJapanese: Bool
    let onDone: () -> Void

    private var savedPresets: [SproutPreset] {
        guard let data = savedPresetsData.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SproutPreset].self, from: data)) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("プリセットを選択", "Choose a preset"))
                .font(.subheadline.weight(.semibold))
            Picker("", selection: $selectedPresetID) {
                Text(t("選択してください", "Choose a preset")).tag(UUID?.none)
                ForEach(savedPresets) { preset in
                    Text(preset.name).tag(UUID?.some(preset.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            HStack {
                Button(t("読み込む", "Load"), action: loadSelectedPreset)
                    .disabled(selectedPresetID == nil)
                Button(t("書き出す…", "Export…"), action: exportSelectedPresetFile)
                    .disabled(selectedPresetID == nil)
                Spacer()
                Button(t("削除", "Delete"), action: deleteSelectedPreset)
                    .disabled(selectedPresetID == nil)
            }

            Divider()

            Text(t("現在の設定のプリセットを保存", "Save current settings as a preset"))
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField(t("プリセット名", "Preset name"), text: $presetName)
                Button(t("保存", "Save"), action: saveCurrentPreset)
                    .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Button(t("設定を初期値へ戻す", "Reset settings")) {
                    options = ExportOptions()
                    destinationMode = .sameLocation
                    destinationURL = nil
                    preservesFolderStructure = false
                }
                Spacer()
                Button(t("決定", "Done"), action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func saveCurrentPreset() {
        let cleanName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        var presets = savedPresets
        let savedID: UUID
        if let index = presets.firstIndex(where: { $0.name == cleanName }) {
            presets[index].options = options
            presets[index].destinationMode = destinationMode
            presets[index].preservesFolderStructure = preservesFolderStructure
            savedID = presets[index].id
        } else {
            let preset = SproutPreset(
                name: cleanName,
                options: options,
                destinationMode: destinationMode,
                preservesFolderStructure: preservesFolderStructure
            )
            presets.append(preset)
            savedID = preset.id
        }
        guard persistPresets(presets) else {
            alertMessage = t("プリセットを保存できませんでした。", "Could not save the preset.")
            return
        }
        selectedPresetID = savedID
    }

    private func loadSelectedPreset() {
        guard let id = selectedPresetID,
              let preset = savedPresets.first(where: { $0.id == id }) else { return }
        var loadedOptions = preset.options
        if loadedOptions.saveSizeMode == nil {
            loadedOptions.saveSizeMode = .percent
            loadedOptions.percentage = 100
        }
        options = loadedOptions
        destinationMode = preset.destinationMode
        destinationURL = nil
        preservesFolderStructure = preset.preservesFolderStructure ?? false
        presetName = preset.name
    }

    private func deleteSelectedPreset() {
        guard let id = selectedPresetID else { return }
        guard persistPresets(savedPresets.filter { $0.id != id }) else { return }
        selectedPresetID = nil
        presetName = ""
    }

    private func exportSelectedPresetFile() {
        guard let id = selectedPresetID,
              let preset = savedPresets.first(where: { $0.id == id }),
              let data = try? JSONEncoder().encode(preset) else { return }
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

    @discardableResult
    private func persistPresets(_ presets: [SproutPreset]) -> Bool {
        guard let data = try? JSONEncoder().encode(presets),
              let json = String(data: data, encoding: .utf8) else { return false }
        savedPresetsData = json
        return true
    }

    private func t(_ japanese: String, _ english: String) -> String {
        isJapanese ? japanese : english
    }
}

struct ContentView: View {
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue
    @AppStorage("appFontSize") private var appFontSize = AppFontSize.medium.rawValue
    @AppStorage("showsAdvancedSettings") private var showsAdvancedSettings = false
    @AppStorage("savedPresets") private var savedPresetsData = ""
    @State private var droppedURLs: [URL] = []
    @State private var destinationURL: URL?
    @State private var destinationMode = DestinationMode.sameLocation
    @State private var options = ExportOptions()
    @State private var includeSubfolders = false
    @State private var preservesFolderStructure = false
    @State private var isTargeted = false
    @State private var isConverting = false
    @State private var progressText = ""
    @State private var alertMessage: String?
    @State private var showsPreferences = false
    @State private var inspection = InputInspection()
    @State private var showsExecutionDetails = true
    @State private var presetName = ""
    @State private var selectedPresetID: UUID?
    @State private var presetWindowController: NSWindowController?
    @State private var conversionProgress = 0.0
    @State private var completedFileCount = 0
    @State private var totalFileCount = 0
    @State private var logText = ""

    private var language: AppLanguage { AppLanguage(rawValue: appLanguage) ?? .japanese }
    private var isJapanese: Bool { language == .japanese }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dropArea
                    destination
                    settings
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        Button {
                            showsPreferences = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18))
                        }
                        .buttonStyle(.plain)
                        .help(t("環境設定", "Preferences"))
                    }
                    .padding(.bottom, 38)
                    Button(t("プリセット", "Presets"), action: openPresetWindow)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    executionDetails
                    Spacer(minLength: 0)
                    exportArea
                    progressStatus
                    logView
                }
                .padding(20)
            }
            .frame(width: 280)
        }
        .frame(width: (AppFontSize(rawValue: appFontSize) ?? .medium).windowWidth)
        .frame(minHeight: 560, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Sprout", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showsPreferences) {
            PreferencesView(appTheme: $appTheme, appLanguage: $appLanguage, appFontSize: $appFontSize)
        }
        .task(id: inspectionKey) {
            await refreshInspection()
        }
    }

    private var progressStatus: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(t("処理済み", "Processed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(completedFileCount)/\(totalFileCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: conversionProgress, total: 1)
                .progressViewStyle(.linear)
                .tint(accentGreen)
        }
        .padding(.top, 8)
        .accessibilityLabel(t("書き出し進捗", "Export progress"))
        .accessibilityValue("\(Int(conversionProgress * 100))%")
    }

    private var logView: some View {
        ScrollView {
            Text(logText.isEmpty ? t("ログはここに表示されます", "The log will appear here") : logText)
                .font(.caption.monospaced())
                .foregroundStyle(logText.isEmpty ? .tertiary : .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 90)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)) }
    }

    private var dropArea: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Spacer().frame(width: 24)
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: droppedURLs.isEmpty ? "arrow.down.doc" : "doc.on.doc.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(isTargeted ? accentGreen : .secondary)
                    Text(droppedFileLabel)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .truncationMode(.middle)
                    Text(t(
                        "複数ファイル、複数フォルダをまとめてドロップできます",
                        "Drop multiple files and folders together"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !droppedURLs.isEmpty {
                    Button {
                        droppedURLs.removeAll()
                        progressText = ""
                        conversionProgress = 0
                        completedFileCount = 0
                        totalFileCount = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(t("ドロップしたデータを削除", "Clear dropped items"))
                } else {
                    Spacer().frame(width: 24)
                }
            }
            if containsFolder {
                Toggle(
                    t("すべてのサブフォルダーを含める", "Include all subfolders"),
                    isOn: $includeSubfolders
                )
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120)
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
            conversionProgress = 0
            completedFileCount = 0
            totalFileCount = 0
            return true
        } isTargeted: { isTargeted = $0 }
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
                    HStack(spacing: 8) {
                        if options.saveSizeMode == .percent {
                            TextField("100", value: $options.percentage, format: .number)
                                .frame(width: 60)
                            Text("%").foregroundStyle(.secondary)
                        } else if options.saveSizeMode?.usesPixelValue == true {
                            TextField("2000", value: $options.edgePixels, format: .number)
                                .frame(width: 90)
                            Text("px").foregroundStyle(.secondary)
                        } else if options.saveSizeMode == .resolution {
                            Picker("", selection: $options.saveResolution) {
                                ForEach(SaveResolutionPreset.allCases) { preset in
                                    Text(preset == .custom ? t("カスタム", "Custom") : "\(preset.rawValue) dpi").tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 95)
                            if options.saveResolution == .custom {
                                TextField("200", value: $options.customSaveDPI, format: .number)
                                    .frame(width: 58)
                                Text("dpi").foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 6)

                        Picker("", selection: Binding(
                            get: { options.saveSizeMode ?? .percent },
                            set: { options.saveSizeMode = $0 }
                        )) {
                            ForEach(SaveSizeMode.allCases) { mode in
                                Text(saveSizeModeName(mode)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        .onChange(of: options.saveSizeMode) { mode in
                            if mode?.neverUpscales == true { options.allowsUpscaling = false }
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
                    .frame(width: 230, alignment: .leading)
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
                    .frame(width: 230, alignment: .leading)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var advancedSettings: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    settingLabel(t("保存", "Save"))
                    Toggle(
                        t("フォルダ構成を維持", "Preserve folder structure"),
                        isOn: $preservesFolderStructure
                    )
                    .disabled(!containsFolder)
                }
                if destinationMode == .sameLocation {
                    GridRow {
                        settingLabel("")
                        Toggle(
                            t(
                                "\(options.format.displayName)のフォルダを作成し、そこへ書き出す",
                                "Create a \(options.format.displayName) folder and export into it"
                            ),
                            isOn: Binding(
                                get: { options.sameLocationExportMode == .formatFolder },
                                set: { options.sameLocationExportMode = $0 ? .formatFolder : .directly }
                            )
                        )
                    }
                }
                GridRow {
                    settingLabel(t("リサイズ方式", "Resize method"))
                    Picker("", selection: $options.resizeMethod) {
                        ForEach(ResizeMethod.allCases) { method in
                            Text(resizeMethodName(method)).tag(method)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230, alignment: .leading)
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
                            .frame(width: 190, alignment: .leading)
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
                        .frame(width: 230, alignment: .leading)
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
                    DashedSeparator()
                        .gridCellColumns(2)
                        .padding(.vertical, 3)
                }
                GridRow {
                    settingLabel(t("メタデータ", "Metadata"))
                    Picker("", selection: $options.metadataMode) {
                        Text(t("保持", "Keep")).tag(MetadataMode.keep)
                        Text(t("破棄", "Discard")).tag(MetadataMode.discard)
                    }
                    .labelsHidden()
                    .frame(width: 230, alignment: .leading)
                }
                GridRow {
                    settingLabel("")
                    Toggle(t("作成日時を保持", "Preserve creation date"), isOn: $options.preservesFileDates)
                }
                GridRow {
                    DashedSeparator()
                        .gridCellColumns(2)
                        .padding(.vertical, 3)
                }
                GridRow {
                    settingLabel(t("ファイル名加工", "Filename processing"))
                    filenameProcessingControls
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filenameProcessingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((options.filenameOperations ?? []).indices), id: \.self) { index in
                let operation = Binding(
                    get: { (options.filenameOperations ?? [])[index] },
                    set: { options.filenameOperations?[index] = $0 }
                )
                HStack(alignment: .top, spacing: 6) {
                    Picker("", selection: operation.kind) {
                        Text(t("文字を追加", "Add text")).tag(FilenameOperationKind.add)
                        Text(t("文字を置換", "Replace text")).tag(FilenameOperationKind.replace)
                    }
                    .labelsHidden()
                    .frame(width: 105)
                    VStack(alignment: .leading, spacing: 5) {
                        if operation.wrappedValue.kind == .add {
                            TextField(t("追加文字", "Text to add"), text: operation.text)
                            Picker("", selection: operation.position) {
                                Text(t("先頭", "Beginning")).tag(TextAdditionPosition.beginning)
                                Text(t("末尾", "End")).tag(TextAdditionPosition.end)
                                Text(t("任意の位置", "Custom")).tag(TextAdditionPosition.custom)
                            }
                            .labelsHidden()
                            if operation.wrappedValue.position == .custom {
                                HStack(spacing: 5) {
                                    TextField("0", value: operation.customPosition, format: .number)
                                        .frame(width: 46)
                                    Text(t("文字目の後ろ", "characters after the start"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            TextField(t("検索文字", "Find"), text: operation.text)
                            TextField(t("置換文字", "Replace"), text: operation.replacement)
                        }
                    }
                    Button {
                        options.filenameOperations?.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            Menu(t("＋ 加工を追加", "+ Add operation")) {
                Button(t("文字を追加", "Add text")) { addFilenameOperation(.add) }
                Button(t("文字を置換", "Replace text")) { addFilenameOperation(.replace) }
            }
            HStack {
                Spacer()
                Text(processedSampleFilename)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addFilenameOperation(_ kind: FilenameOperationKind) {
        if options.filenameOperations == nil {
            options.filenameOperations = options.effectiveFilenameOperations
        }
        options.filenameOperations?.append(FilenameOperation(kind: kind))
    }

    private var processedSampleFilename: String {
        let sourceURL = (try? expandedInputs(from: droppedURLs).first?.url)
            ?? URL(fileURLWithPath: "/sample/00000.jpg")
        return OutputFilenameBuilder.filename(
            for: sourceURL,
            sequence: 1,
            format: options.format,
            options: options
        )
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
        lines.append(t(
            "ファイル名：\(filenamePreview)",
            "Filename: \(filenamePreview)"
        ))
        if inspection.pdfCount > 0 {
            lines.append(t("PDF読込解像度：\(options.effectivePDFDPI)dpi", "PDF import: \(options.effectivePDFDPI) dpi"))
        }
        return lines
    }

    private var filenamePreview: String {
        guard let inputs = try? expandedInputs(from: droppedURLs), !inputs.isEmpty else {
            return t("入力待ち", "Waiting for input")
        }
        let names = inputs.prefix(3).enumerated().map { index, input in
            OutputFilenameBuilder.filename(
                for: input.url,
                sequence: index + 1,
                format: options.format,
                options: options
            )
        }
        return names.joined(separator: "/") + (inputs.count > 3 ? "/…" : "")
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
        GroupBox(t("保存", "Save")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $destinationMode) {
                    Text(t("同じ場所に保存", "Save in the same location")).tag(DestinationMode.sameLocation)
                    Text(t("フォルダを選択", "Choose a folder")).tag(DestinationMode.selectedFolder)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if destinationMode == .selectedFolder {
                    HStack {
                        Button(t("フォルダを選択…", "Choose folder…"), action: chooseDestination)
                        Text(destinationDescription)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .padding(.top, 4)
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

    private func openPresetWindow() {
        if let controller = presetWindowController {
            if controller.window?.isVisible == true {
                controller.window?.orderOut(nil)
                return
            }
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 330),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = t("Sprout プリセット", "Sprout Presets")
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PresetWindowView(
            savedPresetsData: $savedPresetsData,
            options: $options,
            destinationMode: $destinationMode,
            destinationURL: $destinationURL,
            preservesFolderStructure: $preservesFolderStructure,
            presetName: $presetName,
            selectedPresetID: $selectedPresetID,
            alertMessage: $alertMessage,
            isJapanese: isJapanese,
            onDone: { [weak window] in window?.orderOut(nil) }
        ))
        let controller = NSWindowController(window: window)
        presetWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
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
        conversionProgress = 0
        completedFileCount = 0
        totalFileCount = 0
        progressText = t("変換を開始しています…", "Starting conversion…")
        logText = t("書き出しを開始しました", "Export started")

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
                totalFileCount = filesToConvert.count
                logText += t("\n対象：\(filesToConvert.count)ファイル", "\nFiles: \(filesToConvert.count)")
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
                        let itemProgress = total > 0 ? Double(completed) / Double(total) : 0
                        conversionProgress = min(
                            1,
                            (Double(fileIndex) + itemProgress) / Double(filesToConvert.count)
                        )
                        progressText = conversionLanguageIsJapanese
                            ? "ファイル \(fileIndex + 1)/\(filesToConvert.count)・\(completed)/\(total)"
                            : "File \(fileIndex + 1)/\(filesToConvert.count) · \(completed)/\(total)"
                    }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        completedFileCount = fileIndex + 1
                    }
                    logText += "\n[\(fileIndex + 1)/\(filesToConvert.count)] \(input.url.lastPathComponent)"
                }
                isConverting = false
                conversionProgress = 1
                alertMessage = conversionLanguageIsJapanese
                    ? "\(filesToConvert.count)個のファイルを変換しました。"
                    : "Converted \(filesToConvert.count) file(s)."
                logText += conversionLanguageIsJapanese ? "\n完了" : "\nCompleted"
            } catch {
                isConverting = false
                logText += "\nERROR: \(error.localizedDescription)"
                alertMessage = error.localizedDescription
            }
        }
    }

    private var containsFolder: Bool { droppedURLs.contains(where: isDirectory) }

    private var destinationDescription: String {
        switch destinationMode {
        case .sameLocation:
            if options.sameLocationExportMode == .formatFolder {
                return t(
                    "入力ファイルと同じ場所の「\(options.format.displayName)」フォルダ",
                    "A \(options.format.displayName) folder next to each source file"
                )
            }
            return t("入力ファイルと同じ場所", "Next to each source file")
        case .selectedFolder:
            return destinationURL?.path(percentEncoded: false)
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
            if let rootFolder = input.rootFolder {
                var base = options.sameLocationExportMode == .formatFolder
                    ? rootFolder.appendingPathComponent(options.format.displayName, isDirectory: true)
                    : rootFolder
                if preservesFolderStructure && !input.relativeDirectory.isEmpty {
                    base.appendPathComponent(input.relativeDirectory, isDirectory: true)
                }
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                return base
            }
            let sourceFolder = input.url.deletingLastPathComponent()
            guard options.sameLocationExportMode == .formatFolder else { return sourceFolder }
            let formatFolder = sourceFolder.appendingPathComponent(options.format.displayName, isDirectory: true)
            try FileManager.default.createDirectory(at: formatFolder, withIntermediateDirectories: true)
            return formatFolder
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

private struct DashedSeparator: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0.5))
            }
            .stroke(Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 1)
    }
}

private struct PreferencesView: View {
    @Binding var appTheme: String
    @Binding var appLanguage: String
    @Binding var appFontSize: String
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
                Picker(t("フォントサイズ", "Font size"), selection: $appFontSize) {
                    Text("S").tag(AppFontSize.small.rawValue)
                    Text("M").tag(AppFontSize.medium.rawValue)
                    Text("L").tag(AppFontSize.large.rawValue)
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button(t("完了", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360, height: 280)
    }
}

struct HelpView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue
    private var japanese: Bool { appLanguage == AppLanguage.japanese.rawValue }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(japanese ? "Sproutの使い方" : "Using Sprout").font(.largeTitle.bold())
                helpSection(japanese ? "基本操作" : "Basics", japanese
                    ? "PNG、JPG、PDF、PSD、TIFF、GIF、WebP、またはそれらを含むフォルダをドロップします。保存先、保存サイズ、形式、カラーを設定し、「画像を書き出す」を押してください。複数形式を同時に処理できます。処理状況とコピー可能なログは右下に表示されます。"
                    : "Drop PNG, JPG, PDF, PSD, TIFF, GIF, WebP, or folders containing them. Choose the destination and output settings, then click Export images. Progress and a selectable log appear at bottom right.")
                helpSection("PDF", japanese
                    ? "PDFは指定した読込解像度でページごとに画像化され、その後に保存サイズ設定が適用されます。PDF内のベクター、文字、透明、RGB・CMYK・特色は最終的に1枚のピクセル画像へ統合されます。元の編集構造は保持されません。"
                    : "Each PDF page is rasterized at the selected import DPI, then resized. Vector objects, text, transparency and color spaces are flattened into one pixel image; editable structure is not preserved.")
                helpSection("PSD / TIFF / GIF", japanese
                    ? "PSDはPhotoshop保存時に生成される統合画像（Composite Image）を使用します。レイヤー、マスク、スマートオブジェクト、調整レイヤー、効果は保持・再構築しません。統合画像が保存されていないPSDは読み込めない場合があります。TIFFもレイヤーを保持しません。TIFF規格は複数画像を格納できるため、そのような特殊なTIFFを読み込んだ場合は各画像を書き出します。一般的な写真TIFFは通常1画像です。アニメーションGIFは先頭フレームのみ使用します。"
                    : "PSD uses the Composite Image generated when Photoshop saves the file. Layers, masks, smart objects, adjustments and effects are not reconstructed. PSD files saved without a composite may fail. TIFF layers are not preserved. The TIFF format can technically contain multiple images; Sprout exports each one when encountered, though ordinary photo TIFF files usually contain one. Animated GIF uses only its first frame.")
                helpSection(japanese ? "保存サイズとリサイズ" : "Sizing and resizing", japanese
                    ? "100%は元のピクセル数を維持します。「以内」は小さい画像を拡大しません。長辺・短辺・幅・高さ指定は縦横比を維持します。解像度（DPI）を選ぶと、通常画像も「指定DPI ÷ 元画像DPI」の倍率でピクセル寸法を変更し、印刷上の実寸を維持します。元画像にDPI情報がない場合は72dpiとして計算します。たとえば元が72dpiの画像を300dpiにすると、縦横は約4.17倍になります。大幅な拡大では画質が低下します。Sproutの自動、バイキュービック、シャープ、スムーズはAppleの画像処理を利用しており、Photoshopの同名方式と計算やシャープ量が完全に同一ではありません。重要な案件では結果を事前確認してください。"
                    : "100% preserves pixel dimensions. 'Within' modes never enlarge smaller images, and edge/width/height modes preserve aspect ratio. DPI mode also resizes ordinary images by target DPI divided by source DPI, preserving physical print size. Images without DPI metadata are treated as 72 dpi. For example, 72 to 300 dpi enlarges each dimension by about 4.17× and may reduce quality. Sprout uses Apple imaging; its Automatic and bicubic variants are not numerically identical to Photoshop's similarly named methods. Verify critical output.")
                helpSection(japanese ? "カラー・形式" : "Color and formats", japanese
                    ? "カラー変換後、ICCを埋め込む設定を選べます。プロファイルを埋め込まない場合、他アプリで色の見え方が変わる可能性があります。JPEGは透過を保持できません。PNG圧縮率は画質ではなく処理時間と容量に影響します。WebP品質は非可逆圧縮品質です。16 bitは対応する入力・出力形式でのみ有効です。"
                    : "You can embed the ICC profile after color conversion. Without it, other apps may display color differently. JPEG cannot preserve transparency. PNG compression affects speed and size, not quality. WebP quality controls lossy compression. 16-bit is used only where supported.")
                helpSection(japanese ? "ファイル名・保存先・プリセット" : "Names, destinations and presets", japanese
                    ? "文字追加・置換は複数登録でき、上から順に適用されます。同名ファイルには (1)、(2) が付き、既存ファイルを上書きしません。同じ場所へ直接保存するか、形式名のフォルダを作成できます。フォルダ入力では構成維持を選べます。プリセットには設定値を保存しますが、選択した保存先URLそのものは保存しません。"
                    : "Add/replace operations can be stacked and run from top to bottom. Name collisions receive (1), (2), and so on; existing files are not overwritten. Export beside sources or into a format-named folder. Folder structure can be preserved for folder input. Presets store settings, but not the chosen destination URL itself.")
                helpSection(japanese ? "プライバシー" : "Privacy", japanese
                    ? "変換はMac内で完結します。入力ファイルをネットワークへ送信せず、ネットワーク権限も使用しません。"
                    : "Conversion is local to your Mac. Input files are not uploaded and no network permission is used.")
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func helpSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.bold())
            Text(body).textSelection(.enabled).lineSpacing(3)
        }
    }
}
