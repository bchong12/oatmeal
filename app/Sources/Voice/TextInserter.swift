import AppKit
import ApplicationServices
import CoreGraphics

/// Pastes text into whatever app is frontmost, then puts the user's
/// clipboard back the way it was.
///
/// Needs Accessibility (posting ⌘V into another app). If we're not trusted
/// we prompt once via the system dialog and leave the text on the clipboard
/// so the user can paste it themselves.
///
/// "Is there a text field?" is answered through Accessibility, and many apps
/// (browsers, Electron, terminals) don't answer reliably. So the answer is
/// three-way: only a definite "no" shows the copy card. When we can't tell we
/// paste anyway and leave the text on the clipboard, so nothing is lost.
enum TextInserter {
    /// How long to wait after ⌘V before restoring the old clipboard. The
    /// target app reads the pasteboard asynchronously; Electron / Chromium
    /// apps can take a few hundred ms.
    private static let restoreDelay: TimeInterval = 0.6

    enum Result {
        /// A text field was focused and the words went in.
        case pasted
        /// Pasted, but the app couldn't say whether a field was focused. The words stay on the clipboard.
        case unsure
        /// Nowhere to type (no permission, or no text field focused). The words are on the clipboard.
        case nowhere
    }

    /// Pastes `text` where the cursor is. On `.nowhere` the caller shows the text to drag in or copy;
    /// on `.unsure` it shows it briefly, in case it didn't land.
    @MainActor
    @discardableResult
    static func insert(_ text: String) -> Result {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .nowhere }

        let pasteboard = NSPasteboard.general

        let target = isTrusted(prompt: false) ? focusedTarget() : .notText
        guard target != .notText else {
            // Fallback: text stays on the clipboard too, nothing to restore.
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("[TextInserter] Nowhere to paste, text left on clipboard")
            return .nowhere
        }

        // Snapshot existing pasteboard contents so we can restore.
        let savedItems: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChange = pasteboard.changeCount
        // Unsure the paste will land: leave the words on the clipboard.
        let restore = target == .text

        // Short delay so the pasteboard write lands before the target reads it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            simulatePaste()
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                // Only restore if nobody else wrote to the clipboard meanwhile.
                guard restore, pasteboard.changeCount == ourChange else { return }
                pasteboard.clearContents()
                guard !savedItems.isEmpty else { return }
                let items: [NSPasteboardItem] = savedItems.map { itemDict in
                    let item = NSPasteboardItem()
                    for (type, data) in itemDict { item.setData(data, forType: type) }
                    return item
                }
                pasteboard.writeObjects(items)
            }
        }
        return target == .text ? .pasted : .unsure
    }

    enum Target { case text, notText, unknown }

    /// Is something focused that takes text? Checked through Accessibility on the
    /// frontmost app (the system-wide lookup misses focus in several apps): a text
    /// role, an editable element, or anything exposing a text selection. A
    /// definite non-text element, or no focus in a plain native app, is `.notText`.
    /// Apps that don't expose their fields to Accessibility are `.unknown`.
    static func focusedTarget() -> Target {
        let app = NSWorkspace.shared.frontmostApplication
        let opaque = app.map(exposesFieldsPoorly) ?? false
        var focused: CFTypeRef?
        var err = AXError.cannotComplete
        if let app {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            // Chromium and Electron only build their accessibility tree when asked.
            if opaque { AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue) }
            err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        }
        if err != .success {
            err = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
        }
        guard err == .success, let el = focused else {
            return opaque || err != .noValue ? .unknown : .notText
        }
        let element = el as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        if let r = role as? String, textRoles.contains(r) { return .text }
        var editable: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editable) == .success, (editable as? Bool) == true { return .text }
        // The page itself has focus, not a field on it: nothing to type into. (A web page answers
        // "selected text range" too, so this has to come before that check.) Chromium and Electron
        // may not have built their tree yet, so there it proves nothing.
        if (role as? String) == "AXWebArea" { return opaque ? .unknown : .notText }
        var range: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success { return .text }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        if settable.boolValue { return .text }
        // Something is focused and it isn't a field. In an app that hides its
        // fields from Accessibility that proves nothing.
        return opaque ? .unknown : .notText
    }

    /// Browsers, Electron apps, terminals and chat/code apps draw their own text
    /// areas, so Accessibility often can't see the field.
    private static func exposesFieldsPoorly(_ app: NSRunningApplication) -> Bool {
        let id = app.bundleIdentifier ?? ""
        if TextFormatter.codeApps.contains(id) || TextFormatter.casualApps.contains(id) { return true }
        let browsers = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser", "org.mozilla", "com.operasoftware", "com.vivaldi"]
        if browsers.contains(where: id.hasPrefix) { return true }
        if let url = app.bundleURL,
           FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) { return true }
        return false
    }

    /// AXIsProcessTrusted, optionally showing the system "grant access" prompt.
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        // Flags are set explicitly, so a physically-held ⌥ doesn't leak in.
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        print("[TextInserter] Cmd+V posted")
    }
}
