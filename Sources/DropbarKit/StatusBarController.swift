import Cocoa
import SwiftUI

public class StatusBarController: NSObject, NSPopoverDelegate {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private var popover: NSPopover?
    private var cachedItems: [MenuBarItem] = []
    private(set) var isCollapsed = false
    private var isHandlingClick = false
    private let hiddenWidth: CGFloat = 10000

    public override init() {
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        setupToggleItem()
        setupSeparatorItem()
    }

    // MARK: - Setup

    private func setupToggleItem() {
        guard let button = toggleItem.button else { return }
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Dropbar")
        button.target = self
        button.action = #selector(toggleClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupSeparatorItem() {
        guard let button = separatorItem.button else { return }
        button.title = "│"
    }

    var separatorX: CGFloat {
        separatorItem.button?.window?.frame.origin.x ?? 0
    }

    // MARK: - Toggle

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleDropdown()
        }
    }

    private func toggleDropdown() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        if !isCollapsed {
            cachedItems = scanner.itemsLeftOf(x: separatorX)
            collapse()
        }
        showPopover()
    }

    // MARK: - Popover

    private func showPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(items: cachedItems) { [weak self] item in
                self?.handleItemClick(item)
            }
        )

        if let button = toggleItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        self.popover = popover
    }

    // MARK: - Click-through

    private func handleItemClick(_ item: MenuBarItem) {
        isHandlingClick = true
        popover?.performClose(nil)
        expand()

        // Wait for the menu bar to re-render revealed items, then click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.clickThroughItem(item)
            self.isHandlingClick = false
        }
    }

    private func clickThroughItem(_ item: MenuBarItem) {
        let current = scanner.scan()

        // Match by window ID first (stable across expand/collapse since the
        // window persists, it just moves). Fall back to ownerName + closest X.
        let target: MenuBarItem?
        if let byID = current.first(where: { $0.id == item.id }) {
            target = byID
        } else {
            let candidates = current.filter { $0.ownerName == item.ownerName }
            target = candidates.min(by: {
                abs($0.frame.midX - item.frame.midX) < abs($1.frame.midX - item.frame.midX)
            })
        }

        guard let target else { return }
        postTargetedClick(on: target)
    }

    /// Posts a CGEvent click targeted at a specific menu bar item's window.
    ///
    /// Following Ice's approach: set the target PID, window ID, and private
    /// window ID field (0x33) on the event so macOS routes it directly to the
    /// owning process — no matter what's actually under the cursor.
    private func postTargetedClick(on item: MenuBarItem) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let clickPoint = CGPoint(x: item.frame.midX, y: item.frame.midY)

        guard let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left)
        else { return }

        let pid = Int64(item.ownerPID)
        let windowID = Int64(item.id)
        // Private/undocumented CGEventField that Ice uses to target a specific window
        guard let privateWindowIDField = CGEventField(rawValue: 0x33) else { return }

        for event in [mouseDown, mouseUp] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(privateWindowIDField, value: windowID)
        }

        // Save cursor position, hide it, click, then restore.
        // CGEvent(source: nil)?.location gives current pos in Quartz coords.
        let savedCursor = CGEvent(source: nil)?.location ?? .zero
        CGDisplayHideCursor(CGMainDisplayID())

        mouseDown.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            mouseUp.post(tap: .cgSessionEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                CGWarpMouseCursorPosition(savedCursor)
                CGDisplayShowCursor(CGMainDisplayID())
            }
        }
    }

    // MARK: - Collapse / Expand

    private func collapse() {
        separatorItem.length = hiddenWidth
        isCollapsed = true
    }

    private func expand() {
        separatorItem.length = NSStatusItem.squareLength
        isCollapsed = false
    }

    // MARK: - NSPopoverDelegate

    public func popoverDidClose(_ notification: Notification) {
        if isCollapsed && !isHandlingClick {
            expand()
        }
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
