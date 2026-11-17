import SwiftUI
import AVFoundation
import ApplicationServices

struct SettingsView: View {
    @EnvironmentObject var calendars: CalendarStore
    @AppStorage("pillVisible") private var pillVisible = true
    @AppStorage("meetingPrompt") private var meetingPrompt = true
    @ObservedObject private var dictation = DictationService.shared

    @EnvironmentObject var model: AppModel
    @State private var tab: SettingsTab = .general
    @State private var modelSize: Int64 = SpeechEngine.modelSizeOnDisk

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General", dictation = "Dictation", audio = "Audio", models = "Models", calendars = "Calendars", shortcuts = "Shortcuts", mcp = "MCP"
        var id: String { rawValue }
        var title: String { self == .mcp ? "Connect your AI" : rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"; case .dictation: "waveform"; case .audio: "speaker.wave.2"; case .models: "cpu"
            case .calendars: "calendar"; case .shortcuts: "command"; case .mcp: "point.3.connected.trianglepath.dotted"
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(SettingsTab.allCases) { t in
                    SettingsNavItem(title: t.title, symbol: t.symbol, on: tab == t) {
                        withAnimation(.snappy(duration: 0.18)) { tab = t }
                    }
                }
            }
            .frame(width: 176, alignment: .leading)
            .padding(.top, 40)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tab.title).font(DF.font(32, .bold)).tracking(-0.6)
                        .padding(.bottom, 22)
                    VStack(alignment: .leading, spacing: 18) {
                        switch tab {
                        case .general: general
                        case .dictation: VoiceSettingsPanel()
                        case .audio: AudioSettingsTab()
                        case .models: models
                        case .calendars: calendarsTab
                        case .shortcuts: shortcuts
                        case .mcp: MCPSettingsTab()
                        }
                    }
                }
                .padding(.leading, 48).padding(.top, 36).padding(.bottom, 48)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(tab)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 1000, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DF.paper)
        .font(DF.font(14))
        .onAppear {
            calendars.refreshAuth(); modelSize = SpeechEngine.modelSizeOnDisk
            tab = SettingsTab(rawValue: model.settingsTab) ?? .general
        }
        .onChange(of: model.settingsTab) { _, t in tab = SettingsTab(rawValue: t) ?? tab }
    }

    private func header(_ t: String) -> some View {
        Text(t).font(DF.font(17, .semibold)).padding(.top, 12)
    }

    @ViewBuilder private var general: some View {
        AccountCard()
        NotesWriterCard()
        header("The pill")
        VStack(spacing: 0) {
            row("Show the pill", "Appears at the bottom of the screen while you dictate or record") {
                Toggle("", isOn: $pillVisible).toggleStyle(.df)
                    .onChange(of: pillVisible) { _, v in PillController.shared.setVisible(v) }
            }
            row("Offer to record meetings", "When a call starts in Zoom, Teams, FaceTime or a browser", last: true) {
                Toggle("", isOn: $meetingPrompt).toggleStyle(.df)
            }
        }
        .dfCard()
        header("Permissions")
        PermissionsCard()
    }

    @ViewBuilder private var models: some View {
        header("Speech to text")
        SpeechModelsCard()
    }

    @ViewBuilder private var shortcuts: some View {
        VStack(spacing: 0) {
            ShortcutRow(keys: ["Hold right ⌥"], what: "Dictate into the app you\u{2019}re in")
            ShortcutRow(keys: ["Double-tap right ⌥"], what: "Hands-free until you tap again")
            ShortcutRow(keys: ["Right ⌥", "V"], what: "Paste your last dictation again")
            ShortcutRow(keys: ["Right ⌥", "M"], what: "Start or stop meeting notes")
            ShortcutRow(keys: ["Tap right ⌥"], what: "Open or hide Oatmeal")
            ShortcutRow(keys: ["Esc"], what: "Cancel while listening")
            ShortcutRow(keys: ["⌘", "N"], what: "Record a meeting")
            ShortcutRow(keys: ["⌘", "1–2"], what: "Notes, Flow")
            ShortcutRow(keys: ["⌃", "⌘", "S"], what: "Hide or show the sidebar")
            ShortcutRow(keys: ["⌘", ","], what: "Settings", last: true)
        }
        .dfCard()
    }

    @ViewBuilder private var calendarsTab: some View {
                VStack(spacing: 0) {
                    provider("apple-calendar", "Apple Calendar", calendars.authorized ? "Connected · iCloud and every account on this Mac" : "Mac app · brings in iCloud and every account on this Mac") {
                        if calendars.authorized {
                            Text("Live").font(DF.font(12, .semibold)).foregroundStyle(DF.thrivingInk)
                                .padding(.horizontal, 10).frame(height: 26).background(DF.thrivingBg, in: Capsule())
                        } else {
                            PrimaryButton(title: "Allow access", symbol: "lock.open") { Task { await calendars.requestAccess() } }
                        }
                    }
                    if calendars.authorized {
                        VStack(spacing: 0) {
                            ForEach(calendars.calendars, id: \.calendarIdentifier) { c in
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: CalendarStore.hex(c.cgColor))).frame(width: 10, height: 10)
                                    Text(c.title).font(DF.font(14))
                                    Text(CalendarStore.sourceName(c.source)).font(DF.font(12)).foregroundStyle(DF.faint)
                                    Spacer()
                                    Toggle("", isOn: Binding(get: { !calendars.hiddenCalendarIDs.contains(c.calendarIdentifier) },
                                                             set: { on in if on { calendars.hiddenCalendarIDs.remove(c.calendarIdentifier) } else { calendars.hiddenCalendarIDs.insert(c.calendarIdentifier) } }))
                                        .toggleStyle(.df)
                                }
                                .padding(.vertical, 7)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(Color(hex: 0xFAFAFB), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DF.line))
                        .padding(.bottom, 16)
                    }
                    Divider().overlay(DF.line)
                    provider("outlook", "Outlook", "Add your work account in System Settings › Internet Accounts") {
                        SecondaryButton(title: "Open") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
                        }
                    }
                }
                .dfCard()
    }

    private func provider<A: View>(_ logo: String, _ name: String, _ sub: String, @ViewBuilder _ action: () -> A) -> some View {
        HStack(spacing: 14) {
            if let url = Bundle.main.url(forResource: logo, withExtension: "png", subdirectory: "Brand"), let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name).font(DF.font(15, .bold))
                    Text("Free").font(DF.font(11, .bold)).foregroundStyle(DF.muted).padding(.horizontal, 7).frame(height: 20).background(DF.wash, in: Capsule())
                }
                Text(sub).font(DF.font(13)).foregroundStyle(DF.muted)
            }
            Spacer()
            action()
        }
        .padding(.vertical, 16)
    }

    private func how(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).frame(width: 26, height: 26)
                .background(DF.paper, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DF.line))
            Text(text).font(DF.font(13))
        }
    }

    private func row<A: View>(_ title: String, _ sub: String, last: Bool = false, @ViewBuilder _ trailing: () -> A) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DF.font(15, .medium))
                Text(sub).font(DF.font(13)).foregroundStyle(DF.muted)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(DF.line).frame(height: 1) } }
    }
}

private struct ShortcutRow: View {
    let keys: [String]
    let what: String
    var last = false
    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { k in
                Text(k).font(DF.font(12, .semibold)).foregroundStyle(DF.ink)
                    .padding(.horizontal, 7).frame(height: 24)
                    .background(DF.wash, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DF.line))
            }
            Spacer(minLength: 12)
            Text(what).font(DF.font(13)).foregroundStyle(DF.muted).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(DF.line) } }
    }
}

/// An item in Settings' side list.
private struct SettingsNavItem: View {
    let title: String
    let symbol: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12.5)).frame(width: 18).foregroundStyle(on ? DF.ink : DF.muted)
                Text(title).font(DF.font(15, .medium)).foregroundStyle(on ? DF.ink : Color(hex: 0x5F5E5B)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.black.opacity(0.05) : hover ? Color.black.opacity(0.03) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// A titled group of plain settings rows.
struct SettingsSection<C: View>: View {
    let title: String
    @ViewBuilder var content: C
    init(_ title: String, @ViewBuilder content: () -> C) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(DF.font(17, .semibold)).padding(.top, 22).padding(.bottom, 8)
            Hairline()
            content
        }
    }
}

/// Title and a line under it on the left, a control on the right, a hairline below.
struct PlainRow<T: View>: View {
    let title: String
    let sub: String
    @ViewBuilder var trailing: T
    init(_ title: String, _ sub: String, @ViewBuilder trailing: () -> T) { self.title = title; self.sub = sub; self.trailing = trailing() }
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DF.font(15, .medium))
                Text(sub).font(DF.font(13)).foregroundStyle(DF.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
