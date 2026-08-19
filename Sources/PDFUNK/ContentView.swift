import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum DestinationBookmarkStore {
    private static let selectedDestinationKey = "selectedDestinationBookmark"
    private static let sourceFoldersKey = "sourceFolderBookmarks"

    static func saveSelectedDestination(_ url: URL) throws {
        UserDefaults.standard.set(try bookmarkData(for: url), forKey: selectedDestinationKey)
    }

    static func selectedDestination() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: selectedDestinationKey) else { return nil }
        return resolve(data, removingStaleValueForKey: selectedDestinationKey)
    }

    static func saveSourceFolder(_ url: URL) throws {
        var bookmarks = sourceFolderBookmarks
        bookmarks[url.standardizedFileURL.path] = try bookmarkData(for: url)
        UserDefaults.standard.set(bookmarks, forKey: sourceFoldersKey)
    }

    static func sourceFolder(containing url: URL) -> URL? {
        let targetPath = url.standardizedFileURL.path
        let candidatePaths = sourceFolderBookmarks.keys
            .filter { targetPath == $0 || targetPath.hasPrefix($0 + "/") }
            .sorted { $0.count > $1.count }

        for path in candidatePaths {
            guard let data = sourceFolderBookmarks[path] else { continue }
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale, resolved.standardizedFileURL.path == path {
                return resolved
            }
            removeSourceFolder(path: path)
        }
        return nil
    }

    private static var sourceFolderBookmarks: [String: Data] {
        UserDefaults.standard.dictionary(forKey: sourceFoldersKey) as? [String: Data] ?? [:]
    }

    private static func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolve(_ data: Data, removingStaleValueForKey key: String) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return url
    }

    private static func removeSourceFolder(path: String) {
        var bookmarks = sourceFolderBookmarks
        bookmarks.removeValue(forKey: path)
        UserDefaults.standard.set(bookmarks, forKey: sourceFoldersKey)
    }
}

private struct MainContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum SproutsPalette {
    static let accent = Color(red: 0.26, green: 0.56, blue: 0.79)
    static let selectionAccent = Color(red: 0.47, green: 0.78, blue: 0.60)
    static let selectionForeground = Color(red: 0.08, green: 0.22, blue: 0.14)
    static let dropIcon = Color(red: 0.66, green: 0.42, blue: 0.23)

    static func windowBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.114, green: 0.122, blue: 0.133)
            : Color(red: 0.941, green: 0.949, blue: 0.957)
    }

    static func sidebarBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.125, green: 0.133, blue: 0.149)
            : Color(red: 0.914, green: 0.925, blue: 0.937)
    }

    static func panelBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.141, green: 0.149, blue: 0.165)
            : Color(red: 0.976, green: 0.980, blue: 0.984)
    }

    static func panelHeader(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.173, green: 0.180, blue: 0.200)
            : Color(red: 0.925, green: 0.937, blue: 0.949)
    }

    static func controlBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.204, green: 0.216, blue: 0.235)
            : .white
    }

    static func insetBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.090, green: 0.098, blue: 0.110)
            : Color(red: 0.965, green: 0.969, blue: 0.976)
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.067, green: 0.075, blue: 0.086)
            : Color(red: 0.733, green: 0.757, blue: 0.784)
    }
}

private struct SproutsPanelGroupBoxStyle: GroupBoxStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(SproutsPalette.panelHeader(colorScheme))

            Rectangle()
                .fill(SproutsPalette.border(colorScheme))
                .frame(height: 1)

            configuration.content
                .padding(11)
        }
        .background(SproutsPalette.panelBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(SproutsPalette.border(colorScheme), lineWidth: 1)
        }
        .shadow(color: colorScheme == .dark ? .black.opacity(0.18) : .black.opacity(0.06), radius: 2, y: 1)
    }
}

private struct SproutsFormatButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isSelected ? SproutsPalette.selectionForeground : Color.secondary)
            .padding(.horizontal, 9)
            .frame(minWidth: 44, minHeight: 27)
            .background {
                if isSelected {
                    LinearGradient(
                        colors: [SproutsPalette.selectionAccent.opacity(0.98), SproutsPalette.selectionAccent.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    SproutsPalette.controlBackground(colorScheme)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        isSelected ? SproutsPalette.selectionAccent.opacity(0.92) : SproutsPalette.border(colorScheme),
                        lineWidth: 1
                    )
            }
            .shadow(color: isSelected ? SproutsPalette.selectionAccent.opacity(0.18) : .clear, radius: 3, y: 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct SproutsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 18)
            .frame(minHeight: 36)
            .background {
                LinearGradient(
                    colors: isEnabled
                        ? [SproutsPalette.accent.opacity(0.98), SproutsPalette.accent.opacity(0.76)]
                        : [Color.gray.opacity(0.30), Color.gray.opacity(0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isEnabled ? SproutsPalette.accent.opacity(0.92) : Color.gray.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: isEnabled ? SproutsPalette.accent.opacity(0.20) : .clear, radius: 5, y: 2)
            .opacity(configuration.isPressed ? 0.80 : 1)
    }
}

private struct SproutsSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 29)
            .background(SproutsPalette.controlBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(SproutsPalette.border(colorScheme), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

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

private struct SproutsPreset: Codable, Identifiable {
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
    @Environment(\.colorScheme) private var colorScheme

    private var savedPresets: [SproutsPreset] {
        guard let data = savedPresetsData.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SproutsPreset].self, from: data)) ?? []
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
        .tint(SproutsPalette.selectionAccent)
        .background(SproutsPalette.windowBackground(colorScheme))
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
            let preset = SproutsPreset(
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
        destinationURL = preset.destinationMode == .selectedFolder
            ? DestinationBookmarkStore.selectedDestination()
            : nil
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
    private func persistPresets(_ presets: [SproutsPreset]) -> Bool {
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
    @AppStorage("appTheme") private var appTheme = AppTheme.dark.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue
    @AppStorage("showsAdvancedSettings") private var showsAdvancedSettings = false
    @AppStorage("savedPresets") private var savedPresetsData = ""
    @AppStorage("showsInspectorSidebar") private var showsInspectorSidebar = false
    @AppStorage("requiredMainContentHeight") private var requiredMainContentHeight: Double = 0
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
    @State private var inspection = InputInspection()
    @State private var showsExecutionDetails = true
    @State private var presetName = ""
    @State private var selectedPresetID: UUID?
    @State private var presetWindowController: NSWindowController?
    @State private var conversionProgress = 0.0
    @State private var completedFileCount = 0
    @State private var totalFileCount = 0
    @State private var logText = ""
    @Environment(\.colorScheme) private var colorScheme

    init() {
        _destinationURL = State(initialValue: DestinationBookmarkStore.selectedDestination())
    }

    private var language: AppLanguage { AppLanguage(rawValue: appLanguage) ?? .japanese }
    private var isJapanese: Bool { language == .japanese }
    private let uiFontSize = AppLayout()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Spacer()
                            if !showsInspectorSidebar {
                                Button {
                                    showsInspectorSidebar = true
                                } label: {
                                    Image(systemName: "chevron.right.2")
                                        .font(.system(size: 11 * uiFontSize.scale, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .help(t("サイドバーを表示", "Show inspector sidebar"))
                            }
                        }
                        dropArea
                            .frame(width: 280 * uiFontSize.scale)
                            .frame(maxWidth: .infinity, alignment: .center)
                        settings
                        destination
                        advancedSettingsDisclosure
                    }
                    .padding(16 * uiFontSize.scale)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MainContentHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .onPreferenceChange(MainContentHeightPreferenceKey.self) { measuredHeight in
                    guard showsAdvancedSettings, measuredHeight > 0 else { return }
                    let heightIncludingExportArea = ceil(measuredHeight + 74 * uiFontSize.scale)
                    if abs(CGFloat(requiredMainContentHeight) - heightIncludingExportArea) > 1 {
                        requiredMainContentHeight = Double(heightIncludingExportArea)
                    }
                }
                exportArea
                    .padding(.horizontal, 16 * uiFontSize.scale)
                    .padding(.vertical, 16 * uiFontSize.scale)
            }
            .frame(minWidth: uiFontSize.compactWidth, maxWidth: .infinity)
            .background(SproutsPalette.windowBackground(colorScheme))

            if showsInspectorSidebar {
                Divider()
                    .overlay(SproutsPalette.border(colorScheme))
                ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        Button {
                            showsInspectorSidebar = false
                        } label: {
                            Image(systemName: "chevron.left.2")
                                .font(.system(size: 11 * uiFontSize.scale, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help(t("サイドバーを閉じる", "Hide inspector sidebar"))
                    }
                    Button(t("プリセット", "Presets"), action: openPresetWindow)
                        .buttonStyle(SproutsSecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
                    executionDetails
                    Spacer(minLength: 0)
                    progressStatus
                    logView
                }
                .padding(18 * uiFontSize.scale)
                }
                .frame(width: uiFontSize.sidebarWidth)
                .background(SproutsPalette.sidebarBackground(colorScheme))
                .transition(.move(edge: .trailing))
            }
        }
        .frame(
            minWidth: uiFontSize.compactWidth + (showsInspectorSidebar ? uiFontSize.sidebarWidth : 0),
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .tint(SproutsPalette.selectionAccent)
        .background(SproutsPalette.windowBackground(colorScheme))
        .alert("Sprouts", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
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
                .tint(SproutsPalette.accent)
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
        .background(SproutsPalette.insetBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(SproutsPalette.border(colorScheme)) }
    }

    private var dropArea: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Spacer().frame(width: 24)
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: droppedURLs.isEmpty ? "arrow.down.doc" : "doc.on.doc.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(isTargeted ? SproutsPalette.dropIcon : SproutsPalette.dropIcon.opacity(0.88))
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
                    if inspection.fileCount > 0 {
                        Text(dropInspectionSummary)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
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
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(isTargeted ? SproutsPalette.selectionAccent.opacity(0.12) : SproutsPalette.panelBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isTargeted ? SproutsPalette.selectionAccent : SproutsPalette.border(colorScheme),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4], dashPhase: 0)
                )
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

                if let validationMessage = options.validationMessage(isJapanese: isJapanese) {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .groupBoxStyle(SproutsPanelGroupBoxStyle())
    }

    private var advancedSettingsDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showsAdvancedSettings.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: showsAdvancedSettings ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 10)
                    Text(t("詳細設定", "Advanced settings"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsAdvancedSettings {
                advancedSettings
                    .padding(12)
                    .background(SproutsPalette.panelBackground(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(SproutsPalette.border(colorScheme), lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                                    Text(preset == .custom ? t("カスタム", "Custom") : "\(preset.rawValue) ppi").tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 95)
                            if options.saveResolution == .custom {
                                TextField("200", value: $options.customSaveDPI, format: .number)
                                    .frame(width: 58)
                                Text("ppi").foregroundStyle(.secondary)
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
                    HStack(spacing: 6) {
                        ForEach(ExportFormat.allCases) { format in
                            if options.isSelected(format) {
                                Button(format.displayName) {
                                    options.setSelected(format, to: false)
                                }
                                .buttonStyle(SproutsFormatButtonStyle(isSelected: true))
                                .accessibilityValue(t("選択中", "Selected"))
                            } else {
                                Button(format.displayName) {
                                    options.setSelected(format, to: true)
                                }
                                .buttonStyle(SproutsFormatButtonStyle(isSelected: false))
                                .accessibilityValue(t("未選択", "Not selected"))
                            }
                        }
                    }
                    .frame(width: 230, alignment: .leading)
                }
                if options.isSelected(.jpg) {
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
                if options.isSelected(.webp) {
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
                    settingLabel(t("カラープロファイル", "Color profile"))
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
                GridRow {
                    settingLabel("")
                    Toggle(
                        t(
                            "形式ごとのフォルダを作成し、そこへ書き出す",
                            "Create a folder for each format and export into it"
                        ),
                        isOn: Binding(
                            get: { options.usesFormatFolders },
                            set: { options.sameLocationExportMode = $0 ? .formatFolder : .directly }
                        )
                    )
                }
                GridRow {
                    settingLabel("")
                    Toggle(
                        t("完了時にフォルダを開く", "Open folder when complete"),
                        isOn: Binding(
                            get: { options.shouldOpenDestinationWhenComplete },
                            set: { options.opensDestinationWhenComplete = $0 }
                        )
                    )
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
                        settingLabel(t("PDF読込解像度", "PDF import PPI"))
                        HStack {
                            Picker("", selection: $options.pdfResolution) {
                                ForEach(PDFResolutionPreset.allCases) { preset in
                                    Text(preset == .custom ? t("カスタム", "Custom") : "\(preset.rawValue) ppi").tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190, alignment: .leading)
                            if options.pdfResolution == .custom {
                                TextField("200", value: $options.customPDFDPI, format: .number)
                                    .frame(width: 72)
                                Text("ppi").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if options.isSelected(.png) || options.isSelected(.tiff) {
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
                if options.isSelected(.png) {
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
                if options.isSelected(.tiff) {
                    GridRow {
                        settingLabel(t("TIFF圧縮", "TIFF compression"))
                        Picker("", selection: Binding(
                            get: { options.tiffCompression ?? .lzw },
                            set: { options.tiffCompression = $0 }
                        )) {
                            Text(t("なし", "None")).tag(TIFFCompression.none)
                            Text("LZW").tag(TIFFCompression.lzw)
                            Text("ZIP").tag(TIFFCompression.zip)
                        }
                        .labelsHidden()
                        .frame(width: 230, alignment: .leading)
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
                .background(SproutsPalette.controlBackground(colorScheme))
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
        return options.selectedFormats.map { format in
            OutputFilenameBuilder.filename(
                for: sourceURL,
                sequence: 1,
                format: format,
                options: options
            )
        }.joined(separator: " / ")
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
        .background(SproutsPalette.panelBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(SproutsPalette.border(colorScheme), lineWidth: 1)
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
        let formatNames = options.selectedFormats.map(\.displayName).joined(separator: " + ")
        let outputCount = inspection.outputImageCount * options.selectedFormats.count
        var lines = [t(
            "合計\(outputCount)枚（\(formatNames)）を書き出します",
            "Export \(outputCount) image(s) as \(formatNames)"
        )]
        lines.append(t("保存サイズ：\(saveSizeDescription)", "Save size: \(saveSizeDescription)"))
        lines.append(t("リサイズ方式：\(resizeMethodName(options.resizeMethod))", "Resize method: \(resizeMethodName(options.resizeMethod))"))
        lines.append(t(
            "カラープロファイル：\(colorProfileName(options.colorProfile))",
            "Color profile: \(colorProfileName(options.colorProfile))"
        ))
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
            lines.append(t("PDF読込解像度：\(options.effectivePDFDPI)ppi", "PDF import: \(options.effectivePDFDPI) ppi"))
        }
        return lines
    }

    private var filenamePreview: String {
        guard let inputs = try? expandedInputs(from: droppedURLs), !inputs.isEmpty else {
            return t("入力待ち", "Waiting for input")
        }
        let names = inputs.prefix(3).enumerated().flatMap { index, input in
            options.selectedFormats.map { format in
                OutputFilenameBuilder.filename(
                    for: input.url,
                    sequence: index + 1,
                    format: format,
                    options: options
                )
            }
        }
        return names.joined(separator: "/") + (inputs.count > 3 ? "/…" : "")
    }

    private var warningDetailLines: [String] {
        var lines: [String] = []
        if inspection.pdfCount > 0 {
            lines.append(t("PDFは\(options.effectivePDFDPI)ppiで画像化します", "PDFs are rasterized at \(options.effectivePDFDPI) ppi"))
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
        if options.isSelected(.jpg) && inspection.mayContainTransparency {
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
            options.resizeMethod.rawValue,
            options.selectedFormats.map(\.rawValue).joined(separator: ",")
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
        case .resolution?: "\(options.saveDPI)ppi"
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
        .groupBoxStyle(SproutsPanelGroupBoxStyle())
    }

    private var exportArea: some View {
        VStack(alignment: .center, spacing: 8) {
            if !progressText.isEmpty {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Button(isConverting ? t("変換中…", "Converting…") : t("画像を書き出す", "Export images"), action: export)
                .buttonStyle(SproutsPrimaryButtonStyle())
                .frame(minWidth: 156 * uiFontSize.scale, minHeight: 38 * uiFontSize.scale)
                .disabled(
                    droppedURLs.isEmpty
                        || (destinationMode == .selectedFolder && destinationURL == nil)
                        || isConverting
                        || !selectedOptionsAreImplemented
                )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var borderColor: Color { SproutsPalette.border(colorScheme) }

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
            contentRect: NSRect(x: 0, y: 0, width: 360 * uiFontSize.scale, height: 330 * uiFontSize.scale),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = t("Sprouts プリセット", "Sprouts Presets")
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
        )
        .environment(\.dynamicTypeSize, uiFontSize.dynamicTypeSize)
        .environment(\.controlSize, uiFontSize.controlSize))
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

    private var dropInspectionSummary: String {
        let formats = inspection.formatCounts.keys.sorted().map {
            "\($0) \(inspection.formatCounts[$0] ?? 0)"
        }.joined(separator: " · ")
        return t(
            "画像合計 \(inspection.outputImageCount)枚 · 入力 \(inspection.fileCount)件\(formats.isEmpty ? "" : " · \(formats)")",
            "\(inspection.outputImageCount) images · \(inspection.fileCount) inputs\(formats.isEmpty ? "" : " · \(formats)")"
        )
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = t("画像の保存先を選択", "Choose an output folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try DestinationBookmarkStore.saveSelectedDestination(url)
                destinationURL = url
            } catch {
                alertMessage = t(
                    "保存先のアクセス権を保存できませんでした：\(error.localizedDescription)",
                    "Could not remember output-folder access: \(error.localizedDescription)"
                )
            }
        }
    }

    private func export() {
        guard !droppedURLs.isEmpty else { return }
        let roots = droppedURLs
        guard let sourceFolderAccessURLs = requestSourceFolderWriteAccessIfNeeded(for: roots) else { return }
        let conversionLanguageIsJapanese = isJapanese
        let conversionOptions = options
        let selectedFormats = conversionOptions.selectedFormats
        isConverting = true
        conversionProgress = 0
        completedFileCount = 0
        totalFileCount = 0
        progressText = t("変換を開始しています…", "Starting conversion…")
        logText = t("書き出しを開始しました", "Export started")

        Task {
            let selectedDestination = destinationURL
            let securityScopedURLs = roots + sourceFolderAccessURLs + (selectedDestination.map { [$0] } ?? [])
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
                let totalJobs = filesToConvert.count * selectedFormats.count
                totalFileCount = totalJobs
                logText += t(
                    "\n対象：\(filesToConvert.count)ファイル × \(selectedFormats.count)形式",
                    "\nFiles: \(filesToConvert.count) × \(selectedFormats.count) format(s)"
                )
                let outputSequence = OutputSequence()
                var exportedURLs: [URL] = []
                for (fileIndex, input) in filesToConvert.enumerated() {
                    for (formatIndex, format) in selectedFormats.enumerated() {
                        let jobIndex = fileIndex * selectedFormats.count + formatIndex
                        let formatOptions = conversionOptions.options(for: format)
                        let outputBase = try outputBaseURL(
                            for: input,
                            format: format,
                            selectedDestination: selectedDestination,
                            exportOptions: conversionOptions
                        )
                        let createdURLs = try await FileConverter().convert(
                            inputURL: input.url,
                            destinationURL: outputBase,
                            options: formatOptions,
                            sequence: outputSequence,
                            isJapanese: conversionLanguageIsJapanese
                        ) { completed, total in
                            let itemProgress = total > 0 ? Double(completed) / Double(total) : 0
                            conversionProgress = min(
                                1,
                                (Double(jobIndex) + itemProgress) / Double(totalJobs)
                            )
                            progressText = conversionLanguageIsJapanese
                                ? "ファイル \(fileIndex + 1)/\(filesToConvert.count)・\(format.displayName)・\(completed)/\(total)"
                                : "File \(fileIndex + 1)/\(filesToConvert.count) · \(format.displayName) · \(completed)/\(total)"
                        }
                        exportedURLs.append(contentsOf: createdURLs)
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            completedFileCount = jobIndex + 1
                        }
                    }
                    logText += "\n[\(fileIndex + 1)/\(filesToConvert.count)] \(input.url.lastPathComponent)"
                }
                isConverting = false
                conversionProgress = 1
                alertMessage = conversionLanguageIsJapanese
                    ? "\(filesToConvert.count)個のファイルを\(selectedFormats.count)形式へ変換しました。"
                    : "Converted \(filesToConvert.count) file(s) into \(selectedFormats.count) format(s)."
                logText += conversionLanguageIsJapanese ? "\n完了" : "\nCompleted"
                if conversionOptions.shouldOpenDestinationWhenComplete {
                    NSWorkspace.shared.activateFileViewerSelecting(exportedURLs)
                }
            } catch {
                isConverting = false
                logText += "\nERROR: \(error.localizedDescription)"
                alertMessage = error.localizedDescription
            }
        }
    }

    private func requestSourceFolderWriteAccessIfNeeded(for roots: [URL]) -> [URL]? {
        guard destinationMode == .sameLocation else { return [] }
        let parents = Dictionary(grouping: roots.filter { !isDirectory($0) }) {
            $0.deletingLastPathComponent().standardizedFileURL
        }.keys.sorted { $0.path < $1.path }
        var granted: [URL] = []
        for parent in parents {
            if let restored = DestinationBookmarkStore.sourceFolder(containing: parent) {
                granted.append(restored)
                continue
            }
            let panel = NSOpenPanel()
            panel.title = t("保存先へのアクセス", "Output Folder Access")
            panel.message = t(
                "「\(parent.lastPathComponent)」または上位フォルダを選択してください。上位フォルダを選ぶと、その配下では次回から確認されません。",
                "Select “\(parent.lastPathComponent)” or one of its parent folders. Choosing a parent avoids future prompts anywhere inside it."
            )
            panel.prompt = t("アクセスを許可", "Allow Access")
            panel.directoryURL = parent
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let selected = panel.url else { return nil }
            let selectedPath = selected.standardizedFileURL.path
            let parentPath = parent.standardizedFileURL.path
            guard parentPath == selectedPath || parentPath.hasPrefix(selectedPath + "/") else {
                alertMessage = t(
                    "入力ファイルのあるフォルダ、またはその上位フォルダを選択してください。",
                    "Select the folder containing the input file or one of its parent folders."
                )
                return nil
            }
            do {
                try DestinationBookmarkStore.saveSourceFolder(selected)
                granted.append(selected)
            } catch {
                alertMessage = t(
                    "フォルダのアクセス権を保存できませんでした：\(error.localizedDescription)",
                    "Could not remember folder access: \(error.localizedDescription)"
                )
                return nil
            }
        }
        return granted
    }

    private var containsFolder: Bool { droppedURLs.contains(where: isDirectory) }

    private var destinationDescription: String {
        switch destinationMode {
        case .sameLocation:
            if options.usesFormatFolders {
                let formatNames = options.selectedFormats.map(\.displayName).joined(separator: " / ")
                return t(
                    "入力ファイルと同じ場所の形式別フォルダ（\(formatNames)）",
                    "Format folders next to each source file (\(formatNames))"
                )
            }
            return t("入力ファイルと同じ場所", "Next to each source file")
        case .selectedFolder:
            guard let path = destinationURL?.path(percentEncoded: false) else {
                return t("保存先を選択してください", "Choose an output folder")
            }
            if options.usesFormatFolders {
                let formatNames = options.selectedFormats.map(\.displayName).joined(separator: " / ")
                return t(
                    "\(path) 内の形式別フォルダ（\(formatNames)）",
                    "Format folders in \(path) (\(formatNames))"
                )
            }
            return path
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

    private func outputBaseURL(
        for input: ConversionInput,
        format: ExportFormat,
        selectedDestination: URL?,
        exportOptions: ExportOptions
    ) throws -> URL {
        if destinationMode == .sameLocation {
            if let rootFolder = input.rootFolder {
                var base = exportOptions.usesFormatFolders
                    ? rootFolder.appendingPathComponent(format.displayName, isDirectory: true)
                    : rootFolder
                if preservesFolderStructure && !input.relativeDirectory.isEmpty {
                    base.appendPathComponent(input.relativeDirectory, isDirectory: true)
                }
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                return base
            }
            let sourceFolder = input.url.deletingLastPathComponent()
            guard exportOptions.usesFormatFolders else { return sourceFolder }
            let formatFolder = sourceFolder.appendingPathComponent(format.displayName, isDirectory: true)
            try FileManager.default.createDirectory(at: formatFolder, withIntermediateDirectories: true)
            return formatFolder
        }
        guard var base = selectedDestination else {
            throw ConversionError.incompatibleOptions(t("保存先を選択してください。", "Choose an output folder."))
        }
        if exportOptions.usesFormatFolders {
            base.appendPathComponent(format.displayName, isDirectory: true)
        }
        if preservesFolderStructure, let root = input.rootFolder {
            base.appendPathComponent(root.lastPathComponent, isDirectory: true)
            if !input.relativeDirectory.isEmpty {
                base.appendPathComponent(input.relativeDirectory, isDirectory: true)
            }
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
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

struct PreferencesView: View {
    @Binding var appTheme: String
    @Binding var appLanguage: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
        .frame(width: 360, height: 220)
        .tint(SproutsPalette.selectionAccent)
        .background(SproutsPalette.windowBackground(colorScheme))
    }
}

struct HelpView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue
    @Environment(\.colorScheme) private var colorScheme
    private var japanese: Bool { appLanguage == AppLanguage.japanese.rawValue }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(japanese ? "Sproutsの使い方" : "Using Sprouts").font(.largeTitle.bold())
                helpSection(japanese ? "基本操作" : "Basics", japanese
                    ? "PNG、JPG、PDF、PSD、TIFF、GIF、WebP、またはそれらを含むフォルダをドロップします。保存先、保存サイズ、形式、カラーを設定し、「画像を書き出す」を押してください。複数形式を同時に処理できます。処理状況とコピー可能なログは右下に表示されます。"
                    : "Drop PNG, JPG, PDF, PSD, TIFF, GIF, WebP, or folders containing them. Choose the destination and output settings, then click Export images. Progress and a selectable log appear at bottom right.")
                helpSection("PDF", japanese
                    ? "PDFは指定した読込解像度でページごとに画像化され、その後に保存サイズ設定が適用されます。PDF内のベクター、文字、透明、RGB・CMYK・特色は最終的に1枚のピクセル画像へ統合されます。元の編集構造は保持されません。"
                    : "Each PDF page is rasterized at the selected import PPI, then resized. Vector objects, text, transparency and color spaces are flattened into one pixel image; editable structure is not preserved.")
                helpSection("PSD / TIFF / GIF", japanese
                    ? "PSDはPhotoshop保存時に生成される統合画像（Composite Image）を使用します。レイヤー、マスク、スマートオブジェクト、調整レイヤー、効果は保持・再構築しません。統合画像が保存されていないPSDは読み込めない場合があります。TIFFもレイヤーを保持しません。TIFF規格は複数画像を格納できるため、そのような特殊なTIFFを読み込んだ場合は各画像を書き出します。一般的な写真TIFFは通常1画像です。アニメーションGIFは先頭フレームのみ使用します。"
                    : "PSD uses the Composite Image generated when Photoshop saves the file. Layers, masks, smart objects, adjustments and effects are not reconstructed. PSD files saved without a composite may fail. TIFF layers are not preserved. The TIFF format can technically contain multiple images; Sprouts exports each one when encountered, though ordinary photo TIFF files usually contain one. Animated GIF uses only its first frame.")
                helpSection(japanese ? "保存サイズとリサイズ" : "Sizing and resizing", japanese
                    ? "100%は元のピクセル数を維持します。\n\n「長辺ピクセル」「短辺ピクセル」は、指定した辺が入力より大きい場合も、その値になるまで拡大します。たとえば長辺1200pxの画像に「長辺2400px」を指定すると、縦横を2倍にして長辺2400pxで保存します。縦横比は常に維持されます。\n\n「長辺px以内」「短辺px以内」は上限指定です。上限を超える画像だけ縮小し、小さい画像は拡大しません。たとえば長辺1200pxの画像に「長辺2400px以内」を指定しても1200pxのままです。「幅／高さ」は指定値まで拡大・縮小し、「幅以内／高さ以内」は上限を超える場合だけ縮小します。\n\n解像度（PPI）は「指定PPI ÷ 元画像PPI」の倍率で通常画像のピクセル寸法を変更し、印刷上の実寸を維持します。PPI情報がない画像は72ppiとして計算します。72ppiから300ppiでは縦横が約4.17倍になります。PDFは指定PPIで各ページを画像化してから保存サイズを適用します。\n\n拡大処理は存在しない細部を復元するものではなく、ぼけ、輪郭の甘さ、圧縮ノイズの拡大が起こる場合があります。Sproutsの自動、バイキュービック、シャープ、スムーズはAppleの画像処理を利用しており、Photoshopの同名方式と計算やシャープ量が完全に同一ではありません。重要な案件では結果を事前確認してください。"
                    : "100% preserves the original pixel dimensions.\n\nLong Edge Pixels and Short Edge Pixels resize to the exact requested edge even when that requires enlargement. For example, applying Long Edge 2400 px to a 1200 px image doubles both dimensions while preserving aspect ratio.\n\nLong Edge Maximum and Short Edge Maximum are upper limits: only larger images are reduced, and smaller images are never enlarged. Width and Height resize to the requested value; Width Maximum and Height Maximum only reduce images that exceed the limit. Aspect ratio is always preserved.\n\nPPI mode resizes ordinary images by target PPI divided by source PPI to preserve physical print size. Images without PPI metadata are treated as 72 ppi, so 72 to 300 ppi enlarges each dimension by about 4.17×. PDF pages are first rasterized at the selected PPI and then processed by the save-size setting.\n\nUpscaling cannot recreate missing detail and may magnify softness or compression artifacts. Sprouts uses Apple imaging; its Automatic and bicubic variants are not numerically identical to Photoshop's similarly named methods. Verify critical output.")
                helpSection(japanese ? "カラープロファイル・形式" : "Color profiles and formats", japanese
                    ? "カラー変換後、ICCを埋め込む設定を選べます。プロファイルを埋め込まない場合、他アプリで色の見え方が変わる可能性があります。JPEGは透過を保持できません。PNG圧縮率は画質ではなく処理時間と容量に影響します。WebP品質は非可逆圧縮品質です。16 bitは対応する入力・出力形式でのみ有効です。"
                    : "You can embed the ICC profile after color conversion. Without it, other apps may display color differently. JPEG cannot preserve transparency. PNG compression affects speed and size, not quality. WebP quality controls lossy compression. 16-bit is used only where supported.")
                helpSection(japanese ? "ファイル名・保存先・プリセット" : "Names, destinations and presets", japanese
                    ? "文字追加・置換は複数登録でき、上から順に適用されます。同名ファイルには (1)、(2) が付き、既存ファイルを上書きしません。「形式ごとのフォルダを作成」は初期値ONです。同じ場所に保存する場合は入力元の隣に、フォルダを選択した場合は選択先の直下に、JPG、PNG、TIFF、WebPの形式別フォルダを作成します。OFFにすると保存先へ直接書き出します。フォルダ構成維持との併用時は、形式別フォルダの内側に元の階層を作ります。プリセットには設定値を保存しますが、選択した保存先URLそのものは保存しません。"
                    : "Add/replace operations can be stacked and run from top to bottom. Name collisions receive (1), (2), and so on; existing files are not overwritten. Create a folder for each format is enabled by default. Sprouts creates JPG, PNG, TIFF, or WebP folders beside each source or directly inside the chosen destination. Turn it off to export directly into the destination. When Preserve Folder Structure is also enabled, the source hierarchy is created inside each format folder. Presets store settings, but not the chosen destination URL itself.")
                helpSection(japanese ? "プライバシー" : "Privacy", japanese
                    ? "変換はMac内で完結します。入力ファイルをネットワークへ送信せず、ネットワーク権限も使用しません。"
                    : "Conversion is local to your Mac. Input files are not uploaded and no network permission is used.")
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(SproutsPalette.selectionAccent)
        .background(SproutsPalette.windowBackground(colorScheme))
    }

    private func helpSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.bold())
            Text(body).textSelection(.enabled).lineSpacing(3)
        }
    }
}
