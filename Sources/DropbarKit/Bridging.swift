import Cocoa

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSetWindowAlpha")
func CGSSetWindowAlpha(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ alpha: Float
) -> CGError

enum WindowBridging {
    static func setAlpha(_ alpha: Float, for windowID: CGWindowID) -> Bool {
        let result = CGSSetWindowAlpha(CGSMainConnectionID(), windowID, alpha)
        let ok = result == .success
        if !ok {
            print("[Bridging] CGSSetWindowAlpha(wid=\(windowID), alpha=\(alpha)) FAILED: \(result.rawValue)")
        }
        return ok
    }

    static func hideWindow(_ windowID: CGWindowID) -> Bool {
        print("[Bridging] hideWindow(\(windowID))")
        return setAlpha(0.0, for: windowID)
    }

    static func showWindow(_ windowID: CGWindowID) -> Bool {
        print("[Bridging] showWindow(\(windowID))")
        return setAlpha(1.0, for: windowID)
    }
}
