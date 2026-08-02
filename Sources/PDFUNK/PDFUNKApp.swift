import SwiftUI

enum AppFontSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }
    var dynamicTypeSize: DynamicTypeSize {
        switch self { case .small: .small; case .medium: .large; case .large: .xxLarge }
    }
    var windowWidth: CGFloat { self == .large ? 850 : 770 }
}

@main
struct SproutApp: App {
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue
    @AppStorage("appFontSize") private var appFontSize = AppFontSize.medium.rawValue

    var body: some Scene {
        WindowGroup("Sprout") {
            let fontSize = AppFontSize(rawValue: appFontSize) ?? .medium
            ContentView()
                .preferredColorScheme((AppTheme(rawValue: appTheme) ?? .system).colorScheme)
                .environment(\.locale, Locale(identifier: (AppLanguage(rawValue: appLanguage) ?? .japanese).localeIdentifier))
                .environment(\.dynamicTypeSize, fontSize.dynamicTypeSize)
                .background(WindowConfigurator(size: NSSize(width: fontSize.windowWidth, height: 600)))
        }
        .defaultSize(width: 770, height: 600)
        .windowResizability(.contentMinSize)

        Window("Sprout ヘルプ", id: "sprout-help") {
            HelpView()
        }
        .defaultSize(width: 700, height: 720)
        .commands { HelpCommands() }
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
