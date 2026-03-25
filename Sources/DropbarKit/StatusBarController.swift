import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private var panel: DropbarPanel?
    private var cachedHiddenItems: [MenuBarItem] = []
    private var isCollapsed = false
    private var lastCloseTime = Date.distantPast
    private let hiddenWidth: CGFloat = 10000

    public override init() {
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "DropbarToggle"
        // Invisible separator to the left of toggle. When expanded,
        // pushes everything to its left off-screen.
        separatorItem = NSStatusBar.system.statusItem(withLength: 0)
        separatorItem.autosaveName = "DropbarSep"
        super.init()
        setupToggleItem()

        // Restore collapsed state from previous session
        if UserDefaults.standard.bool(forKey: "dropbar.collapsed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.captureAndCollapse()
            }
        }
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

        // If items are visible, capture those left of the toggle and hide them
        if !isCollapsed {
            captureAndCollapse()
        }
        showPanel()
    }

    // MARK: - Hide / Show

    private var toggleX: CGFloat {
        toggleItem.button?.window?.frame.origin.x ?? 0
    }

    private func captureAndCollapse() {
        let tx = toggleX
        guard tx > 0 else { return }
        cachedHiddenItems = scanner.scanAndCapture().filter { $0.frame.maxX <= tx }
        collapse()
    }

    private func collapse() {
        separatorItem.length = hiddenWidth
        isCollapsed = true
        UserDefaults.standard.set(true, forKey: "dropbar.collapsed")
    }

    private func expand() {
        separatorItem.length = 0
        isCollapsed = false
        UserDefaults.standard.set(false, forKey: "dropbar.collapsed")
    }

    // MARK: - Panel

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else { return }

        // Merge currently visible items with cached hidden items
        let visibleItems = scanner.scanAndCapture()
        let allItems = (cachedHiddenItems + visibleItems)
            .sorted { $0.frame.origin.x < $1.frame.origin.x }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            self?.lastCloseTime = Date()
            self?.panel = nil
        }

        let content = DropbarContentView(items: allItems) { [weak self] item in
            self?.handleItemClick(item)
        }
        panel.show(anchoredBelow: buttonWindow, content: content)
        self.panel = panel
    }

    // MARK: - Click-through

    private func handleItemClick(_ item: MenuBarItem) {
        let wasHidden = cachedHiddenItems.contains(item)
        panel?.dismiss()

        if wasHidden {
            // Reveal hidden items, wait for render, then click
            expand()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.clickMenuItem(item)
            }
        } else {
            clickMenuItem(item)
        }
    }

    private func clickMenuItem(_ item: MenuBarItem) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

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
        // Reveal hidden items before quitting so they're accessible
        expand()
        NSApp.terminate(nil)
    }
}
