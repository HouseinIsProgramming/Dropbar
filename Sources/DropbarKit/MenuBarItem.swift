import Cocoa

public struct MenuBarItem: Identifiable, Equatable {
    public let id: CGWindowID
    public let ownerName: String
    public let ownerPID: pid_t
    public let frame: CGRect
    public var image: NSImage?

    public init(id: CGWindowID, ownerName: String, ownerPID: pid_t, frame: CGRect, image: NSImage? = nil) {
        self.id = id
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.frame = frame
        self.image = image
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
