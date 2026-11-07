import SwiftUI
import SwiftData

struct DictationView: View {
    @EnvironmentObject var model: AppModel
    @Query(sort: \DictationEntry.createdAt, order: .reverse) private var entries: [DictationEntry]
    @ObservedObject private var dictation = DictationService.shared
    @State private var query = ""

    private var filtered: [DictationEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? entries : entries.filter { $0.text.lowercased().contains(q) || $0.appName.lowercased().contains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Flow") {
                    ModelBadge(state: dictation.modelState)
                }
                if entries.isEmpty {
                    EmptyState(title: "Nothing dictated yet",
                               message: "Hold right ⌥, talk, let go. The words land wherever your cursor is. Double-tap right ⌥ to keep listening hands-free.")
                } else {
                    StatsRow(entries: entries).padding(.horizontal, 28).padding(.bottom, 18)
                    HStack {
                        Text(query.isEmpty ? "History" : "\(filtered.count) found").font(DF.font(12, .semibold)).foregroundStyle(DF.faint)
                        Spacer()
                        SearchField(text: $query, prompt: "Search what you\u{2019}ve said").frame(width: 260)
                    }
                    .padding(.horizontal, 28).padding(.bottom, 8)
                    Rectangle().fill(DF.line).frame(height: 1).padding(.horizontal, 16)
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { e in EntryRow(entry: e) }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(DF.paper)
        }
    }
}

private struct StatsRow: View {
    let entries: [DictationEntry]
    var body: some View {
        let weekStart = Calendar.oatmeal.dateInterval(of: .weekOfYear, for: Date())!.start
        let week = entries.filter { $0.createdAt >= weekStart }
        let words = week.reduce(0) { $0 + $1.wordCount }
        let secs = entries.filter { $0.seconds > 1 }.reduce(0.0) { $0 + $1.seconds }
        let allWords = entries.filter { $0.seconds > 1 }.reduce(0) { $0 + $1.wordCount }
        let wpm = secs > 0 ? Int(Double(allWords) / (secs / 60)) : 0
        let top = Dictionary(grouping: entries.filter { !$0.appName.isEmpty }, by: \.appName)
            .map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }.first?.0 ?? "—"
        HStack(spacing: 0) {
            stat("\(words)", "words this week")
            divider
            stat(wpm > 0 ? "\(wpm)" : "—", "words per minute")
            divider
            stat("\(Int(Double(words) / 40))m", "typing saved")
            divider
            stat(top, "used most in")
        }
        .padding(.vertical, 14)
        .background(DF.canvas, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DF.line))
    }
    private var divider: some View { Rectangle().fill(DF.line).frame(width: 1, height: 36) }
    private func stat(_ n: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(DF.serif(24)).lineLimit(1)
            Text(l).font(DF.font(12)).foregroundStyle(DF.muted)
        }
        .padding(.horizontal, 18).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EntryRow: View {
    let entry: DictationEntry
    @EnvironmentObject var model: AppModel
    @State private var hover = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconView(name: entry.appName, isTask: entry.destination == "task")
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text).font(DF.font(14)).foregroundStyle(DF.ink).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text([entry.appName.isEmpty ? nil : entry.appName, entry.createdAt.formatted(.relative(presentation: .named)), "\(entry.wordCount) words"]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(DF.font(12)).foregroundStyle(DF.muted)
            }
            Spacer(minLength: 8)
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string) } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.df(.ghost, height: 26))
            .opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 14)
        .background(hover ? DF.canvas : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) { Rectangle().fill(DF.line.opacity(0.6)).frame(height: 1).padding(.horizontal, 12) }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .dfContextMenu {
            [.action("Copy", icon: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string) },
             .divider,
             .action("Delete", icon: "trash", destructive: true) { model.context.delete(entry) }]
        }
    }
}

/// The app a dictation went into, by name.
struct AppIconView: View {
    let name: String
    var isTask = false
    var body: some View {
        Group {
            if isTask {
                Image(systemName: "checklist").font(.system(size: 13)).foregroundStyle(DF.muted)
                    .frame(width: 28, height: 28).background(DF.wash, in: RoundedRectangle(cornerRadius: 7))
            } else if let icon = Self.icon(for: name) {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            } else {
                Image(systemName: "text.cursor").font(.system(size: 13)).foregroundStyle(DF.muted)
                    .frame(width: 28, height: 28).background(DF.wash, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
    private static var cache: [String: NSImage] = [:]
    static func icon(for name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        if let c = cache[name] { return c }
        let ws = NSWorkspace.shared
        let url = ws.runningApplications.first { $0.localizedName == name }?.bundleURL
            ?? ["/Applications/\(name).app", "/System/Applications/\(name).app", "/System/Applications/Utilities/\(name).app"]
                .map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url else { return nil }
        let img = ws.icon(forFile: url.path)
        cache[name] = img
        return img
    }
}

/// Wispr-style clean-up switches, your dictionary and snippets.
struct VoiceSettingsPanel: View {
    @ObservedObject private var v = VoiceSettings.shared
    @State private var newHeard = ""
    @State private var newWritten = ""
    @State private var newCue = ""
    @State private var newText = ""

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 22) {
                Text("CLEAN-UP").font(DF.font(12, .bold)).tracking(1).foregroundStyle(DF.faint)
                VStack(spacing: 0) {
                    toggle("Remove um, uh", "Filler sounds disappear", $v.removeFillers)
                    toggle("Backtrack", "\u{201C}at 2, actually 3\u{201D} → \u{201C}at 3\u{201D}; \u{201C}scratch that\u{201D}", $v.backtrack)
                    toggle("Spoken punctuation", "\u{201C}comma\u{201D}, \u{201C}new line\u{201D}, \u{201C}question mark\u{201D}", $v.spokenPunctuation)
                    toggle("Numbered lists", "\u{201C}first… second…\u{201D} becomes 1. 2.", $v.lists)
                    toggle("Style per app", "Casual in Messages and Slack", $v.appStyles)
                    toggle("Code aware", "\u{201C}camel case user name\u{201D} → userName", $v.codeAware)
                    toggle("Sounds", "A soft tick on start and stop", $v.sounds, last: true)
                }
                .dfCard()

                section("Dictionary", "How words should be written") {
                    ForEach(v.words) { w in
                        HStack(spacing: 8) {
                            Text(w.heard).font(DF.font(13)).foregroundStyle(DF.muted).lineLimit(1)
                            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(DF.faint)
                            Text(w.written).font(DF.font(13, .semibold)).lineLimit(1)
                            Spacer()
                            remove { v.words.removeAll { $0.id == w.id } }
                        }
                        .padding(.vertical, 5)
                    }
                    HStack(spacing: 6) {
                        field("heard", $newHeard)
                        field("written", $newWritten)
                        add(disabled: newHeard.isEmpty || newWritten.isEmpty) {
                            v.words.insert(DictionaryWord(heard: newHeard.lowercased(), written: newWritten), at: 0)
                            newHeard = ""; newWritten = ""
                        }
                    }
                }

                section("Snippets", "Say the cue, get the text") {
                    if v.snippets.isEmpty {
                        Text("e.g. \u{201C}my calendar link\u{201D} → your booking URL").font(DF.font(12)).foregroundStyle(DF.faint)
                    }
                    ForEach(v.snippets) { sn in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\u{201C}\(sn.cue)\u{201D}").font(DF.font(13, .semibold))
                                Text(sn.text).font(DF.font(12)).foregroundStyle(DF.muted).lineLimit(2)
                            }
                            Spacer()
                            remove { v.snippets.removeAll { $0.id == sn.id } }
                        }
                        .padding(.vertical, 5)
                    }
                    field("cue, e.g. my calendar link", $newCue)
                    HStack(spacing: 6) {
                        field("text it becomes", $newText)
                        add(disabled: newCue.isEmpty || newText.isEmpty) {
                            v.snippets.append(Snippet(cue: newCue.lowercased(), text: newText)); newCue = ""; newText = ""
                        }
                    }
                }

                Color.clear.frame(height: 8)
                .padding(.bottom, 24)
            }
        }
    }

    private func toggle(_ t: String, _ sub: String, _ b: Binding<Bool>, last: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(DF.font(13, .semibold)).foregroundStyle(DF.ink)
                Text(sub).font(DF.font(11)).foregroundStyle(DF.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: b).toggleStyle(.df)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(DF.line).padding(.horizontal, 12) } }
    }

    private func section<C: View>(_ t: String, _ sub: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(DF.font(14, .bold))
                Text(sub).font(DF.font(12)).foregroundStyle(DF.muted)
            }
            c()
        }
    }

    private func field(_ p: String, _ b: Binding<String>) -> some View {
        TextField(p, text: b).textFieldStyle(.plain).font(DF.font(13))
            .padding(.horizontal, 8).frame(height: 28)
            .background(DF.wash, in: RoundedRectangle(cornerRadius: 7))
    }

    private func add(disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(DF.ink.opacity(disabled ? 0.3 : 1), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).disabled(disabled)
    }

    private func remove(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(DF.faint) }
            .buttonStyle(.plain)
    }

    private func shortcut(_ k: String, _ what: String) -> some View {
        HStack {
            Text(k).font(DF.font(12, .semibold)).padding(.horizontal, 6).frame(height: 22)
                .background(DF.wash, in: RoundedRectangle(cornerRadius: 6))
            Spacer()
            Text(what).font(DF.font(12)).foregroundStyle(DF.muted)
        }
    }
}
