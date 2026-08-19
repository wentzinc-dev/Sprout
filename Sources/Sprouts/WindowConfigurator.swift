import AppKit
import QuartzCore
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let size: NSSize

    final class Coordinator {
        var requestedSize: NSSize?
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
        window.title = "Sprouts"
        window.titleVisibility = .visible
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        guard let previousSize = coordinator.requestedSize else {
            coordinator.requestedSize = size
            window.setContentSize(size)
            applyResizeLimits(to: window)
            return
        }

        let requestedSizeChanged = abs(previousSize.width - size.width) > 1
            || abs(previousSize.height - size.height) > 1
        guard requestedSizeChanged else {
            applyResizeLimits(to: window)
            return
        }

        coordinator.requestedSize = size
        window.contentMinSize = NSSize(width: 1, height: 1)
        window.contentMaxSize = NSSize(width: 10_000, height: 10_000)

        let currentContentSize = window.contentLayoutRect.size
        let widthDelta = size.width - previousSize.width
        let targetContentSize = NSSize(
            width: max(size.width, currentContentSize.width + widthDelta),
            height: size.height
        )
        let targetContent = NSRect(origin: .zero, size: targetContentSize)
        var targetFrame = window.frameRect(forContentRect: targetContent)
        targetFrame.origin.x = window.frame.origin.x
        targetFrame.origin.y = window.frame.maxY - targetFrame.height
        let isClosing = targetFrame.width < window.frame.width
            || targetFrame.height < window.frame.height
        let changesHeight = abs(targetFrame.height - window.frame.height) > 1
        if isClosing || changesHeight {
            window.setFrame(targetFrame, display: true, animate: false)
            applyResizeLimits(to: window)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                applyResizeLimits(to: window)
            }
        }
    }

    private func applyResizeLimits(to window: NSWindow) {
        window.contentMinSize = size
        window.contentMaxSize = NSSize(width: 10_000, height: size.height)
    }
}
