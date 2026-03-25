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
        // macOS 26: FIRST created = RIGHTMOST.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "DropbarToggle4"

        // SECOND created = to the LEFT of first.
        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem.autosaveName = "DropbarSep4"
        // Give it a button so it has a window
        separatorItem.button?.title = ""

        super.init()
        setupToggleItem()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.logPositions("INIT")
        }
    }

    private func logPositions(_ context: String) {
        let sepX = separatorItem.button?.window?.frame.origin.x ?? -1
        let sepW = separatorItem.button?.window?.frame.width ?? -1
        let togX = toggleItem.button?.window?.frame.origin.x ?? -1
        let togW = toggleItem.button?.window?.frame.width ?? -1
        let sepLen = separatorItem.length
        print("[Dropbar] [\(context)] sep: x=\(sepX) w=\(sepW) len=\(sepLen) | toggle: x=\(togX) w=\(togW)")
        if sepX >= 0 && togX >= 0 {
            print("[Dropbar] [\(context)] sep is \(sepX < togX ? "LEFT ✓" : "RIGHT ✗") of toggle")
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

        print("[Dropbar] --- TOGGLE CLICKED ---")
        print("[Dropbar] isCollapsed=\(isCollapsed) hiddenIDs=\(viewModel.hiddenIDs.count)")

        // If collapsed, expand separator first
        if isCollapsed {
            separatorItem.length = NSStatusItem.variableLength
            isCollapsed = false
            print("[Dropbar] expanded separator")
        }

        // Also reveal any alpha-hidden items
        for id in viewModel.hiddenIDs {
            _ = WindowBridging.showWindow(id)
        }

        logPositions("BEFORE_SCAN")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }

            let items = self.scanner.scanAndCapture()
            print("[Dropbar] scanned \(items.count) items")
            for item in items {
                print("[Dropbar]   \(item.ownerName) id=\(item.id) x=\(item.frame.origin.x) w=\(item.frame.width) hasImage=\(item.image != nil)")
            }

            // Cache images
            for item in items {
                if let image = item.image {
                    self.imageCache[item.id] = image
                }
            }

            // Prune stale IDs
            let currentIDs = Set(items.map(\.id))
            self.viewModel.hiddenIDs = self.viewModel.hiddenIDs.intersection(currentIDs)

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

    // MARK: - Hiding (both separator + alpha)

    private func hideMarkedItems() {
        print("[Dropbar] --- HIDING \(viewModel.hiddenIDs.count) ITEMS ---")

        // Method 1: separator trick
        if !viewModel.hiddenIDs.isEmpty {
            separatorItem.length = 10_000
            isCollapsed = true
            print("[Dropbar] separator set to 10000")
        }

        // Method 2: alpha (per-item, as backup)
        for item in viewModel.items {
            if viewModel.hiddenIDs.contains(item.id) {
                let ok = WindowBridging.hideWindow(item.id)
                print("[Dropbar] alpha hide \(item.ownerName) id=\(item.id) ok=\(ok)")
            }
        }

        logPositions("AFTER_HIDE")
    }

    private func showAllWindows() {
        separatorItem.length = NSStatusItem.variableLength
        isCollapsed = false
        for item in viewModel.items {
            _ = WindowBridging.showWindow(item.id)
        }
    }

    // MARK: - Panel

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else {
            print("[Dropbar] no buttonWindow!")
            return
        }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            guard let self else { return }
            print("[Dropbar] --- PANEL CLOSED ---")
            self.lastCloseTime = Date()
            self.panel = nil
            self.hideMarkedItems()
        }

        let content = DropbarContentView(
            viewModel: viewModel,
            onItemClicked: { [weak self] item in self?.handleItemClick(item) }
        )
        panel.show(anchoredBelow: buttonWindow, content: content)
        self.panel = panel
        print("[Dropbar] panel shown")
    }

    // MARK: - Click-through

    private func handleItemClick(_ item: MenuBarItem) {
        print("[Dropbar] item clicked: \(item.ownerName) id=\(item.id) hidden=\(viewModel.hiddenIDs.contains(item.id))")
        panel?.dismiss()

        if viewModel.hiddenIDs.contains(item.id) {
            _ = WindowBridging.showWindow(item.id)
            separatorItem.length = NSStatusItem.variableLength
            isCollapsed = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.clickMenuItem(item)
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
        if !viewModel.hiddenIDs.isEmpty {
            menu.addItem(NSMenuItem(title: "Show All Items", action: #selector(showAllItems), keyEquivalent: ""))
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
        showAllWindows()
    }

    @objc private func quit() {
        showAllWindows()
        NSApp.terminate(nil)
    }
}
