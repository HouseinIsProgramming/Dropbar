import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private var popover: NSPopover?
    private var cachedItems: [MenuBarItem] = []
    private var isCollapsed = false
    private let hiddenWidth: CGFloat = 10000

    public override init() {
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        setupToggleItem()
        setupSeparatorItem()
    }

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
        button.isEnabled = false
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
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        if !isCollapsed {
            cachedItems = scanner.scanAndCapture()
            collapse()
        }
        showPopover()
    }

    private func showPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
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

    private func handleItemClick(_ item: MenuBarItem) {
        popover?.performClose(nil)
        expand()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.clickThroughItem(item)
        }
    }

    private func clickThroughItem(_ item: MenuBarItem) {
        let currentItems = scanner.scan()
        let target = currentItems.first { $0.ownerName == item.ownerName }
        let clickPoint = CGPoint(
            x: target?.frame.midX ?? item.frame.midX,
            y: target?.frame.midY ?? item.frame.midY
        )

        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: clickPoint,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: clickPoint,
            mouseButton: .left
        )

        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }

    private func collapse() {
        separatorItem.length = hiddenWidth
        isCollapsed = true
    }

    private func expand() {
        separatorItem.length = NSStatusItem.squareLength
        isCollapsed = false
    }

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
