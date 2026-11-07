import XCTest
@testable import Dayform

/// Drives the right-⌥ state machine with fake presses (no keyboard needed).
@MainActor
final class RightOptionKeyTests: XCTestCase {
    private var log: [String] = []
    private var k: RightOptionKey { RightOptionKey.shared }
    private var saved: [Any?] = []

    override func setUp() async throws {
        // Swap the real handlers for recorders, restore them afterwards.
        saved = [k.onTap, k.onHoldStart, k.onHoldEnd, k.onMakeTask, k.onMeeting, k.onDoubleTap, k.onPasteLast, k.onEscape, k.tapIsImmediate]
        log = []
        k.reset()
        k.onTap = { [weak self] in self?.log.append("tap") }
        k.onHoldStart = { [weak self] in self?.log.append("holdStart") }
        k.onHoldEnd = { [weak self] in self?.log.append("holdEnd") }
        k.onMakeTask = { [weak self] in self?.log.append("task") }
        k.onMeeting = { [weak self] in self?.log.append("meeting") }
        k.onDoubleTap = { [weak self] in self?.log.append("double") }
        k.onPasteLast = { [weak self] in self?.log.append("paste") }
        k.onEscape = { [weak self] in self?.log.append("esc"); return true }
        k.tapIsImmediate = { false }
    }

    override func tearDown() async throws {
        k.onTap = saved[0] as? () -> Void; k.onHoldStart = saved[1] as? () -> Void; k.onHoldEnd = saved[2] as? () -> Void
        k.onMakeTask = saved[3] as? () -> Void; k.onMeeting = saved[4] as? () -> Void; k.onDoubleTap = saved[5] as? () -> Void
        k.onPasteLast = saved[6] as? () -> Void; k.onEscape = saved[7] as? () -> Bool; k.tapIsImmediate = saved[8] as? () -> Bool
    }

    private func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }

    func testHoldDictates() async {
        k.rightOption(down: true); await wait(0.35); k.rightOption(down: false); await wait(0.05)
        XCTAssertEqual(log, ["holdStart", "holdEnd"])
    }

    func testSingleTapOpensAfterDoubleTapWindow() async {
        k.rightOption(down: true); await wait(0.05); k.rightOption(down: false)
        XCTAssertEqual(log, [])            // waits to see if a second tap comes
        await wait(0.4)
        XCTAssertEqual(log, ["tap"])
    }

    func testDoubleTapIsHandsFree() async {
        k.rightOption(down: true); await wait(0.05); k.rightOption(down: false); await wait(0.1)
        k.rightOption(down: true); await wait(0.05); k.rightOption(down: false); await wait(0.4)
        XCTAssertEqual(log, ["double"])
    }

    func testTapStopsImmediatelyInHandsFree() async {
        k.tapIsImmediate = { true }
        k.rightOption(down: true); await wait(0.05); k.rightOption(down: false); await wait(0.02)
        XCTAssertEqual(log, ["tap"])
    }

    func testHoldThenTMakesTask() async {
        k.rightOption(down: true); await wait(0.3)
        XCTAssertTrue(k.key(17, down: true)); XCTAssertTrue(k.key(17, down: false))
        k.rightOption(down: false); await wait(0.05)
        XCTAssertEqual(log, ["holdStart", "task", "holdEnd"])
    }

    func testQuickTStartsTaskDictation() async {
        k.rightOption(down: true)
        XCTAssertTrue(k.key(17, down: true))          // T before the hold kicks in
        k.rightOption(down: false); await wait(0.4)
        XCTAssertEqual(log, ["holdStart", "task", "holdEnd"])
    }

    func testMStartsMeetingAndIsNotATap() async {
        k.rightOption(down: true)
        XCTAssertTrue(k.key(46, down: true)); _ = k.key(46, down: false)
        k.rightOption(down: false); await wait(0.4)
        XCTAssertEqual(log, ["meeting"])
    }

    func testVPastesLast() async {
        k.rightOption(down: true)
        XCTAssertTrue(k.key(9, down: true)); _ = k.key(9, down: false)
        k.rightOption(down: false); await wait(0.4)
        XCTAssertEqual(log, ["paste"])
    }

    func testOtherKeysPassThroughAndCancelTap() async {
        k.rightOption(down: true)
        XCTAssertFalse(k.key(0, down: true))           // ⌥A types normally
        k.rightOption(down: false); await wait(0.4)
        XCTAssertEqual(log, [])
    }

    func testEscOnlyWhenNotHolding() async {
        XCTAssertTrue(k.key(53, down: true))
        XCTAssertEqual(log, ["esc"])
        XCTAssertFalse(k.key(0, down: true))           // plain keys untouched
    }

    func testMissedReleaseDoesNotEatTheNextPress() async {
        k.rightOption(down: true); await wait(0.35)        // hold starts, then the release is lost
        k.rightOption(down: true); await wait(0.35)        // next press: the old hold ends, a new one starts
        k.rightOption(down: false); await wait(0.05)
        XCTAssertEqual(log, ["holdStart", "holdEnd", "holdStart", "holdEnd"])
    }

    func testTellsRightOptionFromLeft() {
        let alt = CGEventFlags.maskAlternate.rawValue
        XCTAssertTrue(RightOptionKey.isRightOptionDown(CGEventFlags(rawValue: alt | 0x40)))
        XCTAssertFalse(RightOptionKey.isRightOptionDown(CGEventFlags(rawValue: alt | 0x20)))   // left ⌥ only
        XCTAssertFalse(RightOptionKey.isRightOptionDown(CGEventFlags(rawValue: 0x100)))        // nothing held
        XCTAssertTrue(RightOptionKey.isRightOptionDown(.maskAlternate))                          // no device bits
    }
}
