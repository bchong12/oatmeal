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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(DF.serif(32)).tracking(-0.6)
                DFTabs(items: SettingsTab.allCases.map { ($0, $0.rawValue) }, selection: $tab, spacing: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(DF.line).frame(height: 1) }
            }
            .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 22)
            .frame(maxWidth: 728, alignment: .leading).frame(maxWidth: .infinity)

            ScrollView {
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
                .padding(.horizontal, 28).padding(.bottom, 28)
                .frame(maxWidth: 728, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
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
        Text(t).font(DF.font(12, .bold)).tracking(1).foregroundStyle(DF.faint).padding(.top, 4)
    }

    @ViewBuilder private var general: some View {
        NotesWriterCard()
        header("THE PILL")
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
        header("PERMISSIONS")
        PermissionsCard()
    }

    @ViewBuilder private var models: some View {
        header("SPEECH TO TEXT")
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
                        .padding(.horizontal, 20).padding(.bottom, 16)
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
        .padding(20)
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
                Text(title).font(DF.font(14, .semibold))
                Text(sub).font(DF.font(13)).foregroundStyle(DF.muted)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(DF.line).frame(height: 1).padding(.horizontal, 20) } }
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
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(DF.line).padding(.horizontal, 20) } }
    }
}
