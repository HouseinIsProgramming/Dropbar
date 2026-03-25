import Cocoa

struct MenuBarItem: Identifiable {
    let id: CGWindowID
    let ownerName: String
    let ownerPID: pid_t
    let frame: CGRect
    var image: NSImage?
}
