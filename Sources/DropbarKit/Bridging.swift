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
    static func setAlpha(_ alpha: Float, for windowID: CGWindowID) {
        let result = CGSSetWindowAlpha(CGSMainConnectionID(), windowID, alpha)
        if result != .success {
            print("[Dropbar] CGSSetWindowAlpha(\(windowID), \(alpha)) failed: \(result.rawValue)")
        }
    }

    static func hideWindow(_ windowID: CGWindowID) {
        setAlpha(0.0, for: windowID)
    }

    static func showWindow(_ windowID: CGWindowID) {
        setAlpha(1.0, for: windowID)
    }
}
