import SwiftUI

enum AppFontSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }
    var dynamicTypeSize: DynamicTypeSize {
        switch self { case .small: .xSmall; case .medium: .large; case .large: .accessibility1 }
    }
    var scale: CGFloat { switch self { case .small: 0.88; case .medium: 1; case .large: 1.18 } }
    var compactWidth: CGFloat { 420 * scale }
    var compactHeight: CGFloat { 500 * scale }
    var sidebarWidth: CGFloat { 270 * scale }
    var expandedHeight: CGFloat { 820 * scale }
    var sidebarHeight: CGFloat { 580 * scale }
    var controlSize: ControlSize { switch self { case .small: .small; case .medium: .regular; case .large: .large } }
}

@main
struct SproutApp: App {
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue
    @AppStorage("appFontSize") private var appFontSize = AppFontSize.medium.rawValue
    @AppStorage("showsInspectorSidebar") private var showsInspectorSidebar = false
    @AppStorage("showsAdvancedSettings") private var showsAdvancedSettings = false

    var body: some Scene {
        WindowGroup("Sprout") {
            let fontSize = AppFontSize(rawValue: appFontSize) ?? .medium
            let contentWidth = fontSize.compactWidth + (showsInspectorSidebar ? fontSize.sidebarWidth : 0)
            let contentHeight = max(
                fontSize.compactHeight,
                showsAdvancedSettings ? fontSize.expandedHeight : 0
            )
            ContentView()
                .preferredColorScheme((AppTheme(rawValue: appTheme) ?? .system).colorScheme)
                .environment(\.locale, Locale(identifier: (AppLanguage(rawValue: appLanguage) ?? .japanese).localeIdentifier))
                .environment(\.dynamicTypeSize, fontSize.dynamicTypeSize)
                .environment(\.controlSize, fontSize.controlSize)
                .background(WindowConfigurator(size: NSSize(width: contentWidth, height: contentHeight)))
        }
        .defaultSize(width: 420, height: 500)

        Settings {
            SproutSettingsView()
        }

        Window("Sprout ヘルプ", id: "sprout-help") {
            HelpView()
        }
        .defaultSize(width: 700, height: 720)
        .commands { HelpCommands() }
    }
}

private struct SproutSettingsView: View {
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue
    @AppStorage("appFontSize") private var appFontSize = AppFontSize.medium.rawValue

    var body: some View {
        let fontSize = AppFontSize(rawValue: appFontSize) ?? .medium
        PreferencesView(
            appTheme: $appTheme,
            appLanguage: $appLanguage,
            appFontSize: $appFontSize
        )
        .environment(\.dynamicTypeSize, fontSize.dynamicTypeSize)
        .environment(\.controlSize, fontSize.controlSize)
    }
}

private struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Sproutの使い方") { openWindow(id: "sprout-help") }
                .keyboardShortcut("?", modifiers: [.command])
        }
    }
}
