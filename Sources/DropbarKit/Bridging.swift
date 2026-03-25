import Cocoa

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetScreenRectForWindow")
func CGSGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: UnsafeMutablePointer<CGRect>
) -> CGError

enum WindowBridging {
    static func getWindowFrame(for windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        let result = CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect)
        return result == .success ? rect : nil
    }

    static func getWindowID(for statusItem: NSStatusItem) -> CGWindowID? {
        guard let wn = statusItem.button?.window?.windowNumber, wn > 0 else { return nil }
        return UInt32(exactly: wn).map { CGWindowID($0) }
    }
}
