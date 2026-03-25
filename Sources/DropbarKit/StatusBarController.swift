import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private let viewModel = DropbarViewModel()
    private var panel: DropbarPanel?
    private var lastCloseTime = Date.distantPast
    private var imageCache: [CGWindowID: NSImage] = [:]
    private var isCollapsed = false

    public override init() {
        // macOS 26: FIRST created = RIGHTMOST
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "DropbarToggle5"

        // SECOND created = to the LEFT. Visible so user can CMD+drag it.
        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem.autosaveName = "DropbarSep5"

        super.init()
        setupToggleItem()
        setupSeparatorItem()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.logPositions("INIT")
        }
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
        button.target = self
        button.action = #selector(separatorClicked(_:))
    }

    @objc private func separatorClicked(_ sender: NSStatusBarButton) {
        // Clicking the separator also toggles the dropdown
        toggleDropdown()
    }

    private func logPositions(_ context: String) {
        let sepX = separatorItem.button?.window?.frame.origin.x ?? -1
        let togX = toggleItem.button?.window?.frame.origin.x ?? -1
        let sepLen = separatorItem.length
        print("[Dropbar] [\(context)] sep: x=\(sepX) len=\(sepLen) | toggle: x=\(togX)")
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

        print("[Dropbar] --- TOGGLE ---")

        // If collapsed, expand separator to reveal items for scanning
        if isCollapsed {
            separatorItem.length = NSStatusItem.variableLength
            separatorItem.button?.title = "│"
            isCollapsed = false
            print("[Dropbar] expanded separator")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }

            let sepX = self.separatorItem.button?.window?.frame.origin.x ?? 0
            let items = self.scanner.scanAndCapture()

            // Items to the LEFT of the separator = will be hidden
            let leftItems = items.filter { $0.frame.maxX <= sepX }
            let rightItems = items.filter { $0.frame.origin.x >= sepX }

            print("[Dropbar] sepX=\(sepX) total=\(items.count) left=\(leftItems.count) right=\(rightItems.count)")

            // Cache images
            for item in items {
                if let image = item.image { self.imageCache[item.id] = image }
            }

            // Auto-set hiddenIDs from position (items left of separator)
            self.viewModel.hiddenIDs = Set(leftItems.map(\.id))
            self.viewModel.items = items.map { item in
                var copy = item
                if copy.image == nil, let cached = self.imageCache[item.id] {
                    copy.image = cached
                }
                return copy
            }

            self.showPanel()
        }
    }

    // MARK: - Collapse / Expand

    private func collapse() {
        print("[Dropbar] COLLAPSING separator")
        separatorItem.length = 10_000
        separatorItem.button?.title = ""
        isCollapsed = true
        logPositions("AFTER_COLLAPSE")
    }

    private func expand() {
        separatorItem.length = NSStatusItem.variableLength
        separatorItem.button?.title = "│"
        isCollapsed = false
    }

    // MARK: - Panel

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else { return }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.lastCloseTime = Date()
            self.panel = nil
            // Hide items left of separator when panel closes
            if !self.viewModel.hiddenIDs.isEmpty {
                self.collapse()
            }
        }

        let content = DropbarContentView(
            viewModel: viewModel,
            onItemClicked: { [weak self] item in self?.handleItemClick(item) }
        )
        panel.show(anchoredBelow: buttonWindow, content: content)
        self.panel = panel
    }

    // MARK: - Click-through

    private func handleItemClick(_ item: MenuBarItem) {
        panel?.dismiss()

        if viewModel.hiddenIDs.contains(item.id) {
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
        if isCollapsed {
            menu.addItem(NSMenuItem(title: "Show All", action: #selector(showAllItems), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "Quit Dropbar", action: #selector(quit), keyEquivalent: "q"))
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.toggleItem.menu = nil
        }
    }

    @objc private func showAllItems() {
        viewModel.hiddenIDs.removeAll()
        expand()
    }

    @objc private func quit() {
        expand()
        NSApp.terminate(nil)
    }
}
