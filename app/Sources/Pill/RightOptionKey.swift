import AppKit
import CoreGraphics
import os

/// Everything runs from the right Option key:
///   tap            → swap between the pill and the Oatmeal window
///   hold           → dictate into the app you're in (let go to type it)
///   hold, then T   → this dictation becomes a task instead
///   right ⌥ + M    → start or stop meeting notes
///
/// Needs an event tap (Accessibility), because ordinary hot keys can't tell
/// the right Option key from the left one. Keys pressed with right ⌥ held are
/// swallowed, so ⌥T / ⌥M don't type † or µ into the app underneath.
///
/// The tap runs on its own thread. On the main thread, any stall (a SwiftData save, a big redraw) made
/// macOS disable the tap, and presses in that gap were simply lost.
@MainActor
final class RightOptionKey {
    static let shared = RightOptionKey()

    var onTap: (() -> Void)?
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    var onMakeTask: (() -> Void)?
    var onMeeting: (() -> Void)?
    /// Double-tap right ⌥: hands-free, keeps listening until the next tap.
    var onDoubleTap: (() -> Void)?
    /// Right ⌥ + V: paste the last dictation again.
    var onPasteLast: (() -> Void)?
    /// Esc while listening. Return true to swallow the key.
    var onEscape: (() -> Bool)?
    /// While hands-free is on, a single tap should stop right away.
    var tapIsImmediate: (() -> Bool)?
    private var pendingTap: DispatchWorkItem?
    private let doubleTapWindow: TimeInterval = 0.28

    private(set) var isInstalled = false
    private var warned = false
    nonisolated(unsafe) fileprivate static var machPort: CFMachPort?
    /// Esc belongs to Oatmeal right now (listening, or the copy card is up), so the tap swallows it.
    nonisolated static let escapeIsOurs = OSAllocatedUnfairLock(initialState: false)
    private var downAt: Date?
    private var holding = false
    private var usedAsModifier = false
    private var holdWork: DispatchWorkItem?

    /// How long right ⌥ has to stay down before it counts as a hold.
    private let holdDelay: TimeInterval = 0.22
    nonisolated fileprivate static let rightOptionKeyCode: Int64 = 61
    nonisolated fileprivate static let keyT: Int64 = 17, keyM: Int64 = 46, keyV: Int64 = 9

    /// Is the right ⌥ itself down? The device bits tell left (0x20) from right (0x40); a keyboard
    /// or remapper that sends neither falls back to "any ⌥".
    nonisolated static func isRightOptionDown(_ flags: CGEventFlags) -> Bool {
        let raw = flags.rawValue
        if raw & 0x60 == 0 { return flags.contains(.maskAlternate) }
        return raw & 0x40 != 0
    }

    private init() {}

    @discardableResult
    func install() -> Bool {
        guard Self.machPort == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask), callback: rightOptionCallback, userInfo: nil) else {
            if !warned { print("[RightOption] Event tap unavailable (needs Accessibility); retrying quietly"); warned = true }
            return false
        }
        Self.machPort = t
        let thread = Thread {
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Oatmeal right ⌥"
        thread.qualityOfService = .userInteractive
        thread.start()
        isInstalled = true
        DFLog.log("key", "listening for right \u{2325}")
        return true
    }

    fileprivate var isRightOptionDown: Bool { downAt != nil }

    /// Forget any press in progress (tests start from a clean slate).
    func reset() {
        holdWork?.cancel(); pendingTap?.cancel(); pendingTap = nil
        downAt = nil; holding = false; usedAsModifier = false
    }

    func rightOption(down: Bool) {
        if down {
            // Down while we think it's already down: the release got lost somewhere. Finish that
            // press first rather than ignore this one (which used to eat the next press).
            if downAt != nil { DFLog.log("key", "right \u{2325} down twice: a release was missed"); rightOption(down: false) }
            downAt = Date(); usedAsModifier = false; holding = false
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.downAt != nil, !self.usedAsModifier else { return }
                self.holding = true
                self.onHoldStart?()
            }
            holdWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: work)
        } else {
            guard downAt != nil else { return }
            holdWork?.cancel()
            downAt = nil
            if holding { holding = false; onHoldEnd?() }
            else if !usedAsModifier { registerTap() }
        }
    }

    private func registerTap() {
        if tapIsImmediate?() == true { pendingTap?.cancel(); pendingTap = nil; onTap?(); return }
        if let p = pendingTap {
            p.cancel(); pendingTap = nil
            onDoubleTap?()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.pendingTap = nil; self?.onTap?() }
        pendingTap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
    }

    /// Returns true when the key was ours and should be swallowed.
    func key(_ code: Int64, down: Bool) -> Bool {
        if code == 53, down, downAt == nil { return onEscape?() ?? false }
        guard downAt != nil else { return false }
        if code == Self.keyV {
            if down { usedAsModifier = true; holdWork?.cancel(); onPasteLast?() }
            return true
        }
        if code == Self.keyT {
            if down {
                if !holding { holdWork?.cancel(); holding = true; onHoldStart?() }
                onMakeTask?()
            }
            usedAsModifier = !holding
            return true
        }
        if code == Self.keyM {
            if down { usedAsModifier = true; holdWork?.cancel(); onMeeting?() }
            return true
        }
        // Any other key: right ⌥ is just a modifier this time.
        usedAsModifier = true
        holdWork?.cancel()
        return false
    }
}

/// Runs on the tap's own thread. It decides right away whether to swallow a key (it can't wait for
/// the main thread), then hands the press to `RightOptionKey` on the main thread, in order.
private func rightOptionCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DFLog.log("key", "macOS disabled the key tap (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabling")
        if let t = RightOptionKey.machPort { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    let rightDown = RightOptionKey.isRightOptionDown(event.flags)
    if type == .flagsChanged {
        guard code == RightOptionKey.rightOptionKeyCode else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async { MainActor.assumeIsolated { RightOptionKey.shared.rightOption(down: rightDown) } }
        return Unmanaged.passUnretained(event)
    }
    let down = type == .keyDown
    if code == 53, !rightDown {
        guard down, RightOptionKey.escapeIsOurs.withLock({ $0 }) else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async { MainActor.assumeIsolated { _ = RightOptionKey.shared.key(53, down: true) } }
        return nil
    }
    guard rightDown else { return Unmanaged.passUnretained(event) }
    DispatchQueue.main.async { MainActor.assumeIsolated { _ = RightOptionKey.shared.key(code, down: down) } }
    let ours = [RightOptionKey.keyT, RightOptionKey.keyM, RightOptionKey.keyV].contains(code)
    return ours ? nil : Unmanaged.passUnretained(event)
}
