import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private let viewModel = DropbarViewModel()
    private var panel: DropbarPanel?
    private var lastCloseTime = Date.distantPast
    private var isCollapsed = false

    public override init() {
        // Create separator FIRST with variableLength so it gets a window.
        // macOS places newer status items to the LEFT of existing ones,
        // so separator (first) goes left, toggle (second) goes right.
        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem.autosaveName = "DropbarSep2"
        separatorItem.button?.title = ""

        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "DropbarToggle2"

        super.init()
        setupToggleItem()

        // Verify positioning after a beat (windows need to materialize)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.verifyPositions()
        }
    }

    private func setupToggleItem() {
        guard let button = toggleItem.button else { return }
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Dropbar")
        button.target = self
        button.action = #selector(toggleClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func verifyPositions() {
        let sepWN = separatorItem.button?.window?.windowNumber
        let toggleWN = toggleItem.button?.window?.windowNumber
        print("[Dropbar] raw window numbers: sep=\(sepWN as Any) toggle=\(toggleWN as Any)")
        print("[Dropbar] sep button=\(separatorItem.button as Any) window=\(separatorItem.button?.window as Any)")

        guard let sepID = WindowBridging.getWindowID(for: separatorItem),
              let toggleID = WindowBridging.getWindowID(for: toggleItem)
        else {
            print("[Dropbar] couldn't convert window IDs")
            // Fall back to AppKit frames
            let sepX = separatorItem.button?.window?.frame.origin.x ?? -1
            let toggleX = toggleItem.button?.window?.frame.origin.x ?? -1
            print("[Dropbar] AppKit frames: sep=\(sepX) toggle=\(toggleX)")
            return
        }

        guard let sepFrame = WindowBridging.getWindowFrame(for: sepID),
              let toggleFrame = WindowBridging.getWindowFrame(for: toggleID)
        else {
            print("[Dropbar] CGSGetScreenRectForWindow failed for sep=\(sepID) toggle=\(toggleID)")
            return
        }
        print("[Dropbar] separator: x=\(sepFrame.origin.x) w=\(sepFrame.width)")
        print("[Dropbar] toggle: x=\(toggleFrame.origin.x) w=\(toggleFrame.width)")
        if sepFrame.origin.x < toggleFrame.origin.x {
            print("[Dropbar] ✓ separator is LEFT of toggle — hiding will work")
        } else {
            print("[Dropbar] ✗ separator is RIGHT of toggle — swapping needed")
            // Remove both and recreate in opposite order
            NSStatusBar.system.removeStatusItem(separatorItem)
            NSStatusBar.system.removeStatusItem(toggleItem)
            // Note: this would require re-init, so for now just warn
        }
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

        // Expand separator to show all items for scanning
        if isCollapsed {
            separatorItem.length = NSStatusItem.variableLength
            isCollapsed = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.viewModel.items = self.scanner.scanAndCapture()

            // Prune stale IDs
            let currentIDs = Set(self.viewModel.items.map(\.id))
            self.viewModel.hiddenIDs = self.viewModel.hiddenIDs.intersection(currentIDs)

            // Re-collapse if there are hidden items
            if !self.viewModel.hiddenIDs.isEmpty {
                self.separatorItem.length = 10_000
                self.isCollapsed = true
            }

            self.showPanel()
        }
    }

    // MARK: - Panel

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else { return }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.lastCloseTime = Date()
            self.panel = nil
            // Re-collapse when panel closes
            if !self.viewModel.hiddenIDs.isEmpty && !self.isCollapsed {
                self.separatorItem.length = 10_000
                self.isCollapsed = true
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
            separatorItem.length = NSStatusItem.variableLength
            isCollapsed = false
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

        // Use private API for accurate frame (works even for off-screen items)
        let frame: CGRect
        if let wid = viewModel.items.first(where: { $0.id == item.id })?.id,
           let f = WindowBridging.getWindowFrame(for: wid) {
            frame = f
        } else {
            frame = scanner.currentFrame(for: item.id) ?? item.frame
        }
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
        separatorItem.length = NSStatusItem.variableLength
        isCollapsed = false
    }

    @objc private func quit() {
        separatorItem.length = NSStatusItem.variableLength
        NSApp.terminate(nil)
    }
}
