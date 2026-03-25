import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let separatorItem: NSStatusItem
    private let chevronItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private var panel: DropbarPanel?
    private var lastCloseTime = Date.distantPast
    private var separatorX: CGFloat = 0

    static let expandedLength: CGFloat = 10_000

    public override init() {
        chevronItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupSeparator()
        setupChevron()

        // Briefly show collapsed to capture separator position, then expand
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.captureSeparatorPosition()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.expand()
            }
        }
    }

    // MARK: - Setup

    private func setupSeparator() {
        separatorItem.autosaveName = "Dropbar-Separator"
        guard let button = separatorItem.button else { return }
        button.title = "│"
    }

    private func setupChevron() {
        chevronItem.autosaveName = "Dropbar-Chevron"
        guard let button = chevronItem.button else { return }
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Dropbar")
        button.target = self
        button.action = #selector(chevronClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func chevronClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleDropdown()
        }
    }

    // MARK: - Expand / Collapse

    private func expand() {
        separatorItem.length = Self.expandedLength
        separatorItem.button?.title = ""
    }

    private func collapse() {
        separatorItem.length = NSStatusItem.variableLength
        separatorItem.button?.title = "│"
    }

    private func captureSeparatorPosition() {
        if let window = separatorItem.button?.window {
            separatorX = window.frame.origin.x
        }
    }

    // MARK: - Dropdown

    private func toggleDropdown() {
        if Date().timeIntervalSince(lastCloseTime) < 0.3 { return }

        if let panel, panel.isVisible {
            panel.dismiss()
            return
        }

        showHiddenItems()
    }

    private func showHiddenItems() {
        // Collapse so items slide on-screen for scanning
        collapse()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }

            // Capture fresh separator position
            self.captureSeparatorPosition()

            let allItems = self.scanner.scanAndCapture()
            let hidden = MenuBarScanner.hiddenItems(from: allItems, separatorX: self.separatorX)

            // Re-expand to push items off
            self.expand()

            guard !hidden.isEmpty else { return }
            self.showPanel(with: hidden)
        }
    }

    // MARK: - Panel

    private func showPanel(with items: [MenuBarItem]) {
        guard let buttonWindow = chevronItem.button?.window else { return }

        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            self?.lastCloseTime = Date()
            self?.panel = nil
        }

        let content = DropbarContentView(items: items) { [weak self] item in
            self?.handleItemClick(item)
        }
        panel.show(anchoredBelow: buttonWindow, content: content)
        self.panel = panel
    }

    // MARK: - Click-through

    private func handleItemClick(_ item: MenuBarItem) {
        panel?.dismiss()

        // Collapse so target slides on-screen, click it, then re-expand
        collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.clickMenuItem(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.expand()
            }
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

        // Fresh frame after collapse — item is on-screen now
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
        chevronItem.menu = menu
        chevronItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.chevronItem.menu = nil
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
