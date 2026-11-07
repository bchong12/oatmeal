import SwiftUI
import AVFoundation
import ApplicationServices
import EventKit
import Security

// MARK: - Permissions

/// What macOS currently allows Oatmeal, re-read every second while Settings is open so a switch
/// flipped in System Settings shows up straight away.
@MainActor
final class PermissionsMonitor: ObservableObject {
    @Published private(set) var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var calendar = EKEventStore.authorizationStatus(for: .event)
    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in PermissionsMonitor.live?.refresh() }
        }
        Self.live = self
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if Self.live === self { Self.live = nil }
    }

    private static weak var live: PermissionsMonitor?

    func refresh() {
        let m = AVCaptureDevice.authorizationStatus(for: .audio), ax = AXIsProcessTrusted()
        let cal = EKEventStore.authorizationStatus(for: .event)
        if m != mic || ax != accessibility { AppModel.shared.refreshPermissions() }   // keeps the bell honest
        if cal != calendar { CalendarStore.shared.refreshAuth() }
        mic = m; accessibility = ax; calendar = cal
    }

    func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in PermissionsMonitor.live?.refresh(); AppModel.shared.refreshPermissions() }
        }
    }

    /// Debug builds are signed ad hoc, so every rebuild looks like a new app to macOS and loses its permissions.
    static let isAdHocSigned: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let adHoc: UInt32 = 0x0002   // kSecCodeSignatureAdhoc
        return dict[kSecCodeInfoTeamIdentifier as String] == nil || flags & adHoc != 0
    }()

    static func openPrivacyPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

enum PermissionState: Equatable {
    case allowed, notAsked, denied
    /// macOS has no way to check it ahead of time.
    case askedOnUse(String)
}

extension PermissionState {
    init(_ s: AVAuthorizationStatus) {
        switch s {
        case .authorized: self = .allowed
        case .notDetermined: self = .notAsked
        default: self = .denied
        }
    }
    init(_ s: EKAuthorizationStatus) {
        switch s {
        case .fullAccess: self = .allowed
        case .notDetermined: self = .notAsked
        default: self = .denied   // denied, restricted and write-only all mean Oatmeal can't read events
        }
    }
}

/// One permission: what it's for, where it stands, and the one action that fixes it.
struct PermissionRow: View {
    let icon: String
    let title: String
    let sub: String
    let state: PermissionState
    let pane: String
    var request: (() -> Void)?

    var body: some View {
        SettingsRow(icon: icon, title: title, sub: sub) {
            switch state {
            case .allowed:
                Label("Allowed", systemImage: "checkmark.circle.fill").font(DF.font(12, .semibold)).foregroundStyle(DF.thrivingInk)
            case .notAsked:
                SecondaryButton(title: "Allow") { request?() ?? PermissionsMonitor.openPrivacyPane(pane) }
            case .denied:
                HStack(spacing: 10) {
                    Label("Off", systemImage: "xmark.circle.fill").font(DF.font(12, .semibold)).foregroundStyle(DF.tiredInk)
                    SecondaryButton(title: "Open Settings") { PermissionsMonitor.openPrivacyPane(pane) }
                }
            case .askedOnUse(let note):
                HStack(spacing: 10) {
                    Text(note).font(DF.font(12)).foregroundStyle(DF.muted)
                    SecondaryButton(title: "Open Settings") { PermissionsMonitor.openPrivacyPane(pane) }
                }
            }
        }
    }
}

/// Settings › General › Permissions.
struct PermissionsCard: View {
    @StateObject private var perms = PermissionsMonitor()

    var body: some View {
        VStack(spacing: 0) {
            PermissionRow(icon: "mic", title: "Microphone", sub: "Dictation, and your side of meetings",
                          state: PermissionState(perms.mic), pane: "Privacy_Microphone") { perms.requestMic() }
            PermissionRow(icon: "speaker.wave.2", title: "System audio", sub: "The other side of calls in meeting notes",
                          state: .askedOnUse("Asked when you first record"), pane: "Privacy_ScreenCapture")
            PermissionRow(icon: "keyboard", title: "Accessibility", sub: "Right ⌥, and typing into other apps",
                          state: perms.accessibility ? .allowed : .denied, pane: "Privacy_Accessibility") { AppModel.shared.requestAccessibility() }
            PermissionRow(icon: "calendar", title: "Calendar", sub: "Meetings on Today and Week, reminders",
                          state: PermissionState(perms.calendar), pane: "Privacy_Calendars") { Task { await CalendarStore.shared.requestAccess() } }
            SettingsRow(icon: "arrow.counterclockwise", title: "Reset permissions", sub: "If right ⌥ or dictation stops working", last: !PermissionsMonitor.isAdHocSigned) {
                SecondaryButton(title: "Reset…") { AppModel.shared.resetPermissions() }
            }
            if PermissionsMonitor.isAdHocSigned {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DF.okayInk)
                    Text("This is an unsigned development build. macOS forgets Oatmeal\u{2019}s permissions every time it\u{2019}s rebuilt, so you may need to allow them again.")
                        .font(DF.font(12)).foregroundStyle(DF.muted).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .dfCard()
        .onAppear { perms.start() }
        .onDisappear { perms.stop() }
    }
}

// MARK: - Audio tab

/// Settings › Audio: which mic Oatmeal listens with, a live level to check it hears you, and how call audio is captured.
struct AudioSettingsTab: View {
    @ObservedObject private var inputs = AudioInputs.shared

    private var micOptions: [(String?, String)] {
        var out: [(String?, String)] = [(nil, "System default (\(inputs.defaultName))")]
        if inputs.selectedMissing, let uid = inputs.selectedUID { out.append((uid, "Not connected")) }
        out += inputs.devices.map { (Optional($0.id), $0.name) }
        return out
    }
    @StateObject private var meter = MicLevelMeter()
    @StateObject private var perms = PermissionsMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("MICROPHONE").font(DF.font(12, .bold)).tracking(1).foregroundStyle(DF.faint).padding(.top, 4)
            VStack(spacing: 0) {
                SettingsRow(icon: "mic", title: "Input", sub: inputs.selectedMissing
                            ? "Your chosen mic isn\u{2019}t connected, so Oatmeal is using \(inputs.defaultName)"
                            : "Used for dictation and your side of meetings") {
                    DFSelect(options: micOptions, selection: $inputs.selectedUID, width: 260)
                }
                SettingsRow(icon: "waveform", title: "Level", sub: levelSub, last: true) {
                    if perms.mic == .authorized {
                        LevelBars(level: meter.level).frame(width: 160, height: 18)
                    } else {
                        PermissionRow(icon: "", title: "", sub: "", state: PermissionState(perms.mic), pane: "Privacy_Microphone") { perms.requestMic() }
                            .fixedSize()
                    }
                }
            }
            .dfCard()

            Text("CALL AUDIO").font(DF.font(12, .bold)).tracking(1).foregroundStyle(DF.faint).padding(.top, 4)
            VStack(spacing: 0) {
                SettingsRow(icon: "speaker.wave.2", title: "The other side of calls",
                            sub: "Meeting notes also record what plays through your speakers or headphones (Zoom, Meet, Teams). macOS asks for System Audio Recording the first time.", last: true) {
                    SecondaryButton(title: "Open Settings") { PermissionsMonitor.openPrivacyPane("Privacy_ScreenCapture") }
                }
            }
            .dfCard()
        }
        .onAppear { perms.start(); meter.start() }
        .onDisappear { meter.stop(); perms.stop() }
        .onChange(of: inputs.selectedUID) { _, _ in meter.start() }
        .onChange(of: perms.mic) { _, s in if s == .authorized { meter.start() } }
    }

    private var levelSub: String {
        if let p = meter.problem { return p }
        switch perms.mic {
        case .authorized: return "Say something: the bars should move. Listening with \(inputs.activeName)"
        case .notDetermined: return "Allow the microphone to test it"
        default: return "Microphone access is off, so Oatmeal can\u{2019}t hear you"
        }
    }
}

struct LevelBars: View {
    let level: Float
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                let on = Float(i) / 16 < level
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(on ? (i > 12 ? DF.okayInk : DF.thrivingInk) : DF.line)
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }
}

/// A Settings row: icon, title and description on the left, a control on the right.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    let sub: String
    var last = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            if !icon.isEmpty {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(DF.muted)
                    .frame(width: 30, height: 30).background(DF.wash, in: RoundedRectangle(cornerRadius: 8))
            }
            if !title.isEmpty || !sub.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DF.font(14, .semibold))
                    Text(sub).font(DF.font(13)).foregroundStyle(DF.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
            }
            trailing()
        }
        .padding(.horizontal, title.isEmpty ? 0 : 20).padding(.vertical, title.isEmpty ? 0 : 14)
        .overlay(alignment: .bottom) { if !last && !title.isEmpty { Divider().overlay(DF.line).padding(.horizontal, 20) } }
    }
}
