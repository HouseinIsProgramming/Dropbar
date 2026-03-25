import Cocoa
import SwiftUI

public class StatusBarController: NSObject {
    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let scanner = MenuBarScanner()
    private let viewModel = DropbarViewModel()
    private var panel: DropbarPanel?
    private var imageCache: [CGWindowID: NSImage] = [:]
    private var lastCloseTime = Date.distantPast
    private var isCollapsed = false

    public override init() {
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "DropbarToggle5"

        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem.autosaveName = "DropbarSep5"

        super.init()

        if let b = toggleItem.button {
            b.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Dropbar")
            b.target = self
            b.action = #selector(toggleClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        separatorItem.button?.title = "│"
    }

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggle()
        }
    }

    private func toggle() {
        if Date().timeIntervalSince(lastCloseTime) < 0.3 { return }

        if let panel, panel.isVisible {
            panel.dismiss()
            return
        }

        // Expand to scan, then collapse and show panel
        if isCollapsed {
            separatorItem.length = NSStatusItem.variableLength
            separatorItem.button?.title = "│"
            isCollapsed = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let sepX = self.separatorItem.button?.window?.frame.origin.x ?? 0
            let items = self.scanner.scanAndCapture()

            let hidden = items.filter { $0.frame.maxX <= sepX }
            for item in items {
                if let img = item.image { self.imageCache[item.id] = img }
            }

            self.viewModel.hiddenIDs = Set(hidden.map(\.id))
            self.viewModel.items = hidden.map { item in
                var c = item
                if c.image == nil { c.image = self.imageCache[item.id] }
                return c
            }

            // Collapse
            self.separatorItem.length = 10_000
            self.separatorItem.button?.title = ""
            self.isCollapsed = true

            self.showPanel()
        }
    }

    private func showPanel() {
        guard let bw = toggleItem.button?.window else { return }
        let panel = DropbarPanel()
        panel.onClose = { [weak self] in
            self?.lastCloseTime = Date()
            self?.panel = nil
        }
        let content = DropbarContentView(
            viewModel: viewModel,
            onItemClicked: { [weak self] item in self?.handleItemClick(item) }
        )
        panel.show(anchoredBelow: bw, content: content)
        self.panel = panel
    }

    private func handleItemClick(_ item: MenuBarItem) {
        panel?.dismiss()
        separatorItem.length = NSStatusItem.variableLength
        separatorItem.button?.title = "│"
        isCollapsed = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.clickMenuItem(item)
        }
    }

    private func clickMenuItem(_ item: MenuBarItem) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let permitAll: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        if let s = CGEventSource(stateID: .combinedSessionState) {
            s.setLocalEventsFilterDuringSuppressionState(permitAll, state: .eventSuppressionStateRemoteMouseDrag)
            s.setLocalEventsFilterDuringSuppressionState(permitAll, state: .eventSuppressionStateSuppressionInterval)
            s.localEventsSuppressionInterval = 0
        }

        let frame = scanner.currentFrame(for: item.id) ?? item.frame
        let pt = CGPoint(x: frame.midX, y: frame.midY)

        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)
        else { return }

        let pid = Int64(item.ownerPID), wid = Int64(item.id)
        for e in [down, up] {
            e.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
            e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: wid)
            e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: wid)
            e.setIntegerValueField(.mouseEventClickState, value: 1)
            if let f = CGEventField(rawValue: 0x33) { e.setIntegerValueField(f, value: wid) }
        }

        let cur = CGEvent(source: nil)?.location ?? .zero
        CGDisplayHideCursor(CGMainDisplayID())
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        CGWarpMouseCursorPosition(cur)
        CGDisplayShowCursor(CGMainDisplayID())
    }

    private func showContextMenu() {
        let menu = NSMenu()
        if isCollapsed {
            menu.addItem(NSMenuItem(title: "Show All", action: #selector(showAll), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.toggleItem.menu = nil }
    }

    @objc private func showAll() {
        separatorItem.length = NSStatusItem.variableLength
        separatorItem.button?.title = "│"
        isCollapsed = false
        viewModel.hiddenIDs.removeAll()
    }

    @objc private func quit() {
        separatorItem.length = NSStatusItem.variableLength
        NSApp.terminate(nil)
    }
}
