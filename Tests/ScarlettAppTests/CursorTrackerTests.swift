import XCTest
@testable import ScarlettApp

/// The cursor stack must stay balanced: one pop for every push.
final class CursorTrackerTests: XCTestCase {
    private func depth(_ actions: [CursorTracker.Action?]) -> Int {
        actions.reduce(0) { $0 + ($1 == .push ? 1 : $1 == .pop ? -1 : 0) }
    }

    func testHoverPushesOnEntryAndPopsOnExit() {
        var t = CursorTracker()
        XCTAssertEqual(t.hover(inside: true, enabled: true, holding: false), .push)
        XCTAssertEqual(t.hover(inside: false, enabled: true, holding: false), .pop)
        XCTAssertFalse(t.active)
    }

    func testEnteringTwiceOrLeavingTwiceDoesNotUnbalanceTheStack() {
        var t = CursorTracker()
        let actions = [
            t.hover(inside: true, enabled: true, holding: false),
            t.hover(inside: true, enabled: true, holding: false),
            t.hover(inside: false, enabled: true, holding: false),
            t.hover(inside: false, enabled: true, holding: false),
        ]
        XCTAssertEqual(depth(actions), 0)
    }

    func testADisabledControlNeverShowsTheCursor() {
        var t = CursorTracker()
        XCTAssertNil(t.hover(inside: true, enabled: false, holding: false))
        XCTAssertNil(t.hover(inside: false, enabled: false, holding: false))
    }

    func testDisablingWhileHoveringDropsTheCursor() {
        var t = CursorTracker()
        _ = t.hover(inside: true, enabled: true, holding: false)
        XCTAssertEqual(t.enabledChanged(enabled: false), .pop)
        XCTAssertNil(t.hover(inside: false, enabled: false, holding: false))
    }

    func testTheCursorStaysForADragThatLeavesTheControl() {
        var t = CursorTracker()
        var actions = [t.hover(inside: true, enabled: true, holding: false)]
        actions.append(t.hover(inside: false, enabled: true, holding: true))      // dragged off
        XCTAssertEqual(depth(actions), 1, "still showing while the drag goes on")
        actions.append(t.holdingChanged(holding: false))                          // released
        XCTAssertEqual(depth(actions), 0)
    }

    func testReleasingBackOnTheControlKeepsTheCursorUntilThePointerLeaves() {
        var t = CursorTracker()
        var actions = [t.hover(inside: true, enabled: true, holding: false)]
        actions.append(t.hover(inside: false, enabled: true, holding: true))      // dragged off
        actions.append(t.hover(inside: true, enabled: true, holding: true))       // and back
        actions.append(t.holdingChanged(holding: false))                          // released on it
        XCTAssertEqual(depth(actions), 1)
        actions.append(t.hover(inside: false, enabled: true, holding: false))
        XCTAssertEqual(depth(actions), 0)
    }

    func testRemovalWhileHoveringReleasesTheCursor() {
        var t = CursorTracker()
        var actions = [t.hover(inside: true, enabled: true, holding: false)]
        actions.append(t.disappeared())
        actions.append(t.disappeared())
        XCTAssertEqual(depth(actions), 0)
    }

    func testChangingTheCursorOnlySwapsWhileItIsShowing() {
        var t = CursorTracker()
        XCTAssertNil(t.cursorChanged())
        _ = t.hover(inside: true, enabled: true, holding: false)
        XCTAssertEqual(t.cursorChanged(), .swap)
    }
}
