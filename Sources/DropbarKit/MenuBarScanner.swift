import Cocoa

public class MenuBarScanner {
    private let ownPID = ProcessInfo.processInfo.processIdentifier

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

    public func captureImage(for item: MenuBarItem) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            item.frame,
            .optionIncludingWindow,
            item.id,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return nil }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: item.frame.width, height: item.frame.height)
        )
    }

    func parseWindow(_ info: [String: Any]) -> MenuBarItem? {
        guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
              let ownerName = info[kCGWindowOwnerName as String] as? String,
              let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let layer = info[kCGWindowLayer as String] as? Int
        else { return nil }

        let frame = CGRect(
            x: bounds["X"] ?? 0,
            y: bounds["Y"] ?? 0,
            width: bounds["Width"] ?? 0,
            height: bounds["Height"] ?? 0
        )

        let menuBarHeight = NSStatusBar.system.thickness

        guard layer == 25,
              frame.origin.y == 0,
              frame.height <= menuBarHeight + 10,
              frame.width > 0,
              ownerPID != ownPID
        else { return nil }

        return MenuBarItem(
            id: windowID,
            ownerName: ownerName,
            ownerPID: pid_t(ownerPID),
            frame: frame
        )
    }
}
