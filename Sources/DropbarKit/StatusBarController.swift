import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private var panel: DropbarPanel?
    private var coverWindow: NSWindow?
    private var cachedHiddenItems: [MenuBarItem] = []
    private var isCollapsed = false
    private var lastCloseTime = Date.distantPast

    public override init() {
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "DropbarToggle"
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

        // First click: capture items left of toggle and cover them.
        // Subsequent clicks while covered: just show the panel.
        if !isCollapsed {
            captureAndCollapse()
        }
        showPanel()
    }

    // MARK: - Cover window (hides items visually)

    private var toggleX: CGFloat {
        toggleItem.button?.window?.frame.origin.x ?? 0
    }

    private func captureAndCollapse() {
        let tx = toggleX
        guard tx > 0 else { return }
        // Re-scan: uncover first so items are visible for capture
        removeCover()
        cachedHiddenItems = scanner.scanAndCapture().filter { $0.frame.maxX <= tx }
        guard !cachedHiddenItems.isEmpty else { return }
        placeCover()
        isCollapsed = true
        UserDefaults.standard.set(true, forKey: "dropbar.collapsed")
    }

    private func placeCover() {
        let tx = toggleX
        guard tx > 0,
              let leftmost = cachedHiddenItems.min(by: { $0.frame.origin.x < $1.frame.origin.x }),
              let screen = toggleItem.button?.window?.screen ?? NSScreen.main
        else { return }

        let startX = leftmost.frame.origin.x
        let coverWidth = tx - startX
        guard coverWidth > 0 else { return }

        let menuBarHeight = NSStatusBar.system.thickness
        let frame = NSRect(
            x: startX,
            y: screen.frame.maxY - menuBarHeight,
            width: coverWidth,
            height: menuBarHeight
        )

        let w = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        w.contentView = effect

        w.orderFront(nil)
        coverWindow = w
    }

    private func removeCover() {
        coverWindow?.close()
        coverWindow = nil
    }

    private func expand() {
        removeCover()
        isCollapsed = false
        UserDefaults.standard.set(false, forKey: "dropbar.collapsed")
    }

    // MARK: - Panel

    private func showPanel() {
        guard let buttonWindow = toggleItem.button?.window else { return }

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
            // Temporarily remove cover so the item is clickable
            removeCover()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.clickMenuItem(item)
                // Re-cover after giving the item's menu time to appear
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.placeCover()
                }
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
        menu.addItem(NSMenuItem(title: "Quit Dropbar", action: #selector(quit), keyEquivalent: "q"))
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.toggleItem.menu = nil
        }
    }

    @objc private func quit() {
        removeCover()
        NSApp.terminate(nil)
    }
}
