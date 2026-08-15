import SwiftUI

struct AppLayout {
    let dynamicTypeSize = DynamicTypeSize.large
    let scale: CGFloat = 1
    let compactWidth: CGFloat = 420
    let compactHeight: CGFloat = 500
    let sidebarWidth: CGFloat = 270
    let expandedHeight: CGFloat = 820
    let sidebarHeight: CGFloat = 580
    let controlSize = ControlSize.regular
}

@main
struct SproutApp: App {
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue
    @AppStorage("showsInspectorSidebar") private var showsInspectorSidebar = false
    @AppStorage("showsAdvancedSettings") private var showsAdvancedSettings = false

    var body: some Scene {
        WindowGroup("Sprout") {
            let layout = AppLayout()
            let contentWidth = layout.compactWidth + (showsInspectorSidebar ? layout.sidebarWidth : 0)
            let contentHeight = max(
                layout.compactHeight,
                showsAdvancedSettings ? layout.expandedHeight : 0
            )
            ContentView()
                .preferredColorScheme((AppTheme(rawValue: appTheme) ?? .system).colorScheme)
                .environment(\.locale, Locale(identifier: (AppLanguage(rawValue: appLanguage) ?? .japanese).localeIdentifier))
                .environment(\.dynamicTypeSize, layout.dynamicTypeSize)
                .environment(\.controlSize, layout.controlSize)
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

    var body: some View {
        PreferencesView(
            appTheme: $appTheme,
            appLanguage: $appLanguage
        )
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
