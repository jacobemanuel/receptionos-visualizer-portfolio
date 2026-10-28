import XCTest
@testable import SceneLifecycle

final class SceneLifecycleReducerTests: XCTestCase {
    func testFirstWindowComesUp() {
        var reducer = SceneLifecycleReducer()
        XCTAssertEqual(reducer.receive(.connect("main")).forwardedEvents, [])
        XCTAssertEqual(reducer.receive(.willEnterForeground("main")).forwardedEvents, [.willEnterForeground])
        XCTAssertEqual(reducer.receive(.didBecomeActive("main")).forwardedEvents, [.didBecomeActive])
        XCTAssertEqual(reducer.deliveredPhase, .foregroundActive)
    }

    // the case the reducer exists for: focus goes from one window to another and unity hears nothing
    func testFocusMovingBetweenWindowsReachesUnityAsNothing() {
        var reducer = activeReducer(["main"])

        let resign = reducer.receive(.willResignActive("main"))
        XCTAssertEqual(resign.forwardedEvents, [])
        guard case .schedule = resign.settleDirective else { return XCTFail("expected a settle window") }

        let otherWindow = reducer.receive(.didBecomeActive("models"))
        XCTAssertEqual(otherWindow.forwardedEvents, [])
        XCTAssertEqual(otherWindow.settleDirective, .cancel)
        XCTAssertEqual(reducer.deliveredPhase, .foregroundActive)
    }

    // uikit can report background before resign. unity still gets resign first
    func testRealBackgroundIsForwardedAfterTheSettleWindowInOrder() {
        var reducer = activeReducer(["main"])

        let background = reducer.receive(.didEnterBackground("main"))
        XCTAssertEqual(background.forwardedEvents, [])
        guard case .schedule(let generation) = background.settleDirective else { return XCTFail("expected a settle window") }

        let settled = reducer.settle(generation: generation)
        XCTAssertEqual(settled.forwardedEvents, [.willResignActive, .didEnterBackground])
        XCTAssertEqual(reducer.deliveredPhase, .background)
    }

    func testOldSettleTimerDoesNothing() {
        var reducer = activeReducer(["main"])
        guard case .schedule(let first) = reducer.receive(.willResignActive("main")).settleDirective else { return XCTFail() }
        XCTAssertEqual(reducer.receive(.didBecomeActive("main")).settleDirective, .cancel)
        guard case .schedule(let second) = reducer.receive(.willResignActive("main")).settleDirective else { return XCTFail() }
        XCTAssertNotEqual(first, second)

        XCTAssertEqual(reducer.settle(generation: first).forwardedEvents, [])
        XCTAssertEqual(reducer.deliveredPhase, .foregroundActive)

        XCTAssertEqual(reducer.settle(generation: second).forwardedEvents, [.willResignActive])
        XCTAssertEqual(reducer.deliveredPhase, .foregroundInactive)
    }

    func testClosingOneOfTwoWindowsKeepsUnityRunning() {
        var reducer = activeReducer(["main", "guide"])
        let closed = reducer.receive(.disconnect("guide"))
        XCTAssertEqual(closed.forwardedEvents, [])
        XCTAssertEqual(closed.settleDirective, .unchanged)
        XCTAssertEqual(closed.snapshot.connectedCount, 1)
        XCTAssertEqual(reducer.deliveredPhase, .foregroundActive)
    }

    func testRepeatedCallbacksForwardNothingTwice() {
        var reducer = activeReducer(["main"])
        XCTAssertEqual(reducer.receive(.didBecomeActive("main")).forwardedEvents, [])
        XCTAssertEqual(reducer.receive(.willEnterForeground("main")).forwardedEvents, [])
    }

    func testComingBackFromBackgroundForwardsForegroundThenActive() {
        var reducer = activeReducer(["main"])
        guard case .schedule(let generation) = reducer.receive(.didEnterBackground("main")).settleDirective else { return XCTFail() }
        _ = reducer.settle(generation: generation)

        let back = reducer.receive(.didBecomeActive("main"))
        XCTAssertEqual(back.forwardedEvents, [.willEnterForeground, .didBecomeActive])
        XCTAssertEqual(reducer.deliveredPhase, .foregroundActive)
    }

    private func activeReducer(_ sceneIDs: [String]) -> SceneLifecycleReducer {
        var reducer = SceneLifecycleReducer()
        for id in sceneIDs {
            _ = reducer.receive(.connect(id))
            _ = reducer.receive(.willEnterForeground(id))
            _ = reducer.receive(.didBecomeActive(id))
        }
        return reducer
    }
}
