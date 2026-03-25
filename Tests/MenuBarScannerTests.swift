import XCTest
@testable import DropbarKit

final class MenuBarScannerTests: XCTestCase {
    private var scanner: MenuBarScanner!

    override func setUp() {
        scanner = MenuBarScanner()
    }

    // MARK: - Valid parsing

    func testParsesValidStatusItem() {
        let info = makeWindowInfo()
        let result = scanner.parseWindow(info)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, 42)
        XCTAssertEqual(result?.ownerName, "Spotify")
        XCTAssertEqual(result?.ownerPID, 1234)
        XCTAssertEqual(result?.frame.origin.x, 800)
        XCTAssertEqual(result?.frame.width, 26)
    }

    // MARK: - Rejection cases

    func testRejectsWrongLayer() {
        let info = makeWindowInfo(layer: 0)
        XCTAssertNil(scanner.parseWindow(info), "should reject non-menu-bar layer")
    }

    func testRejectsOffScreenY() {
        let info = makeWindowInfo(y: 100)
        XCTAssertNil(scanner.parseWindow(info), "should reject windows not at top of screen")
    }

    func testRejectsZeroWidth() {
        let info = makeWindowInfo(width: 0)
        XCTAssertNil(scanner.parseWindow(info), "should reject zero-width windows")
    }

    func testRejectsTooWide() {
        let info = makeWindowInfo(width: 250)
        XCTAssertNil(scanner.parseWindow(info), "should reject windows wider than max status item width")
    }

    func testRejectsZeroHeight() {
        let info = makeWindowInfo(height: 0)
        XCTAssertNil(scanner.parseWindow(info), "should reject zero-height windows")
    }

    func testRejectsTooTall() {
        let info = makeWindowInfo(height: 80)
        XCTAssertNil(scanner.parseWindow(info), "should reject windows taller than menu bar")
    }

    func testRejectsWindowServer() {
        let info = makeWindowInfo(ownerName: "Window Server")
        XCTAssertNil(scanner.parseWindow(info), "should reject Window Server windows")
    }

    func testRejectsOwnPID() {
        let info = makeWindowInfo(ownerPID: ProcessInfo.processInfo.processIdentifier)
        XCTAssertNil(scanner.parseWindow(info), "should reject own PID")
    }

    func testRejectsMissingFields() {
        let partial: [String: Any] = [kCGWindowNumber as String: CGWindowID(1)]
        XCTAssertNil(scanner.parseWindow(partial), "should reject incomplete window info")
    }

    func testRejectsMissingBounds() {
        let info: [String: Any] = [
            kCGWindowNumber as String: CGWindowID(1),
            kCGWindowOwnerName as String: "TestApp",
            kCGWindowOwnerPID as String: Int32(9999),
            kCGWindowLayer as String: 25,
        ]
        XCTAssertNil(scanner.parseWindow(info), "should reject missing bounds")
    }

    // MARK: - Edge cases

    func testAcceptsMaxValidWidth() {
        let info = makeWindowInfo(width: 199)
        XCTAssertNotNil(scanner.parseWindow(info), "should accept width below threshold")
    }

    func testRejectsExactMaxWidth() {
        let info = makeWindowInfo(width: MenuBarScanner.maxStatusItemWidth)
        XCTAssertNil(scanner.parseWindow(info), "should reject width at threshold")
    }

    func testAcceptsMenuBarHeight() {
        let h = NSStatusBar.system.thickness
        let info = makeWindowInfo(height: h)
        XCTAssertNotNil(scanner.parseWindow(info), "should accept exact menu bar height")
    }

    func testAcceptsSlightlyTallerThanMenuBar() {
        let h = NSStatusBar.system.thickness + 5
        let info = makeWindowInfo(height: h)
        XCTAssertNotNil(scanner.parseWindow(info), "should accept height within tolerance")
    }

    // MARK: - Position filtering

    func testItemsLeftOfFiltersByMaxX() {
        let items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 50, y: 0, width: 30, height: 24)),
            MenuBarItem(id: 2, ownerName: "B", ownerPID: 2, frame: CGRect(x: 150, y: 0, width: 30, height: 24)),
            MenuBarItem(id: 3, ownerName: "C", ownerPID: 3, frame: CGRect(x: 250, y: 0, width: 30, height: 24)),
        ]

        let separatorX: CGFloat = 200
        let hidden = items.filter { $0.frame.maxX <= separatorX }

        XCTAssertEqual(hidden.count, 2)
        XCTAssertEqual(hidden[0].ownerName, "A")
        XCTAssertEqual(hidden[1].ownerName, "B")
    }

    func testItemsLeftOfExcludesOverlapping() {
        let items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 190, y: 0, width: 30, height: 24)),
        ]

        let separatorX: CGFloat = 200
        let hidden = items.filter { $0.frame.maxX <= separatorX }

        XCTAssertEqual(hidden.count, 0, "item overlapping separator should not be hidden")
    }

    // MARK: - MenuBarItem equality

    func testMenuBarItemEqualityByID() {
        let a = MenuBarItem(id: 42, ownerName: "A", ownerPID: 1, frame: .zero)
        let b = MenuBarItem(id: 42, ownerName: "B", ownerPID: 2, frame: CGRect(x: 100, y: 0, width: 30, height: 24))
        let c = MenuBarItem(id: 99, ownerName: "A", ownerPID: 1, frame: .zero)

        XCTAssertEqual(a, b, "items with same ID should be equal")
        XCTAssertNotEqual(a, c, "items with different IDs should not be equal")
    }

    // MARK: - Helpers

    private func makeWindowInfo(
        windowID: CGWindowID = 42,
        ownerName: String = "Spotify",
        ownerPID: Int32 = 1234,
        layer: Int = 25,
        x: CGFloat = 800,
        y: CGFloat = 0,
        width: CGFloat = 26,
        height: CGFloat = 24
    ) -> [String: Any] {
        [
            kCGWindowNumber as String: windowID,
            kCGWindowOwnerName as String: ownerName,
            kCGWindowOwnerPID as String: ownerPID,
            kCGWindowBounds as String: [
                "X": x, "Y": y, "Width": width, "Height": height,
            ],
            kCGWindowLayer as String: layer,
        ]
    }
}
