import AppKit
import Carbon

/// Global push-to-talk on ⌥ Space: press → `onPress`, release → `onRelease`.
///
/// Uses a Carbon hot key (same approach as Dollop's HotkeyManager) because
/// it fires while other apps are focused, needs no Accessibility grant, and
/// swallows the keystroke so ⌥ Space doesn't type a non-breaking space into
/// the frontmost app. Carbon delivers both kEventHotKeyPressed and
/// kEventHotKeyReleased, which is all hold-to-talk needs.
@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// ⌥⇧ Space: hold to speak a task.
    var onTaskPress: (() -> Void)?
    var onTaskRelease: (() -> Void)?
    /// ⌥ M: start or stop meeting notes.
    var onMeeting: (() -> Void)?
    /// ⌥ D: open Oatmeal.
    var onOpen: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var extraRefs: [EventHotKeyRef?] = []
    private var taskDown = false
    private var handlerRef: EventHandlerRef?
    private var isDown = false

    /// 'DYFM'
    nonisolated fileprivate static let signature = OSType(0x4459464D)
    private static let spaceKeyCode: UInt32 = 49

    private init() {}

    /// Register ⌥ Space. Safe to call more than once.
    func install() {
        ensureEventHandler()
        guard hotKeyRef == nil else { return }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(Self.spaceKeyCode, UInt32(optionKey), hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        print("[HotkeyService] Register ⌥ Space: status=\(status)")

        // id 2: ⌥⇧ Space, id 3: ⌥ M (kVK_ANSI_M = 46), id 4: ⌥ D (kVK_ANSI_D = 2)
        for (id, key, mods) in [(UInt32(2), Self.spaceKeyCode, UInt32(optionKey | shiftKey)),
                                (3, 46, UInt32(optionKey)), (4, 2, UInt32(optionKey))] {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(key, mods, EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &ref)
            extraRefs.append(ref)
        }
    }

    fileprivate func handle(id: UInt32, pressed: Bool) {
        switch id {
        case 2:
            if pressed { guard !taskDown else { return }; taskDown = true; onTaskPress?() }
            else { guard taskDown else { return }; taskDown = false; onTaskRelease?() }
        case 3: if pressed { onMeeting?() }
        case 4: if pressed { onOpen?() }
        default: handle(pressed: pressed)
        }
    }

    func uninstall() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        for ref in extraRefs { if let ref { UnregisterEventHotKey(ref) } }
        extraRefs = []
        if isDown {
            isDown = false
            onRelease?()
        }
    }

    fileprivate func handle(pressed: Bool) {
        // Guard against key-repeat presses and stray releases.
        if pressed {
            guard !isDown else { return }
            isDown = true
            onPress?()
        } else {
            guard isDown else { return }
            isDown = false
            onRelease?()
        }
    }

    // MARK: - Carbon event handler

    private func ensureEventHandler() {
        guard handlerRef == nil else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), oatmealHotkeyCallback,
                                         eventTypes.count, &eventTypes, nil, &handlerRef)
        print("[HotkeyService] Carbon event handler installed: status=\(status)")
    }
}

// Top-level C function for Carbon callback
private func oatmealHotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    // Not ours (another part of the app may register Carbon hot keys too).
    guard hotKeyID.signature == HotkeyService.signature else { return OSStatus(eventNotHandledErr) }

    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let id = hotKeyID.id
    // Carbon dispatches on the main thread; hop through the main queue so
    // press/release keep their order.
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotkeyService.shared.handle(id: id, pressed: pressed) }
    }
    return noErr
}
