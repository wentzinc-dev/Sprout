import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let size: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.title = "SPROUT"
        window.titleVisibility = .visible
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.minSize = size
        window.maxSize = size
        window.setContentSize(size)
    }
}
