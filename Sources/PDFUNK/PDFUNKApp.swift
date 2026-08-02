import SwiftUI

@main
struct SproutApp: App {
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.japanese.rawValue

    var body: some Scene {
        WindowGroup("SPROUT") {
            ContentView()
                .preferredColorScheme((AppTheme(rawValue: appTheme) ?? .system).colorScheme)
                .environment(\.locale, Locale(identifier: (AppLanguage(rawValue: appLanguage) ?? .japanese).localeIdentifier))
                .background(WindowConfigurator(size: NSSize(width: 540, height: 900)))
        }
        .defaultSize(width: 540, height: 900)
        .windowResizability(.contentSize)
    }
}
