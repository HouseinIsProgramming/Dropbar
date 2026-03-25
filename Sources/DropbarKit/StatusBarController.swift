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
        // preferredPosition is an X-coordinate hint. Lower = further LEFT.
        // Separator must be LEFT of toggle. Ice uses 0/1 for its leftmost items.
        // We set separator=0 (far left) and let toggle get placed to its right.
        let sepName = "DropbarSep"
        let toggleName = "DropbarToggle"

        let posKey = "NSStatusItem Preferred Position"
        UserDefaults.standard.set(CGFloat(0), forKey: "\(posKey) \(sepName)")
        // Don't set a position for toggle — let macOS place it naturally
        // (to the right of the separator)

        // Create separator FIRST at position 0 (leftmost)
        separatorItem = NSStatusBar.system.statusItem(withLength: 0)
        separatorItem.autosaveName = sepName

        // Create toggle SECOND (placed to the right of separator)
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = toggleName

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

        // Always scan fresh (expand if needed, scan, re-collapse)
        refreshAndShowPanel()
    }

    // MARK: - Scan & Panel

    private var toggleX: CGFloat {
        toggleItem.button?.window?.frame.origin.x ?? 0
    }

    private func refreshAndShowPanel() {
        // If collapsed, briefly expand so scanner can see all items
        if isCollapsed {
            separatorItem.length = 0
        }

        // Give the menu bar a moment to settle after expand
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let items = self.scanner.scanAndCapture()
            self.viewModel.items = items

            // Prune stale IDs (apps that quit since last scan)
            let currentIDs = Set(items.map(\.id))
            self.viewModel.hiddenIDs = self.viewModel.hiddenIDs.intersection(currentIDs)

            // Re-collapse if there are hidden items
            if !self.viewModel.hiddenIDs.isEmpty {
                self.separatorItem.length = 10_000
                self.isCollapsed = true
            }

            self.showPanel()
        }
    }

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else { return }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.lastCloseTime = Date()
            self.panel = nil
            // When panel closes, ensure hidden items stay hidden
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
            // Item is hidden — expand, wait for render, click
            separatorItem.length = 0
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
        separatorItem.length = 0
        isCollapsed = false
    }

    @objc private func quit() {
        // Restore items before quitting
        separatorItem.length = 0
        NSApp.terminate(nil)
    }
}
