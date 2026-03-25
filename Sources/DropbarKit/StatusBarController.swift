import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private var panel: DropbarPanel?
    private var cachedHiddenItems: [MenuBarItem] = []
    private var isCollapsed = false
    private var lastCloseTime = Date.distantPast

    public override init() {
        let toggleName = "DropbarToggle"
        let separatorName = "DropbarSep"

        // Set preferred positions BEFORE creating items. This is the same
        // technique Ice uses (StatusItemDefaults). Position 0 = rightmost
        // among our items, position 1 = to its left.
        // Without this, macOS can place the separator to the RIGHT of the
        // toggle, causing the toggle to get pushed off-screen on expansion.
        let posKey = "NSStatusItem Preferred Position"
        if UserDefaults.standard.object(forKey: "\(posKey) \(toggleName)") == nil {
            UserDefaults.standard.set(0, forKey: "\(posKey) \(toggleName)")
        }
        if UserDefaults.standard.object(forKey: "\(posKey) \(separatorName)") == nil {
            UserDefaults.standard.set(1, forKey: "\(posKey) \(separatorName)")
        }

        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = toggleName

        // Separator: invisible (length 0) when items are shown.
        // Expands to 10,000 to push items to its left off-screen.
        separatorItem = NSStatusBar.system.statusItem(withLength: 0)
        separatorItem.autosaveName = separatorName

        super.init()
        setupToggleItem()

        // Restore collapsed state from previous session
        if UserDefaults.standard.bool(forKey: "dropbar.collapsed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.captureAndCollapse()
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

        // If items are currently visible, capture and hide them
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
        let tx = toggleX
        guard tx > 0 else { return }
        cachedHiddenItems = scanner.scanAndCapture().filter { $0.frame.maxX <= tx }
        collapse()
    }

    private func collapse() {
        separatorItem.length = 10_000
        isCollapsed = true
        UserDefaults.standard.set(true, forKey: "dropbar.collapsed")
    }

    private func expand() {
        separatorItem.length = 0
        isCollapsed = false
        UserDefaults.standard.set(false, forKey: "dropbar.collapsed")
    }

    // MARK: - Panel

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else { return }

        // Merge visible + cached hidden, deduplicated by window ID
        let visibleItems = scanner.scanAndCapture()
        let hiddenIDs = Set(cachedHiddenItems.map(\.id))
        let allItems = (cachedHiddenItems + visibleItems.filter { !hiddenIDs.contains($0.id) })
            .sorted { $0.frame.origin.x < $1.frame.origin.x }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            self?.lastCloseTime = Date()
            self?.panel = nil
        }

        let content = DropbarContentView(items: allItems) { [weak self] item in
            self?.handleItemClick(item)
        }
        panel.show(anchoredBelow: buttonWindow, content: content)
        self.panel = panel
    }

    // MARK: - Click-through

    private func handleItemClick(_ item: MenuBarItem) {
        let wasHidden = cachedHiddenItems.contains(item)
        panel?.dismiss()

        if wasHidden {
            // Reveal items so the click target is on-screen
            expand()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.clickMenuItem(item)
                // Items stay visible; next toggle click re-captures and re-hides
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

        // Get FRESH frame right before clicking
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
        menu.addItem(NSMenuItem(title: "Quit Dropbar", action: #selector(quit), keyEquivalent: "q"))
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.toggleItem.menu = nil
        }
    }

    @objc private func quit() {
        // Restore normal positions before quitting so macOS saves
        // correct positions and items aren't stuck off-screen
        separatorItem.length = 0
        NSApp.terminate(nil)
    }
}
