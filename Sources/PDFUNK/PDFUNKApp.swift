import SwiftUI

@main
struct PDFUNKApp: App {
    var body: some Scene {
        WindowGroup("PDFUNK") {
            ContentView()
                .background(WindowConfigurator(size: NSSize(width: 320, height: 610)))
        }
        .defaultSize(width: 320, height: 610)
        .windowResizability(.contentSize)
    }
}
