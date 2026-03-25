import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private let viewModel = DropbarViewModel()
    private var panel: DropbarPanel?
    private var isCollapsed = false
    private var lastCloseTime = Date.distantPast

    public override init() {
        let toggleName = "DropbarToggle"
        let separatorName = "DropbarSep"

        let posKey = "NSStatusItem Preferred Position"
        if UserDefaults.standard.object(forKey: "\(posKey) \(toggleName)") == nil {
            UserDefaults.standard.set(0, forKey: "\(posKey) \(toggleName)")
        }
        if UserDefaults.standard.object(forKey: "\(posKey) \(separatorName)") == nil {
            UserDefaults.standard.set(1, forKey: "\(posKey) \(separatorName)")
        }

        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = toggleName

        separatorItem = NSStatusBar.system.statusItem(withLength: 0)
        separatorItem.autosaveName = separatorName

        super.init()
        setupToggleItem()

        // Auto-collapse on launch if items were hidden in previous session
        if UserDefaults.standard.bool(forKey: "dropbar.collapsed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.scanAndCollapse()
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

        // Scan items while visible (expand if needed)
        if isCollapsed {
            separatorItem.length = 0
            isCollapsed = false
        }

        // Brief delay for items to settle after expand
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scanAndShowPanel()
        }
    }

    // MARK: - Scan & Show

    private var toggleX: CGFloat {
        toggleItem.button?.window?.frame.origin.x ?? 0
    }

    private func scanAndShowPanel() {
        let tx = toggleX
        let items = scanner.scanAndCapture()

        viewModel.items = items

        // Items left of the chevron are initially hidden
        if viewModel.hiddenIDs.isEmpty {
            let leftOfToggle = items.filter { $0.frame.maxX <= tx }
            viewModel.hiddenIDs = Set(leftOfToggle.map(\.id))
        } else {
            // Keep existing hidden set but remove IDs that no longer exist
            let currentIDs = Set(items.map(\.id))
            viewModel.hiddenIDs = viewModel.hiddenIDs.intersection(currentIDs)
        }

        // Collapse to hide items
        if !viewModel.hiddenIDs.isEmpty {
            separatorItem.length = 10_000
            isCollapsed = true
            UserDefaults.standard.set(true, forKey: "dropbar.collapsed")
        }

        showPanel()
    }

    private func scanAndCollapse() {
        let tx = toggleX
        guard tx > 0 else { return }
        let items = scanner.scanAndCapture()
        viewModel.items = items
        viewModel.hiddenIDs = Set(items.filter { $0.frame.maxX <= tx }.map(\.id))

        if !viewModel.hiddenIDs.isEmpty {
            separatorItem.length = 10_000
            isCollapsed = true
        }
    }

    // MARK: - Panel

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else { return }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            self?.lastCloseTime = Date()
            self?.panel = nil
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
        let wasHidden = viewModel.hiddenIDs.contains(item.id)
        panel?.dismiss()

        if wasHidden {
            // Reveal items temporarily to click the target
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
        if isCollapsed {
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
        UserDefaults.standard.set(false, forKey: "dropbar.collapsed")
    }

    @objc private func quit() {
        separatorItem.length = 0
        NSApp.terminate(nil)
    }
}
