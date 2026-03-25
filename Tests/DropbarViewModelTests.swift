import XCTest
@testable import DropbarKit

final class DropbarViewModelTests: XCTestCase {
    private var vm: DropbarViewModel!

    override func setUp() {
        vm = DropbarViewModel()
        vm.items = [
            MenuBarItem(id: 1, ownerName: "A", ownerPID: 1, frame: CGRect(x: 100, y: 0, width: 30, height: 24)),
            MenuBarItem(id: 2, ownerName: "B", ownerPID: 2, frame: CGRect(x: 200, y: 0, width: 30, height: 24)),
            MenuBarItem(id: 3, ownerName: "C", ownerPID: 3, frame: CGRect(x: 300, y: 0, width: 30, height: 24)),
        ]
    }

    func testInitiallyNoHiddenItems() {
        XCTAssertTrue(vm.hiddenIDs.isEmpty)
        XCTAssertEqual(vm.hiddenItems.count, 0)
        XCTAssertEqual(vm.visibleItems.count, 3)
    }

    func testToggleHidesItem() {
        vm.toggleHidden(vm.items[0])

        XCTAssertTrue(vm.hiddenIDs.contains(1))
        XCTAssertEqual(vm.hiddenItems.count, 1)
        XCTAssertEqual(vm.hiddenItems[0].id, 1)
        XCTAssertEqual(vm.visibleItems.count, 2)
    }

    func testToggleTwiceUnhidesItem() {
        vm.toggleHidden(vm.items[0])
        vm.toggleHidden(vm.items[0])

        XCTAssertFalse(vm.hiddenIDs.contains(1))
        XCTAssertEqual(vm.hiddenItems.count, 0)
        XCTAssertEqual(vm.visibleItems.count, 3)
    }

    func testMultipleItemsHidden() {
        vm.toggleHidden(vm.items[0])
        vm.toggleHidden(vm.items[2])

        XCTAssertEqual(vm.hiddenItems.count, 2)
        XCTAssertEqual(vm.visibleItems.count, 1)
        XCTAssertEqual(vm.visibleItems[0].id, 2)
    }

    func testHiddenItemsSortedByPosition() {
        vm.toggleHidden(vm.items[2]) // x=300
        vm.toggleHidden(vm.items[0]) // x=100

        XCTAssertEqual(vm.hiddenItems[0].id, 1) // x=100 first
        XCTAssertEqual(vm.hiddenItems[1].id, 3) // x=300 second
    }

    func testVisibleItemsSortedByPosition() {
        vm.toggleHidden(vm.items[1]) // hide middle item

        XCTAssertEqual(vm.visibleItems[0].id, 1) // x=100
        XCTAssertEqual(vm.visibleItems[1].id, 3) // x=300
    }
}
