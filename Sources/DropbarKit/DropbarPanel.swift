import Cocoa
import SwiftUI

/// A borderless floating panel that appears below the menu bar,
/// modeled after Ice's IceBarPanel. Uses `.mainMenu + 1` window level
/// to float above the menu bar, and `.nonactivatingPanel` so clicking
/// it doesn't steal focus from the frontmost app.
final class DropbarPanel: NSPanel {
    private var clickMonitor: Any?
    var onClose: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        animationBehavior = .utilityWindow
        backgroundColor = .clear
        hasShadow = true
        level = .mainMenu + 1
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
    }

    func show(
        anchoredBelow buttonWindow: NSWindow,
        content: some View
    ) {
        let hostingView = NSHostingView(
            rootView: content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        )
        let size = hostingView.fittingSize
        contentView = hostingView

        let buttonFrame = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]

        // Center horizontally on the button, clamped to screen
        let panelX = max(
            screen.frame.minX,
            min(buttonFrame.midX - size.width / 2, screen.frame.maxX - size.width)
        )
        // Position directly below the menu bar (button's bottom edge)
        let panelY = buttonFrame.minY - size.height - 4

        setFrame(
            NSRect(x: panelX, y: panelY, width: size.width, height: size.height),
            display: true
        )
        orderFrontRegardless()
        startMonitoringClicks()
    }

    func dismiss() {
        stopMonitoringClicks()
        close()
        onClose?()
    }

    private func startMonitoringClicks() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            if !self.frame.contains(mouse) {
                self.dismiss()
            }
        }
    }

    private func stopMonitoringClicks() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    deinit {
        stopMonitoringClicks()
    }
}
