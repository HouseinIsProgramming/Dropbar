import Cocoa

public class MenuBarScanner {
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    static let excludedOwners: Set<String> = ["Window Server"]
    static let maxStatusItemWidth: CGFloat = 200

    public init() {}

    /// Items whose right edge is fully left of the separator position.
    public static func hiddenItems(from items: [MenuBarItem], separatorX: CGFloat) -> [MenuBarItem] {
        items.filter { $0.frame.maxX <= separatorX }
    }

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

    func captureImage(for item: MenuBarItem) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            item.frame,
            .optionIncludingWindow,
            item.id,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return nil }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
        )
    }

    public func currentFrame(for windowID: CGWindowID) -> CGRect? {
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
        guard frame.height > 0,
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
