import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private var panel: DropbarPanel?
    private var cachedHiddenItems: [MenuBarItem] = []
    private var allSortedItems: [MenuBarItem] = []
    private var hiddenCount = 0
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

        // Restore from previous session
        let saved = UserDefaults.standard.integer(forKey: "dropbar.hiddenCount")
        if saved > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                self.hiddenCount = saved
                self.captureAndCollapse()
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

        // If items are visible, scan and hide
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
        // Expand first to ensure items are visible for capture
        if isCollapsed {
            separatorItem.length = 0
        }

        // Small delay for items to settle after expand
        let tx = toggleX
        guard tx > 0 else { return }

        let items = scanner.scanAndCapture().sorted { $0.frame.origin.x < $1.frame.origin.x }
        let leftOfToggle = items.filter { $0.frame.maxX <= tx }

        // If no explicit hiddenCount yet, hide everything left of toggle
        if hiddenCount == 0 || hiddenCount > leftOfToggle.count {
            hiddenCount = leftOfToggle.count
        }

        allSortedItems = items
        cachedHiddenItems = Array(items.prefix(hiddenCount))
        collapse()
    }

    private func collapse() {
        guard hiddenCount > 0 else { return }
        separatorItem.length = 10_000
        isCollapsed = true
        UserDefaults.standard.set(hiddenCount, forKey: "dropbar.hiddenCount")
    }

    private func expand() {
        separatorItem.length = 0
        isCollapsed = false
    }

    // MARK: - Panel

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else { return }

        // Re-merge: cached hidden + fresh visible scan
        let visibleItems = scanner.scanAndCapture()
        let hiddenIDs = Set(cachedHiddenItems.map(\.id))
        allSortedItems = (cachedHiddenItems + visibleItems.filter { !hiddenIDs.contains($0.id) })
            .sorted { $0.frame.origin.x < $1.frame.origin.x }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            self?.lastCloseTime = Date()
            self?.panel = nil
        }

        let content = DropbarContentView(
            items: allSortedItems,
            hiddenCount: hiddenCount,
            onItemClicked: { [weak self] item in self?.handleItemClick(item) },
            onItemOptionClicked: { [weak self] index in self?.handleOptionClick(at: index) }
        )
        panel.show(anchoredBelow: buttonWindow, content: content)
        self.panel = panel
    }

    // MARK: - Option+click (toggle hidden/visible)

    private func handleOptionClick(at index: Int) {
        if index < hiddenCount {
            // Unhide: move divider to this index (unhide this item and all to its right)
            hiddenCount = index
        } else {
            // Hide: move divider past this item (hide this item and all to its left)
            hiddenCount = index + 1
        }

        UserDefaults.standard.set(hiddenCount, forKey: "dropbar.hiddenCount")

        // Refresh: expand, re-scan, re-collapse, re-show panel
        panel?.dismiss()
        expand()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.captureAndCollapse()
            self.showPanel()
        }
    }

    // MARK: - Click-through

    private func handleItemClick(_ item: MenuBarItem) {
        let wasHidden = cachedHiddenItems.contains(item)
        panel?.dismiss()

        if wasHidden {
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
        hiddenCount = 0
        expand()
        UserDefaults.standard.set(0, forKey: "dropbar.hiddenCount")
    }

    @objc private func quit() {
        separatorItem.length = 0
        NSApp.terminate(nil)
    }
}
