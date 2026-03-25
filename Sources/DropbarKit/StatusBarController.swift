import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private var panel: DropbarPanel?
    private var lastCloseTime = Date.distantPast

    public override init() {
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "DropbarToggle"
        super.init()
        setupToggleItem()
    }

    private func setupToggleItem() {
        guard let button = toggleItem.button else { return }
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Dropbar")
        button.target = self
        button.action = #selector(toggleClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleDropdown()
        }
    }

    private func toggleDropdown() {
        if Date().timeIntervalSince(lastCloseTime) < 0.3 { return }

        if let panel, panel.isVisible {
            panel.dismiss()
            return
        }

        showPanel(with: scanner.scanAndCapture())
    }

    // MARK: - Panel

    private func showPanel(with items: [MenuBarItem]) {
        guard let buttonWindow = toggleItem.button?.window else { return }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            self?.lastCloseTime = Date()
            self?.panel = nil

        }

        let content = DropbarContentView(items: items) { [weak self] item in
            self?.handleItemClick(item)
        }
        panel.show(anchoredBelow: buttonWindow, content: content)
        self.panel = panel

    }

    // MARK: - Click-through (Ice's approach)

    private func handleItemClick(_ item: MenuBarItem) {
        panel?.dismiss()
        clickMenuItem(item)
    }

    /// Posts targeted CGEvents to click a menu bar item, matching Ice's
    /// `menuBarItemEvent` factory. Key fields route the event to the
    /// correct process and window regardless of what's under the cursor.
    private func clickMenuItem(_ item: MenuBarItem) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // Permit all events during suppression states (same as Ice)
        let permitAll: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        if let suppression = CGEventSource(stateID: .combinedSessionState) {
            suppression.setLocalEventsFilterDuringSuppressionState(
                permitAll, state: .eventSuppressionStateRemoteMouseDrag
            )
            suppression.setLocalEventsFilterDuringSuppressionState(
                permitAll, state: .eventSuppressionStateSuppressionInterval
            )
            suppression.localEventsSuppressionInterval = 0
        }

        // Get FRESH frame right before clicking, not the cached one
        let frame = scanner.currentFrame(for: item.id) ?? item.frame
        let clickPoint = CGPoint(x: frame.midX, y: frame.midY)

        guard let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left)
        else { return }

        let pid = Int64(item.ownerPID)
        let windowID = Int64(item.id)

        for event in [mouseDown, mouseUp] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            if let wIDField = CGEventField(rawValue: 0x33) {
                event.setIntegerValueField(wIDField, value: windowID)
            }
        }

        // Save cursor, hide, click, restore (Ice's pattern — no delays)
        let savedCursor = CGEvent(source: nil)?.location ?? .zero
        CGDisplayHideCursor(CGMainDisplayID())

        mouseDown.post(tap: .cgSessionEventTap)
        mouseUp.post(tap: .cgSessionEventTap)

        CGWarpMouseCursorPosition(savedCursor)
        CGDisplayShowCursor(CGMainDisplayID())
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Dropbar", action: #selector(quit), keyEquivalent: "q"))
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.toggleItem.menu = nil
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
