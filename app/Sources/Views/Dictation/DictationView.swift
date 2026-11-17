import SwiftUI
import SwiftData

struct DictationView: View {
    @EnvironmentObject var model: AppModel
    @Query(sort: \DictationEntry.createdAt, order: .reverse) private var entries: [DictationEntry]
    @ObservedObject private var dictation = DictationService.shared
    @State private var query = ""
    @State private var tab: FlowTab = .history

    enum FlowTab: Hashable { case history, dictionary, snippets }

    private var filtered: [DictationEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? entries : entries.filter { $0.text.lowercased().contains(q) || $0.appName.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                NotionHeader(icon: .face("face-h"), title: "Flow",
                             description: "Hold right \u{2325} and talk. The words land wherever your cursor is.") {
                    EmptyView()
                } below: {
                    ModelChip(state: dictation.modelState).padding(.top, 12)
                }

                if !entries.isEmpty {
                    FlowStats(entries: entries).padding(.top, 28).padding(.bottom, 22)
                    Hairline()
                } else {
                    Hairline().padding(.top, 24)
                }

                HStack(spacing: 8) {
                    ViewTabs(items: [(FlowTab.history, "History", "clock"), (.dictionary, "Dictionary", "character.book.closed"), (.snippets, "Snippets", "text.badge.plus")],
                             selection: $tab)
                    Spacer(minLength: 8)
                    if tab == .history && !entries.isEmpty {
                        SearchField(text: $query, prompt: "Search what you\u{2019}ve said").frame(width: 240)
                    }
                }
                .padding(.top, 12).padding(.bottom, 4)

                switch tab {
                case .history: history
                case .dictionary: DictionaryList().padding(.top, 12)
                case .snippets: SnippetsList().padding(.top, 12)
                }
            }
            .pageColumn()
            .padding(.top, 36).padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DF.paper)
    }

    @ViewBuilder private var history: some View {
        if entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing dictated yet").font(DF.font(16, .semibold))
                Text("Hold right \u{2325}, talk, let go. Double-tap right \u{2325} to keep listening hands-free.")
                    .font(DF.font(15)).foregroundStyle(DF.muted)
            }
            .padding(.top, 28)
        } else if filtered.isEmpty {
            Text("Nothing matches \u{201C}\(query)\u{201D}").font(DF.font(15)).foregroundStyle(DF.muted).padding(.top, 28)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Self.days(filtered), id: \.day) { group in
                    DayHeader(day: group.day, entries: group.entries)
                    ForEach(group.entries) { e in EntryRow(entry: e) }
                }
            }
        }
    }

    static func days(_ list: [DictationEntry]) -> [(day: Date, entries: [DictationEntry])] {
        let cal = Calendar.current
        var out: [(day: Date, entries: [DictationEntry])] = []
        for e in list {
            let d = cal.startOfDay(for: e.createdAt)
            if out.last?.day == d { out[out.count - 1].entries.append(e) } else { out.append((d, [e])) }
        }
        return out
    }
}

/// "Today  4 dictations · 276 words"
private struct DayHeader: View {
    let day: Date
    let entries: [DictationEntry]
    var body: some View {
        let words = entries.reduce(0) { $0 + $1.wordCount }
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.title(day)).font(DF.font(15, .semibold))
            Text("\(entries.count) \(entries.count == 1 ? "dictation" : "dictations") \u{00B7} \(words) words")
                .font(DF.font(13)).foregroundStyle(DF.faint)
        }
        .padding(.top, 22).padding(.bottom, 4)
    }
    static func title(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return cal.isDate(d, equalTo: Date(), toGranularity: .year)
            ? d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            : d.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// The speech model under Flow's title.
private struct ModelChip: View {
    let state: VoiceModelState
    var body: some View {
        let name = SpeechModel.selected.name.replacingOccurrences(of: " TDT 0.6B", with: "")
        switch state {
        case .ready: InfoChip(text: "\(name) \u{00B7} on this Mac", dot: DF.thrivingInk)
        case .downloading(let p): InfoChip(text: "Downloading \(name) \(Int(p * 100))%", dot: DF.okayInk)
        case .notLoaded: InfoChip(text: "\(name) \u{00B7} loads on first use")
        case .failed: InfoChip(text: "\(name) didn\u{2019}t load", dot: DF.now)
        }
    }
}

/// Four numbers straight on the page.
private struct FlowStats: View {
    let entries: [DictationEntry]
    var body: some View {
        let weekStart = Calendar.oatmeal.dateInterval(of: .weekOfYear, for: Date())!.start
        let week = entries.filter { $0.createdAt >= weekStart }
        let words = week.reduce(0) { $0 + $1.wordCount }
        let secs = entries.filter { $0.seconds > 1 }.reduce(0.0) { $0 + $1.seconds }
        let allWords = entries.filter { $0.seconds > 1 }.reduce(0) { $0 + $1.wordCount }
        let wpm = secs > 0 ? Int(Double(allWords) / (secs / 60)) : 0
        let top = Dictionary(grouping: week.filter { !$0.appName.isEmpty }, by: \.appName)
            .map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }.first?.0 ?? "\u{2014}"
        HStack(alignment: .top, spacing: 24) {
            stat(words.formatted(), "words this week")
            stat(wpm > 0 ? "\(wpm)" : "\u{2014}", "words a minute")
            stat("\(Int(Double(words) / 40)) min", "of typing saved")
            stat(top, "where you talk most")
        }
    }
    private func stat(_ n: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(n).font(DF.font(28, .semibold)).tracking(-0.5).lineLimit(1).minimumScaleFactor(0.7)
            Text(l).font(DF.font(13)).foregroundStyle(DF.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EntryRow: View {
    let entry: DictationEntry
    @EnvironmentObject var model: AppModel
    @State private var hover = false
    @State private var copied = false
    @State private var moreFrame: CGRect = .zero

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconView(name: entry.appName, isTask: entry.destination == "task", size: 22).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text).font(DF.font(16)).foregroundStyle(DF.ink).textSelection(.enabled)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                Text([entry.destination == "task" ? "Saved as a task" : entry.appName.isEmpty ? nil : entry.appName, "\(entry.wordCount) words"]
                        .compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(DF.font(13)).foregroundStyle(DF.muted)
            }
            Spacer(minLength: 8)
            ZStack(alignment: .topTrailing) {
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened)).font(DF.font(13)).foregroundStyle(DF.faint)
                    .monospacedDigit().padding(.top, 2).opacity(hover ? 0 : 1)
                HStack(spacing: 2) {
                    Button { copy() } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(.dfIcon(size: 26)).help("Copy")
                    Button {
                        Popups.shared.showMenu(menu, below: moreFrame, width: 180)
                    } label: { Image(systemName: "ellipsis") }
                        .buttonStyle(.dfIcon(size: 26)).popupAnchor($moreFrame).help("More")
                }
                .opacity(hover ? 1 : 0)
            }
            .frame(width: 64, alignment: .topTrailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(hover ? DF.canvas : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .padding(.horizontal, -10)
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
        .dfContextMenu { menu }
    }

    private var menu: [DFMenuItem] {
        [.action("Copy", icon: "doc.on.doc") { copy() },
         .divider,
         .action("Delete", icon: "trash", destructive: true) { model.context.delete(entry) }]
    }

    private func copy() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string)
        withAnimation(.snappy) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(.snappy) { copied = false } }
    }
}

// MARK: - Dictionary and snippets (Flow's other two tabs)

/// How words should be written: "heard" → "written", with a row to add one.
struct DictionaryList: View {
    @ObservedObject private var v = VoiceSettings.shared
    @State private var heard = ""
    @State private var written = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Words Oatmeal hears wrong, and how they should be written.").font(DF.font(15)).foregroundStyle(DF.muted)
                .padding(.bottom, 14)
            HStack(spacing: 8) {
                PlainField(prompt: "Heard, e.g. oat meal", text: $heard)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(DF.faint)
                PlainField(prompt: "Written, e.g. Oatmeal", text: $written)
                Button("Add") {
                    v.words.insert(DictionaryWord(heard: heard.lowercased(), written: written), at: 0)
                    heard = ""; written = ""
                }
                .buttonStyle(.df(.primary, height: 30)).disabled(heard.isEmpty || written.isEmpty)
            }
            .padding(.bottom, 10)
            Hairline()
            ForEach(v.words) { w in
                ListLine {
                    Text(w.heard).font(DF.font(15)).foregroundStyle(DF.muted).lineLimit(1).frame(width: 220, alignment: .leading)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(DF.faint)
                    Text(w.written).font(DF.font(15, .medium)).lineLimit(1)
                } remove: { v.words.removeAll { $0.id == w.id } }
            }
            if v.words.isEmpty {
                Text("Nothing here yet.").font(DF.font(14)).foregroundStyle(DF.faint).padding(.vertical, 14)
            }
        }
    }
}

/// Say the cue, get the text.
struct SnippetsList: View {
    @ObservedObject private var v = VoiceSettings.shared
    @State private var cue = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Say the cue and the full text goes in, like your calendar link or address.").font(DF.font(15)).foregroundStyle(DF.muted)
                .padding(.bottom, 14)
            HStack(spacing: 8) {
                PlainField(prompt: "Cue, e.g. my calendar link", text: $cue).frame(width: 220)
                PlainField(prompt: "The text it becomes", text: $text)
                Button("Add") {
                    v.snippets.append(Snippet(cue: cue.lowercased(), text: text)); cue = ""; text = ""
                }
                .buttonStyle(.df(.primary, height: 30)).disabled(cue.isEmpty || text.isEmpty)
            }
            .padding(.bottom, 10)
            Hairline()
            ForEach(v.snippets) { sn in
                ListLine {
                    Text("\u{201C}\(sn.cue)\u{201D}").font(DF.font(15, .medium)).lineLimit(1).frame(width: 220, alignment: .leading)
                    Text(sn.text).font(DF.font(15)).foregroundStyle(DF.muted).lineLimit(2)
                } remove: { v.snippets.removeAll { $0.id == sn.id } }
            }
            if v.snippets.isEmpty {
                Text("Nothing here yet.").font(DF.font(14)).foregroundStyle(DF.faint).padding(.vertical, 14)
            }
        }
    }
}

/// A row in a plain list: content, then × on hover, with a hairline under it.
private struct ListLine<C: View>: View {
    @ViewBuilder var content: C
    let remove: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            content
            Spacer(minLength: 8)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.dfIcon(size: 24)).opacity(hover ? 1 : 0).help("Remove")
        }
        .frame(minHeight: 42)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// A quiet text field on a grey wash.
struct PlainField: View {
    let prompt: String
    @Binding var text: String
    var body: some View {
        TextField(prompt, text: $text).textFieldStyle(.plain).font(DF.font(14))
            .padding(.horizontal, 9).frame(height: 30)
            .background(DF.wash, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The app a dictation went into, by name.
struct AppIconView: View {
    let name: String
    var isTask = false
    var size: CGFloat = 28
    var body: some View {
        Group {
            if isTask {
                Image(systemName: "checklist").font(.system(size: size * 0.46)).foregroundStyle(DF.muted)
                    .frame(width: size, height: size).background(DF.wash, in: RoundedRectangle(cornerRadius: size * 0.25))
            } else if let icon = Self.icon(for: name) {
                Image(nsImage: icon).resizable().frame(width: size, height: size)
            } else {
                Image(systemName: "text.cursor").font(.system(size: size * 0.46)).foregroundStyle(DF.muted)
                    .frame(width: size, height: size).background(DF.wash, in: RoundedRectangle(cornerRadius: size * 0.25))
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

/// Settings › Dictation: the clean-up switches. (Dictionary and snippets live in Flow.)
struct VoiceSettingsPanel: View {
    @ObservedObject private var v = VoiceSettings.shared
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection("Clean-up") {
                PlainRow("Remove um, uh", "Filler sounds disappear") { Toggle("", isOn: $v.removeFillers).toggleStyle(.df) }
                PlainRow("Backtrack", "\u{201C}at 2, actually 3\u{201D} becomes \u{201C}at 3\u{201D}; \u{201C}scratch that\u{201D} drops the last bit") { Toggle("", isOn: $v.backtrack).toggleStyle(.df) }
                PlainRow("Spoken punctuation", "\u{201C}comma\u{201D}, \u{201C}new line\u{201D}, \u{201C}question mark\u{201D}") { Toggle("", isOn: $v.spokenPunctuation).toggleStyle(.df) }
                PlainRow("Numbered lists", "\u{201C}first\u{2026} second\u{2026}\u{201D} becomes 1. 2.") { Toggle("", isOn: $v.lists).toggleStyle(.df) }
                PlainRow("Style per app", "Casual in Messages and Slack") { Toggle("", isOn: $v.appStyles).toggleStyle(.df) }
                PlainRow("Code aware", "\u{201C}camel case user name\u{201D} becomes userName") { Toggle("", isOn: $v.codeAware).toggleStyle(.df) }
                PlainRow("Sounds", "A soft tick on start and stop") { Toggle("", isOn: $v.sounds).toggleStyle(.df) }
            }
            SettingsSection("Dictionary and snippets") {
                PlainRow("\(v.words.count) words, \(v.snippets.count) snippets", "They live in Flow, beside your history") {
                    Button("Open Flow") { withAnimation(.snappy(duration: 0.22)) { model.section = .dictation } }
                        .buttonStyle(.df(.secondary, height: 30))
                }
            }
        }
    }
}
