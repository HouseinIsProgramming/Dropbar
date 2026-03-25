import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private var panel: DropbarPanel?
    private var cachedItems: [MenuBarItem] = []
    private var isCollapsed = false
    private var isHandlingClick = false
    private var lastCloseTime = Date.distantPast
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
        // Debounce: if the panel was just closed by clicking outside,
        // the toggle action fires right after. Don't reopen.
        if Date().timeIntervalSince(lastCloseTime) < 0.3 {
            return
        }

        if let panel, panel.isVisible {
            closePanel()
            return
        }

        if !isCollapsed {
            // Get separator's window ID from AppKit, then look up its
            // CGWindowList frame (same coordinate space as scanned items).
            let sepWindowID = CGWindowID(separatorItem.button?.window?.windowNumber ?? 0)
            let sepX = scanner.frameForWindow(id: sepWindowID)?.origin.x ?? 0
            cachedItems = scanner.itemsLeftOf(x: sepX)
            print("[Dropbar] sep windowID=\(sepWindowID) sepX=\(sepX) found=\(cachedItems.count) items")
            collapse()
        }
        showPanel()
    }

    // MARK: - Panel

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else { return }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.lastCloseTime = Date()
            self.panel = nil
            if self.isCollapsed && !self.isHandlingClick {
                self.expand()
            }
        }

        let content = DropbarContentView(items: cachedItems) { [weak self] item in
            self?.handleItemClick(item)
        }
        panel.show(anchoredBelow: buttonWindow, content: content)
        self.panel = panel
    }

    private func closePanel() {
        panel?.dismiss()
    }

    // MARK: - Click-through

    private func handleItemClick(_ item: MenuBarItem) {
        isHandlingClick = true
        closePanel()
        expand()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.clickThroughItem(item)
            self.isHandlingClick = false
        }
    }

    private func clickThroughItem(_ item: MenuBarItem) {
        let current = scanner.scan()

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

    private func postTargetedClick(on item: MenuBarItem) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let clickPoint = CGPoint(x: item.frame.midX, y: item.frame.midY)

        guard let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left)
        else { return }

        let pid = Int64(item.ownerPID)
        let windowID = Int64(item.id)
        guard let privateWindowIDField = CGEventField(rawValue: 0x33) else { return }

        for event in [mouseDown, mouseUp] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(privateWindowIDField, value: windowID)
        }

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
