import AppKit
import QuartzCore
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
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        if !coordinator.didSetInitialSize {
            coordinator.didSetInitialSize = true
            window.setContentSize(size)
            window.minSize = size
            window.maxSize = size
        } else if abs(window.contentLayoutRect.width - size.width) > 1
                    || abs(window.contentLayoutRect.height - size.height) > 1 {
            window.minSize = NSSize(width: 1, height: 1)
            window.maxSize = NSSize(width: 10_000, height: 10_000)
            let targetContent = NSRect(origin: .zero, size: size)
            var targetFrame = window.frameRect(forContentRect: targetContent)
            targetFrame.origin.x = window.frame.origin.x
            targetFrame.origin.y = window.frame.maxY - targetFrame.height
            let isClosing = targetFrame.width < window.frame.width
                || targetFrame.height < window.frame.height
            let changesHeight = abs(targetFrame.height - window.frame.height) > 1
            if isClosing || changesHeight {
                window.setFrame(targetFrame, display: true, animate: false)
                window.minSize = size
                window.maxSize = size
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.28
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(targetFrame, display: true)
                } completionHandler: {
                    window.minSize = size
                    window.maxSize = size
                }
            }
        } else {
            window.minSize = size
            window.maxSize = size
        }
    }
}
