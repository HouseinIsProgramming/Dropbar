import Cocoa

public class MenuBarScanner {
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    static let excludedOwners: Set<String> = ["Window Server"]
    static let maxStatusItemWidth: CGFloat = 200

    public init() {}

    public func scan() -> [MenuBarItem] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowList
            .compactMap { parseWindow($0) }
            .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    public func scanAndCapture() -> [MenuBarItem] {
        scan().map { item in
            var captured = item
            captured.image = captureImage(for: item)
            return captured
        }
    }

    public func itemsLeftOf(x: CGFloat) -> [MenuBarItem] {
        scanAndCapture().filter { $0.frame.maxX <= x }
    }

    /// Find the separator's frame using CGWindowList (same coordinate space
    /// as scanned items). Returns the leftmost of our own menu bar windows.
    public func separatorFrame() -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ownWindows: [CGRect] = windowList.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  ownerPID == ownPID,
                  layer == 25
            else { return nil }

            return CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        }

        // Separator is the leftmost of our two menu bar windows
        return ownWindows.min(by: { $0.origin.x < $1.origin.x })
    }

    public func captureImage(for item: MenuBarItem) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            item.frame,
            .optionIncludingWindow,
            item.id,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return nil }

        // Divide pixel dimensions by backing scale factor so the NSImage
        // renders at the correct point size with crisp Retina resolution.
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let size = NSSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
        return NSImage(cgImage: cgImage, size: size)
    }

    func parseWindow(_ info: [String: Any]) -> MenuBarItem? {
        guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
              let ownerName = info[kCGWindowOwnerName as String] as? String,
              let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let layer = info[kCGWindowLayer as String] as? Int
        else { return nil }

        guard !Self.excludedOwners.contains(ownerName) else { return nil }
        guard ownerPID != ownPID else { return nil }
        guard layer == 25 else { return nil }

        let frame = CGRect(
            x: bounds["X"] ?? 0,
            y: bounds["Y"] ?? 0,
            width: bounds["Width"] ?? 0,
            height: bounds["Height"] ?? 0
        )

        let menuBarHeight = NSStatusBar.system.thickness
        guard frame.origin.y == 0,
              frame.height > 0,
              frame.height <= menuBarHeight + 10,
              frame.width > 0,
              frame.width < Self.maxStatusItemWidth
        else { return nil }

        return MenuBarItem(
            id: windowID,
            ownerName: ownerName,
            ownerPID: pid_t(ownerPID),
            frame: frame
        )
    }
}
