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

        // Match by window ID (stable across expand/collapse)
        let target: MenuBarItem?
        if let byID = current.first(where: { $0.id == item.id }) {
            target = byID
        } else {
            // Fallback: same owner, closest X position
            let candidates = current.filter { $0.ownerName == item.ownerName }
            target = candidates.min(by: {
                abs($0.frame.midX - item.frame.midX) < abs($1.frame.midX - item.frame.midX)
            })
        }

        guard let target else { return }
        postClick(at: CGPoint(x: target.frame.midX, y: target.frame.midY))
    }

    private func postClick(at point: CGPoint) {
        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        mouseDown?.post(tap: .cghidEventTap)

        // Stagger mouseUp so macOS registers it as a real click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
            mouseUp?.post(tap: .cghidEventTap)
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
