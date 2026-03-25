# Dropbar: Separator-Based Menu Bar Hiding

## Goal

```
[hidden items] │ [visible items] ▼ [system]
                ↑ user CMD+drags    ↑ always visible, opens dropdown
```

1. │ separator and ▼ chevron in the menu bar. User CMD+drags │ to position it.
2. Items LEFT of │ are hidden (pushed off-screen by separator expansion).
3. ▼ chevron is always visible.
4. Click ▼ → dropdown shows hidden items (captured images).
5. Click item in dropdown → activates it.
6. Close dropdown → items stay hidden.
7. Positions persist across restarts (autosaveName).

---

## How Ice Solves This (reference implementation)

Ice uses a **single NSStatusItem per section** that toggles between:
- **Collapsed** (`variableLength`): shows a chevron image — this IS the visible separator
- **Expanded** (`10,000px`): image set to nil, cell disabled — becomes **invisible spacer**

Key lessons from Ice:
- The separator **disappears when items are hidden**. Only the "Ice icon" stays visible.
- Off-screen items are **captured by CGWindowID** — no need to collapse first.
- Click-through: Ice physically **moves the hidden item on-screen** (synthesized CMD+drag), clicks it, then moves it back.

---

## Architecture

### Two NSStatusItems

| Item | Role | autosaveName | Behavior |
|------|------|-------------|----------|
| `separatorItem` | Divider │ + expander | `"Dropbar-Separator"` | Toggles between `variableLength` (shows │) and `10,000` (invisible, pushes items off) |
| `chevronItem` | Always-visible ▼ | `"Dropbar-Chevron"` | Fixed square length, never changes. Click opens dropdown. |

**Why not keep │ visible when expanded?** Because a 10,000px NSStatusBarButton does not reliably render text/overlays at its right edge. Tested: `button.alignment = .right`, attributed titles, NSView overlays — all fail or flicker. Ice confirms this by design: the divider disappears when expanded. This is the correct approach.

**User workflow for repositioning:**
1. Click ▼ to show dropdown (separator collapses, │ appears)
2. CMD+drag │ to new position
3. Click ▼ again or click away to dismiss (separator expands, │ disappears)
4. macOS remembers the new position via autosaveName

### State Machine

```
           click ▼           click ▼ / click outside
HIDDEN ─────────────► SHOWING ──────────────────────► HIDDEN
  │                      │
  │ separator.length     │ separator.length
  │ = 10,000             │ = variableLength
  │ button.image = nil   │ button.title = "│"
  │                      │
  │ items off-screen     │ items on-screen
  └──────────────────────┘
```

On launch → HIDDEN (after 0.5s delay for positions to settle).

---

## Implementation Plan

### Phase 1: Separator + Expansion (StatusBarController.swift)

**Setup:**
```swift
separatorItem = NSStatusBar.system.statusItem(withLength: .variableLength)
separatorItem.autosaveName = "Dropbar-Separator"
// button.title = "│" when collapsed
// button.title = "" + button.image = nil when expanded

chevronItem = NSStatusBar.system.statusItem(withLength: .squareLength)
chevronItem.autosaveName = "Dropbar-Chevron"
// button.image = chevron.down (always)
```

**Expand (hide items):**
```swift
func expandSeparator() {
    separatorItem.length = 10_000
    separatorItem.button?.title = ""
    separatorItem.button?.image = nil
}
```

**Collapse (show items):**
```swift
func collapseSeparator() {
    separatorItem.length = NSStatusItem.variableLength
    separatorItem.button?.title = "│"
}
```

**Startup sequence:**
1. Create chevronItem (rightmost)
2. Create separatorItem (to its left)
3. `collapseSeparator()` initially (show │)
4. After 0.5s delay: `expandSeparator()` (push items off, │ disappears)

### Phase 2: Scanning Hidden Items (MenuBarScanner.swift)

**Two scan modes:**
- `scan()` — current, uses `.optionOnScreenOnly`. Keep for visible items.
- `scanAll()` — new, uses all windows. Needed to find off-screen hidden items.

```swift
public func scanAll() -> [MenuBarItem] {
    guard let windowList = CGWindowListCopyWindowInfo(
        CGWindowListOption(rawValue: 0), // kCGWindowListOptionAll = 0
        kCGNullWindowID
    ) as? [[String: Any]] else { return [] }

    return windowList
        .compactMap { parseWindow($0) }
        .sorted { $0.frame.origin.x < $1.frame.origin.x }
}
```

**Modify `parseWindow`**: remove the `frame.origin.y == 0` check for scanAll, since off-screen items may have y=0 but x < 0. Actually keep y == 0 — off-screen items still have y=0, just negative x. The filter `frame.origin.y == 0` is fine. But remove the implicit "on-screen" assumption — items with negative x are valid hidden items.

**Image capture for off-screen items:**
`CGWindowListCreateImage` with `.optionIncludingWindow` captures by windowID regardless of screen position. The current `captureImage(for:)` should work as-is.

Test this: if capture returns nil for off-screen windows, fall back to collapse→capture→expand approach.

**Filtering hidden items:**
```swift
public static func hiddenItems(from items: [MenuBarItem], separatorX: CGFloat) -> [MenuBarItem] {
    items.filter { $0.frame.maxX <= separatorX }
}
```
Already implemented. Keep as-is.

### Phase 3: Show Dropdown (StatusBarController.swift)

**When ▼ is clicked:**

Option A — Off-screen capture (preferred, no flicker):
1. Get separator's saved position (need to read it BEFORE expanding, or store it when collapsing)
2. `scanAll()` to find all menu bar items including off-screen
3. Filter to items left of separator position
4. Capture images by windowID
5. Show panel with captured images
6. Do NOT collapse the separator — items stay hidden

Problem: we need the separator's collapsed position, but it's currently expanded. Store `lastSeparatorX` when collapsing:
```swift
private var lastSeparatorX: CGFloat = 0

func collapseSeparator() {
    separatorItem.length = NSStatusItem.variableLength
    separatorItem.button?.title = "│"
    // Read position after a brief delay for layout
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        if let x = self?.separatorItem.button?.window?.frame.origin.x {
            self?.lastSeparatorX = x
        }
    }
}
```

On first launch, we collapse briefly to capture position, then expand.

Option B — Collapse→scan→expand (fallback, has brief flicker):
1. Collapse separator (items slide on-screen, │ appears)
2. Wait 150ms for reposition
3. Get separator position from button window
4. Scan + capture images
5. Expand separator (items hidden, │ disappears)
6. Show panel

The flicker is ~200ms. Acceptable as fallback.

**Recommendation: Start with Option B (simpler). Move to Option A once the basics work.**

### Phase 4: Click-Through

**When user clicks an item in the dropdown:**

Simple approach (not Ice's complex move-and-click):
1. Dismiss panel
2. Collapse separator (target item slides on-screen)
3. Wait 150ms
4. Post targeted CGEvents at the item's FRESH frame position
5. Wait 500ms for the click to register
6. Expand separator (items hidden again)

The existing `clickMenuItem` code is correct for this — it posts CGEvents with `eventTargetUnixProcessID` and `mouseEventWindowUnderMousePointer` fields.

**Enhancement**: use `currentFrame(for:)` right before clicking to get the item's real-time position (it may have shifted during collapse).

### Phase 5: Panel (DropbarPanel.swift + PopoverView.swift)

Already mostly correct. Verify:
- Panel level: `.mainMenu + 1` ✓
- Style: `.nonactivatingPanel, .fullSizeContentView, .borderless` ✓
- `isFloatingPanel = true` ✓
- Click-outside dismissal via global monitor ✓
- Anchored below chevron's button window ✓

**One change needed**: anchor the panel below the **chevron** (not the separator), since the chevron is always visible.

### Phase 6: Persistence

`autosaveName` on both items handles this automatically. macOS persists:
- Relative ordering of status items
- User's CMD+drag positions

No additional persistence code needed.

---

## File Changes Summary

| File | Changes |
|------|---------|
| `StatusBarController.swift` | Full rewrite: two-item setup, expand/collapse with title toggling, state tracking, `lastSeparatorX` |
| `MenuBarScanner.swift` | Add `scanAll()` method (all windows, not just on-screen). Keep `hiddenItems(from:separatorX:)`. |
| `DropbarPanel.swift` | No changes needed |
| `PopoverView.swift` | No changes needed |
| `MenuBarItem.swift` | No changes needed |
| `AppDelegate.swift` | No changes needed |

## Test Plan

| Test | File |
|------|------|
| `hiddenItems` filtering (boundary, overlap, empty) | `SeparatorFilteringTests` ✓ exists |
| `parseWindow` validation (layer, bounds, PID) | `MenuBarScannerTests` ✓ exists |
| `scanAll` returns items with negative x | New test |
| Expand sets length to 10,000 and clears title | Manual verification (needs running app) |
| Collapse sets variableLength and restores │ | Manual verification |
| CMD+drag separator changes position | Manual verification |
| Position persists across restart | Manual verification (kill + relaunch) |
| Click-through activates target app's menu | Manual verification |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `CGWindowListCreateImage` returns nil for off-screen items | Fall back to collapse→capture→expand approach |
| Collapse→expand flicker is noticeable | Keep it to ~200ms. Consider Option A (off-screen capture) if annoying |
| User CMD+drags separator out of order | autosaveName handles ordering. If chevron ends up left of separator, items won't hide correctly — add a position sanity check |
| Click-through doesn't activate target (off-screen coords) | Always collapse before clicking — use fresh on-screen frame |
| Re-expand while target's menu is open closes the menu | Use longer delay (1-2s) or detect menu dismissal before re-expanding |

---

## Execution Order

1. Revert StatusBarController to clean baseline (remove overlay attempt)
2. Implement Phase 1 (separator expand/collapse with title toggle)
3. Test manually: │ visible when collapsed, invisible when expanded, items push off
4. Implement Phase 2 (scanAll or collapse-scan-expand)
5. Implement Phase 3 (dropdown shows only hidden items)
6. Test manually: click ▼ shows correct items in dropdown
7. Implement Phase 4 (click-through with collapse)
8. Test manually: clicking item in dropdown activates it
9. Run all unit tests
10. Final manual test of full flow
