import XCTest
@testable import DropbarKit

final class SeparatorFilteringTests: XCTestCase {

    // MARK: - hiddenItems(from:separatorX:)

    func testItemsFullyLeftOfSeparatorAreHidden() {
        let items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 50, y: 0, width: 30, height: 24)),
            MenuBarItem(id: 2, ownerName: "B", ownerPID: 2, frame: CGRect(x: 150, y: 0, width: 30, height: 24)),
            MenuBarItem(id: 3, ownerName: "C", ownerPID: 3, frame: CGRect(x: 250, y: 0, width: 30, height: 24)),
        ]
        let hidden = MenuBarScanner.hiddenItems(from: items, separatorX: 200)

        XCTAssertEqual(hidden.count, 2)
        XCTAssertEqual(hidden[0].ownerName, "A")
        XCTAssertEqual(hidden[1].ownerName, "B")
    }

    func testItemOverlappingSeparatorIsNotHidden() {
        let items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 190, y: 0, width: 30, height: 24)),
        ]
        let hidden = MenuBarScanner.hiddenItems(from: items, separatorX: 200)

        XCTAssertEqual(hidden.count, 0, "item straddling separator should stay visible")
    }

    func testItemRightOfSeparatorIsNotHidden() {
        let items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 300, y: 0, width: 30, height: 24)),
        ]
        let hidden = MenuBarScanner.hiddenItems(from: items, separatorX: 200)

        XCTAssertEqual(hidden.count, 0)
    }

    func testItemExactlyTouchingSeparatorIsHidden() {
        // maxX == separatorX → fully left, should be hidden
        let items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 170, y: 0, width: 30, height: 24)),
        ]
        let hidden = MenuBarScanner.hiddenItems(from: items, separatorX: 200)

        XCTAssertEqual(hidden.count, 1)
    }

    func testNoItemsHiddenWhenSeparatorAtLeftEdge() {
        let items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 50, y: 0, width: 30, height: 24)),
        ]
        let hidden = MenuBarScanner.hiddenItems(from: items, separatorX: 0)

        XCTAssertEqual(hidden.count, 0)
    }

    func testAllItemsHiddenWhenSeparatorAtFarRight() {
        let items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 50, y: 0, width: 30, height: 24)),
            MenuBarItem(id: 2, ownerName: "B", ownerPID: 2, frame: CGRect(x: 150, y: 0, width: 30, height: 24)),
        ]
        let hidden = MenuBarScanner.hiddenItems(from: items, separatorX: 10000)

        XCTAssertEqual(hidden.count, 2)
    }

    func testEmptyItemsReturnsEmpty() {
        let hidden = MenuBarScanner.hiddenItems(from: [], separatorX: 200)
        XCTAssertTrue(hidden.isEmpty)
    }

    func testHiddenItemsPreserveSortOrder() {
        let items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 50, y: 0, width: 30, height: 24)),
            MenuBarItem(id: 2, ownerName: "B", ownerPID: 2, frame: CGRect(x: 100, y: 0, width: 30, height: 24)),
            MenuBarItem(id: 3, ownerName: "C", ownerPID: 3, frame: CGRect(x: 150, y: 0, width: 30, height: 24)),
        ]
        let hidden = MenuBarScanner.hiddenItems(from: items, separatorX: 200)

        XCTAssertEqual(hidden.map(\.ownerName), ["A", "B", "C"])
    }
}
