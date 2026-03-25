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

    /// Look up a specific window's frame in CGWindowList by its window ID.
    /// This gives us the frame in Quartz coordinates — the same coordinate
    /// space as all scanned items.
    public func frameForWindow(id windowID: CGWindowID) -> CGRect? {
        guard windowID != 0 else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in windowList {
            guard let wID = info[kCGWindowNumber as String] as? CGWindowID,
                  wID == windowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            return CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        }
        return nil
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
