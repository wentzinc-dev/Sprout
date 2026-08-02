import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let size: NSSize

    final class Coordinator {
        var didSetInitialSize = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, coordinator: context.coordinator) }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.title = "Sprout"
        window.titleVisibility = .visible
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: size.width, height: 560)
        window.maxSize = NSSize(width: size.width, height: 10_000)
        if !coordinator.didSetInitialSize {
            coordinator.didSetInitialSize = true
            window.setContentSize(size)
        } else if abs(window.contentLayoutRect.width - size.width) > 1 {
            window.setContentSize(NSSize(width: size.width, height: window.contentLayoutRect.height))
        }
    }
}
