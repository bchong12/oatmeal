import SwiftUI
import SwiftData

/// Notes: a Finder-style list of folders and meetings, or one meeting open full width.
struct MeetingsView: View {
    @EnvironmentObject var model: AppModel
    @Query(sort: \MeetingNote.startedAt, order: .reverse) private var allNotes: [MeetingNote]
    @Query private var folders: [MeetingFolder]

    var body: some View {
        let open = allNotes.first { $0.id == model.selectedMeetingID }
        HStack(spacing: 0) {
            Group {
                if let open {
                    MeetingDetail(note: open).id(open.id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
                } else {
                    MeetingBrowser(allNotes: allNotes, folders: folders)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onExitCommand { if open != nil { withAnimation(.snappy(duration: 0.22)) { model.selectedMeetingID = nil } } }

            if model.sidePanelOpen {
                Rectangle().fill(DF.line).frame(width: 1)
                TodayMeetings().frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DF.paper)
    }
}

// MARK: - Browser

private enum SortKey { case name, people, date, length }

/// The list for the current place: folders first, then meetings, in columns you can sort.
private struct MeetingBrowser: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var meeting = MeetingService.shared
    @ObservedObject private var importer = AudioImporter.shared
    @ObservedObject private var account = OatmealAccount.shared
    let allNotes: [MeetingNote]
    let folders: [MeetingFolder]

    @State private var query = ""
    @State private var sort: SortKey = .date
    @State private var ascending = false
    /// Meetings picked with ⌘- or ⇧-click.
    @State private var picked: Set<UUID> = []
    @State private var anchor: UUID?
    @State private var fileTargeted = false

    private var here: UUID? { if case .folder(let f) = model.place { return f }; return nil }
    private var isRecent: Bool { model.place == .recent }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var current: MeetingFolder? { here.flatMap { id in folders.first { $0.id == id } } }

    private var subfolders: [MeetingFolder] {
        guard !isRecent, !searching else { return [] }
        let list = MeetingFolders.children(of: here, in: folders)
        return sort == .name && !ascending ? list.reversed() : list
    }

    private var notes: [MeetingNote] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base: [MeetingNote]
        if !q.isEmpty {
            base = allNotes.filter { n in
                n.title.lowercased().contains(q) || n.myNotes.lowercased().contains(q) || n.notesMarkdown.lowercased().contains(q)
                    || n.attendees.joined(separator: " ").lowercased().contains(q)
                    || String(decoding: n.transcriptData, as: UTF8.self).lowercased().contains(q)
            }
        } else if isRecent {
            base = Array(allNotes.prefix(100))
        } else {
            base = allNotes.filter { MeetingFolders.home(of: $0, in: folders) == here }
        }
        let sorted: [MeetingNote]
        switch sort {
        case .name: sorted = base.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .people: sorted = base.sorted { $0.attendees.joined().localizedStandardCompare($1.attendees.joined()) == .orderedAscending }
        case .date: sorted = base.sorted { $0.startedAt < $1.startedAt }
        case .length: sorted = base.sorted { $0.duration < $1.duration }
        }
        return ascending ? sorted : sorted.reversed()
    }

    var body: some View {
        let list = notes
        let subs = subfolders
        VStack(alignment: .leading, spacing: 0) {
            header(count: list.count + subs.count)
            columns
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if meeting.isRecording { LiveMeetingRow().padding(.horizontal, 16).padding(.vertical, 8) }
                        if let job = importer.job { ImportRow(job: job).padding(.horizontal, 16).padding(.vertical, 8) }
                        ForEach(subs) { f in
                            FolderListRow(folder: f, items: MeetingFolders.children(of: f.id, in: folders).count + allNotes.filter { $0.folderID == f.id }.count)
                        }
                        ForEach(list) { n in
                            MeetingListRow(note: n, picked: picked.contains(n.id), locked: account.historyCutoff.map { n.startedAt < $0 } ?? false,
                                           path: searching || isRecent ? MeetingFolders.path(to: MeetingFolders.home(of: n, in: folders), in: folders).map(\.name).joined(separator: " / ") : nil)
                                .onTapGesture { click(n, in: list) }
                                .draggable(MeetingFolders.payload(n)) { DragChip(title: n.title, count: picked.contains(n.id) ? picked.count : 1) }
                                .dfContextMenu { menu(for: n) }
                        }
                        emptyMessage(subs: subs, list: list)
                    }
                    .padding(.bottom, picked.count > 1 ? 80 : 24)
                }
                .background(Color.clear.contentShape(Rectangle()).dfContextMenu { backgroundMenu })
                .overlay {
                    if fileTargeted {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(DF.honeyDeep, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                            .background(DF.honey.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(Text("Drop a recording to transcribe it").font(DF.font(14, .semibold)).foregroundStyle(DF.umber))
                            .padding(12).allowsHitTesting(false)
                    }
                }
                if picked.count > 1 { selectionBar.padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
        }
        .background(DF.paper)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !importer.busy else { return false }
            Task { await importer.importFile(url) }
            return true
        } isTargeted: { t in withAnimation(.easeOut(duration: 0.12)) { fileTargeted = t } }
        .onChange(of: model.place) { _, _ in picked = []; query = "" }
    }

    // MARK: Header

    private func header(count: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if isRecent {
                Image(systemName: "clock").font(.system(size: 19, weight: .medium)).foregroundStyle(DF.muted)
            } else if current != nil {
                FolderGlyph(size: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(isRecent ? "Recent" : current?.name ?? "Meetings").font(DF.serif(30)).tracking(-0.6).lineLimit(1)
            }
            Text(searching ? "Searching everything" : "\(count) \(count == 1 ? "item" : "items")")
                .font(DF.font(13)).foregroundStyle(DF.faint).padding(.top, 6)
            Spacer(minLength: 12)
            SearchField(text: $query, prompt: "Search meetings").frame(width: 220)
            if !isRecent {
                Button { newFolder() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.dfIcon(size: 32))
                    .help("New folder")
            }
            Button { importer.pickAndImport() } label: { Label("Import", systemImage: "arrow.down.to.line") }
                .buttonStyle(.df(.secondary, height: 32)).disabled(importer.busy)
                .help("Transcribe a recording: a voice memo, a Zoom file, a podcast. You can also drop one on the list.")
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 16)
    }

    private var columns: some View {
        HStack(spacing: 0) {
            column("Name", .name).frame(maxWidth: .infinity, alignment: .leading)
            column("People", .people).frame(width: 170, alignment: .leading)
            column("Date", .date).frame(width: 150, alignment: .leading)
            column("Length", .length).frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 28).frame(height: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(DF.line).frame(height: 1).padding(.horizontal, 16) }
    }

    private func column(_ title: String, _ key: SortKey) -> some View {
        let on = sort == key
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if on { ascending.toggle() } else { sort = key; ascending = key == .name || key == .people }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).font(DF.font(12, on ? .semibold : .medium)).foregroundStyle(on ? DF.ink : DF.faint)
                if on { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(DF.muted) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func emptyMessage(subs: [MeetingFolder], list: [MeetingNote]) -> some View {
        if subs.isEmpty && list.isEmpty && !meeting.isRecording && importer.job == nil {
            if searching {
                hint("Nothing matches \u{201C}\(query)\u{201D}", "Try a name, a word someone said, or a meeting title.")
            } else if allNotes.isEmpty {
                hint("No meetings yet", "When a call starts, Oatmeal offers to take notes. No bot joins, and everything stays on your Mac. Record a meeting from the sidebar, or press right \u{2325} M.")
            } else if current != nil {
                hint("This folder is empty", "Drag meetings or folders here, or right-click a meeting and choose Move to.")
            } else {
                hint("Everything\u{2019}s filed", "Every meeting is in a folder. Recent shows them all, newest first.")
            }
        }
    }

    private func hint(_ title: String, _ message: String) -> some View {
        VStack(spacing: 8) {
            BrandMark(size: 44).padding(.bottom, 4)
            Text(title).font(DF.serif(20))
            Text(message).font(DF.font(14)).foregroundStyle(DF.muted).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity).padding(.top, 70)
    }

    // MARK: Selection

    private var pickedNotes: [MeetingNote] { allNotes.filter { picked.contains($0.id) } }

    /// Click opens a meeting; ⌘-click adds or removes it from the pick, ⇧-click picks the run in between.
    private func click(_ n: MeetingNote, in list: [MeetingNote]) {
        if let cutoff = account.historyCutoff, n.startedAt < cutoff { return offerPro() }
        let mods = NSEvent.modifierFlags
        if mods.contains(.shift), let a = anchor, let i = list.firstIndex(where: { $0.id == a }), let j = list.firstIndex(where: { $0.id == n.id }) {
            withAnimation(.snappy(duration: 0.18)) { picked = Set(list[min(i, j)...max(i, j)].map(\.id)) }
            return
        }
        if mods.contains(.command) {
            withAnimation(.snappy(duration: 0.18)) { if picked.contains(n.id) { picked.remove(n.id) } else { picked.insert(n.id) } }
            anchor = n.id
            return
        }
        picked = []
        anchor = n.id
        withAnimation(.snappy(duration: 0.22)) { model.selectedMeetingID = n.id }
    }

    private var selectionBar: some View {
        HStack(spacing: 4) {
            Text("\(picked.count) selected").font(DF.font(13, .semibold)).foregroundStyle(.white).padding(.leading, 10).padding(.trailing, 6)
            BarButton(title: "Move to", icon: "folder") { frame in
                Popups.shared.showMenu(MeetingFolders.destinations(model: model) { dest in
                    MeetingFolders.move(pickedNotes, to: dest, in: model.context); picked = []
                }, below: frame, width: 240)
            }
            BarButton(title: "Merge", icon: "arrow.triangle.merge") { _ in confirmMerge(pickedNotes) }
            BarButton(title: "Delete", icon: "trash") { _ in confirmDelete(pickedNotes) }
            Button { withAnimation(.snappy(duration: 0.18)) { picked = [] } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Clear selection")
        }
        .padding(5)
        .background(DF.ink, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }

    // MARK: Actions

    /// Free keeps the last 30 days open; older meetings are still on this Mac, just locked.
    private func offerPro() {
        let days = account.me?.historyDays ?? 30
        if account.signedIn {
            Popups.shared.confirm("Unlock older meetings", "Free shows your last \(days) days. Pro opens every meeting you\u{2019}ve recorded; they\u{2019}re all still on this Mac.",
                                  confirm: "See Pro") { account.openPricing() }
        } else {
            Popups.shared.confirm("Sign in to see older meetings", "Free shows your last \(days) days. Sign in, and Pro opens every meeting you\u{2019}ve recorded.",
                                  confirm: "Sign in") { account.signIn() }
        }
    }

    private func newFolder() {
        let f = MeetingFolders.create(in: here, ctx: model.context)
        model.startRenaming(f, inSidebar: false)
    }

    private var backgroundMenu: [DFMenuItem] {
        var items: [DFMenuItem] = []
        if !isRecent { items.append(.action("New folder", icon: "folder.badge.plus") { newFolder() }) }
        items.append(.action("Import a recording\u{2026}", icon: "arrow.down.to.line") { importer.pickAndImport() })
        return items
    }

    private func menu(for n: MeetingNote) -> [DFMenuItem] {
        if picked.count > 1 && picked.contains(n.id) {
            let group = pickedNotes
            return [
                .submenu("Move \(group.count) to", icon: "folder", MeetingFolders.destinations(model: model) { dest in
                    MeetingFolders.move(group, to: dest, in: model.context); picked = []
                }),
                .action("Merge \(group.count) meetings\u{2026}", icon: "arrow.triangle.merge") { confirmMerge(group) },
                .divider,
                .action("Delete \(group.count) meetings\u{2026}", icon: "trash", destructive: true) { confirmDelete(group) },
            ]
        }
        return MeetingMenu.items(for: n, all: allNotes, model: model)
    }

    private func confirmMerge(_ notes: [MeetingNote]) {
        MeetingMenu.confirmMerge(notes, model: model) { picked = [] }
    }

    private func confirmDelete(_ notes: [MeetingNote]) {
        MeetingMenu.confirmDelete(notes, model: model) { picked = [] }
    }
}

/// The menu for one meeting, shared by the list's right-click and the detail's ⋯ button.
@MainActor
enum MeetingMenu {
    static func items(for n: MeetingNote, all: [MeetingNote], model: AppModel) -> [DFMenuItem] {
        let ctx = model.context
        let folders = MeetingFolders.all(ctx)
        let nearest = all.filter { $0.id != n.id }
            .sorted { abs($0.startedAt.timeIntervalSince(n.startedAt)) < abs($1.startedAt.timeIntervalSince(n.startedAt)) }
            .prefix(6)
        var items: [DFMenuItem] = []
        if model.selectedMeetingID != n.id {
            items.append(.action("Open", icon: "doc.text") { withAnimation(.snappy(duration: 0.22)) { model.selectedMeetingID = n.id } })
        }
        items.append(.submenu("Move to", icon: "folder", MeetingFolders.destinations(model: model, current: .some(MeetingFolders.home(of: n, in: folders))) { dest in
            MeetingFolders.move([n], to: dest, in: ctx)
        }))
        if !nearest.isEmpty {
            items.append(.submenu("Merge with", icon: "arrow.triangle.merge", nearest.map { o in
                .action(o.title, hint: o.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())) { confirmMerge([n, o], model: model) }
            }))
        }
        items.append(.action("Copy notes", icon: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(n.notesMarkdown.isEmpty ? n.title : "# \(n.title)\n\n\(n.notesMarkdown)", forType: .string)
        })
        items.append(.divider)
        items.append(.action("Delete\u{2026}", icon: "trash", destructive: true) { confirmDelete([n], model: model) })
        return items
    }

    static func confirmMerge(_ notes: [MeetingNote], model: AppModel, then: @escaping () -> Void = {}) {
        guard notes.count > 1 else { return }
        Popups.shared.confirm("Merge \(notes.count) meetings?",
                              "Their transcripts and notes join, in time order, into the earliest one. This can\u{2019}t be undone.",
                              confirm: "Merge") {
            if let m = MeetingMerge.merge(notes, in: model.context) { model.selectedMeetingID = m.id }
            then()
        }
    }

    static func confirmDelete(_ notes: [MeetingNote], model: AppModel, then: @escaping () -> Void = {}) {
        guard !notes.isEmpty else { return }
        let title = notes.count == 1 ? "Delete \u{201C}\(notes[0].title)\u{201D}?" : "Delete \(notes.count) meetings?"
        Popups.shared.confirm(title, "Transcripts and notes are deleted from this Mac. This can\u{2019}t be undone.", confirm: "Delete", destructive: true) {
            let ids = Set(notes.map(\.id))
            withAnimation(.snappy(duration: 0.2)) {
                if let open = model.selectedMeetingID, ids.contains(open) { model.selectedMeetingID = nil }
                for n in notes { model.context.delete(n) }
            }
            try? model.context.save()
            then()
        }
    }
}

/// A button in the dark selection bar; hands back its frame so a menu can hang off it.
private struct BarButton: View {
    let title: String
    let icon: String
    let action: (CGRect) -> Void
    @State private var frame: CGRect = .zero
    @State private var hover = false
    var body: some View {
        Button { action(frame) } label: {
            Label(title, systemImage: icon).labelStyle(DFLabelStyle())
                .font(DF.font(13, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).frame(height: 28)
                .background(hover ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .popupAnchor($frame)
    }
}

/// What follows the pointer while dragging meetings.
private struct DragChip: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(spacing: 7) {
            MeetingGlyph()
            Text(count > 1 ? "\(count) meetings" : title).font(DF.font(13, .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(DF.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DF.line))
    }
}

/// A small page with lines: a meeting's icon in the list.
struct MeetingGlyph: View {
    var size: CGFloat = 16
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.16)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: size * 0.16).strokeBorder(Color(hex: 0xCFC6B2), lineWidth: 1))
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: size * 0.11) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i == 0 ? DF.honeyDeep : Color(hex: 0xD6CEBC)).frame(width: size * (i == 2 ? 0.34 : 0.5), height: max(1, size * 0.07))
                    }
                }
                .padding(.top, size * 0.24)
            }
            .frame(width: size * 0.82, height: size)
    }
}

private struct FolderListRow: View {
    @EnvironmentObject var model: AppModel
    let folder: MeetingFolder
    let items: Int
    @State private var hover = false
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                FolderGlyph(size: 18)
                if model.renaming?.id == folder.id && model.renaming?.inSidebar == false {
                    FolderNameField(folder: folder).frame(maxWidth: 280)
                } else {
                    Text(folder.name).font(DF.font(14, .semibold)).foregroundStyle(DF.ink).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\u{2014}").frame(width: 170, alignment: .leading)
            Text("\(items) \(items == 1 ? "item" : "items")").frame(width: 150, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 70, alignment: .trailing)
        }
        .font(DF.font(13)).foregroundStyle(DF.muted)
        .modifier(ListRowChrome(hover: hover, picked: false, targeted: targeted))
        .onHover { hover = $0 }
        .onTapGesture { model.go(.folder(folder.id)) }
        .draggable(MeetingFolders.payload(folder)) {
            HStack(spacing: 6) { FolderGlyph(size: 15); Text(folder.name).font(DF.font(13, .semibold)) }
                .padding(.horizontal, 10).frame(height: 30).background(DF.paper, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, _ in MeetingFolders.drop(items, into: folder.id, ctx: model.context) }
            isTargeted: { t in withAnimation(.easeOut(duration: 0.12)) { targeted = t } }
        .dfContextMenu { MeetingFolders.menu(for: folder, model: model, inSidebar: false) }
    }
}

private struct MeetingListRow: View {
    let note: MeetingNote
    let picked: Bool
    /// Older than the free plan's history: shown, but opens an upgrade prompt.
    var locked = false
    /// The folder it's in, shown while searching or in Recent.
    let path: String?
    @ObservedObject private var writers = NoteWriters.shared
    @State private var hover = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                MeetingGlyph(size: 18)
                Text(note.title).font(DF.font(14, .semibold)).foregroundStyle(DF.ink).lineLimit(1)
                if locked {
                    Label("Pro", systemImage: "lock.fill").labelStyle(DFLabelStyle()).font(DF.font(11, .bold)).foregroundStyle(DF.ink)
                        .padding(.horizontal, 7).frame(height: 18).background(DF.honey.opacity(0.7), in: Capsule())
                } else if writers.running.contains(note.id) {
                    HStack(spacing: 5) { DFSpinner(size: 10, color: DF.muted); Text("Writing notes").font(DF.font(12)) }
                        .foregroundStyle(DF.muted)
                } else if note.notesMarkdown.isEmpty && note.summary.isEmpty {
                    Text("No notes").font(DF.font(11, .semibold)).foregroundStyle(DF.faint)
                        .padding(.horizontal, 6).frame(height: 18).background(DF.wash.opacity(0.7), in: Capsule())
                }
                if let path, !path.isEmpty {
                    HStack(spacing: 4) { FolderGlyph(size: 11); Text(path).lineLimit(1) }
                        .font(DF.font(12)).foregroundStyle(DF.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(note.attendees.isEmpty ? "\u{2014}" : note.attendees.joined(separator: ", ")).lineLimit(1).frame(width: 170, alignment: .leading)
            Text(Self.when(note.startedAt)).lineLimit(1).frame(width: 150, alignment: .leading)
            Text("\(max(1, Int((note.duration / 60).rounded()))) min").monospacedDigit().frame(width: 70, alignment: .trailing)
        }
        .font(DF.font(13)).foregroundStyle(DF.muted)
        .opacity(locked ? 0.55 : 1)
        .modifier(ListRowChrome(hover: hover, picked: picked, targeted: false))
        .onHover { hover = $0 }
    }

    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(d) { return "Today, \(time)" }
        if cal.isDateInYesterday(d) { return "Yesterday, \(time)" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day, days < 7 {
            return d.formatted(.dateTime.weekday(.wide)) + ", " + time
        }
        return cal.isDate(d, equalTo: Date(), toGranularity: .year)
            ? d.formatted(.dateTime.month(.abbreviated).day()) : d.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// Row height, hairline, and the hover / picked / drop-target highlight shared by list rows.
private struct ListRowChrome: ViewModifier {
    let hover: Bool
    let picked: Bool
    let targeted: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(targeted ? DF.honey.opacity(0.45) : picked ? DF.honey.opacity(0.28) : hover ? DF.canvas : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? DF.honeyDeep : .clear, lineWidth: 1.5))
            )
            .overlay(alignment: .bottom) { Rectangle().fill(DF.line.opacity(0.6)).frame(height: 1).padding(.horizontal, 12) }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
    }
}

/// An imported file being transcribed, or why it couldn't be.
private struct ImportRow: View {
    let job: AudioImporter.Job
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.error == nil ? "waveform" : "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(job.error == nil ? DF.muted : DF.tiredInk)
                .frame(width: 30, height: 30).background(DF.wash.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(job.name).font(DF.font(14, .semibold)).lineLimit(1)
                if let e = job.error {
                    Text(e).font(DF.font(12)).foregroundStyle(DF.tiredInk).fixedSize(horizontal: false, vertical: true)
                } else {
                    DFProgressBar(value: job.progress).frame(maxWidth: 260)
                    Text(job.progress >= 1 ? "Writing notes\u{2026}" : "Transcribing \(Int(job.progress * 100))%").font(DF.font(12)).foregroundStyle(DF.muted)
                }
            }
            Spacer()
            if job.error != nil {
                Button { AudioImporter.shared.dismissError() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.dfIcon())
            }
        }
        .padding(12)
        .background(DF.canvas, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DF.line))
    }
}

private struct LiveMeetingRow: View {
    @ObservedObject private var meeting = MeetingService.shared
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(DF.now).frame(width: 9, height: 9)
                .overlay(Circle().stroke(DF.now.opacity(0.4), lineWidth: 6).scaleEffect(pulse ? 1.6 : 0.8).opacity(pulse ? 0 : 1))
                .onAppear { withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true } }
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording \u{00B7} \(Duration.seconds(meeting.elapsed).formatted(.time(pattern: .minuteSecond)))").font(DF.font(14, .semibold)).monospacedDigit()
                Text(meeting.segments.last?.text ?? "Listening\u{2026}").font(DF.font(12)).foregroundStyle(DF.muted).lineLimit(1)
            }
            Spacer()
            Button { PillController.shared.toggleMeeting() } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.df(.secondary))
        }
        .padding(12)
        .background(DF.tiredBg.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DF.now.opacity(0.18)))
    }
}

// MARK: - Detail

struct MeetingDetail: View {
    @Bindable var note: MeetingNote
    @EnvironmentObject var model: AppModel
    @Query(sort: \MeetingNote.startedAt, order: .reverse) private var allNotes: [MeetingNote]
    @State private var tab = 0
    @State private var copied = false
    @State private var promptCopied = false
    @State private var moreFrame: CGRect = .zero
    @ObservedObject private var mcp = MCPServer.shared
    @ObservedObject private var writers = NoteWriters.shared

    /// What the copy button copies: whatever the open tab shows.
    var copyText: String {
        switch tab {
        case 1: return segments.plainText
        case 2: return note.myNotes
        default:
            var md = "# \(note.title)\n\(note.startedAt.formatted(date: .abbreviated, time: .shortened))"
            if !note.attendees.isEmpty { md += " · " + note.attendees.joined(separator: ", ") }
            if !meetingNotes.isEmpty { md += "\n\n" + meetingNotes }
            return md
        }
    }

    var copyLabel: String { ["Copy notes", "Copy transcript", "Copy my notes"][tab] }

    /// The Granola-style notes, or older meetings' summary and action items shown the same way.
    var meetingNotes: String {
        if !note.notesMarkdown.isEmpty { return note.notesMarkdown }
        var parts: [(String, [String])] = []
        if !note.summary.isEmpty { parts.append(("Summary", note.summary)) }
        if !note.actionItems.isEmpty { parts.append(("Next steps", note.actionItems)) }
        return parts.map { "### \($0.0)\n" + $0.1.map { "- \($0)" }.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    /// Writes the notes with the AI on this Mac; otherwise copies the prompt to paste into one.
    func createNotes() {
        guard mcp.isRunning else { model.settingsTab = "MCP"; model.section = .settings; return }
        if writers.available { writers.run(note); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(NoteWriters.prompt(for: note), forType: .string)
        withAnimation(.snappy) { promptCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation(.snappy) { promptCopied = false } }
    }

    var segments: [TranscriptSegment] { (try? JSONDecoder().decode([TranscriptSegment].self, from: note.transcriptData)) ?? [] }

    var body: some View {
        let writing = writers.running.contains(note.id)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    TextField("Untitled meeting", text: $note.title, axis: .vertical)
                        .textFieldStyle(.plain).font(DF.serif(32)).tracking(-0.6)
                    Button {
                        Popups.shared.showMenu(MeetingMenu.items(for: note, all: allNotes, model: model), below: moreFrame, width: 230)
                    } label: { Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(.dfIcon(size: 32))
                    .popupAnchor($moreFrame)
                    .padding(.top, 4)
                    .help("More")
                }
                HStack(spacing: 6) {
                    meta("calendar", note.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    meta("clock", "\(max(1, Int((note.duration / 60).rounded()))) min")
                    if !note.attendees.isEmpty { meta("person.2", note.attendees.joined(separator: ", ")) }
                    MeetingFolderChip(note: note)
                }
                .padding(.top, 10)

                HStack(alignment: .bottom) {
                    DFTabs(items: [(0, "Notes"), (2, "My notes"), (1, "Transcript")], selection: $tab)
                    Spacer()
                    HStack(spacing: 4) {
                        Button { createNotes() } label: {
                            HStack(spacing: 6) {
                                if writing { DFSpinner(size: 11, color: DF.muted) }
                                else { Image(systemName: promptCopied ? "checkmark" : "sparkles").font(.system(size: 11.5, weight: .semibold)) }
                                Text(writing ? "Writing notes\u{2026}" : promptCopied ? "Prompt copied" : meetingNotes.isEmpty ? "Write notes" : "Redo notes")
                            }
                        }
                        .buttonStyle(.df(.ghost))
                        .disabled(writing)
                        .help(!mcp.isRunning ? "Turn on Oatmeal\u{2019}s MCP server first (Settings \u{203A} MCP)"
                              : writers.available ? "\(writers.active?.title ?? "Your AI") fixes the transcript and writes Granola-style notes here, on \(writers.active?.plan ?? "your plan")."
                              : "Copies a prompt for Claude, Cursor or Codex. It writes the notes here through Oatmeal\u{2019}s MCP.")
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(copyText, forType: .string)
                            withAnimation(.snappy) { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(.snappy) { copied = false } }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(copied ? DF.thrivingInk : DF.muted)
                        }
                        .buttonStyle(.dfIcon(size: 30))
                        .disabled(copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help(copyLabel)
                    }
                    .padding(.bottom, 6)
                }
                .padding(.top, 26)
                .overlay(alignment: .bottom) { Rectangle().fill(DF.line).frame(height: 1) }
                .padding(.bottom, 24)

                Group {
                    if tab == 2 { myNotes } else if tab == 0 { notesTab(writing: writing) } else { transcript }
                }
            }
            .padding(.horizontal, 40).padding(.top, 34).padding(.bottom, 40)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .background(DF.paper)
    }

    private func meta(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium))
            Text(text).font(DF.font(13)).lineLimit(1)
        }
        .foregroundStyle(DF.muted)
        .padding(.horizontal, 7).frame(height: 24)
        .background(DF.canvas, in: RoundedRectangle(cornerRadius: 6))
    }

    private var myNotes: some View {
        ZStack(alignment: .topLeading) {
            if note.myNotes.isEmpty {
                Text("Nothing typed during this meeting. Add notes here any time.")
                    .font(DF.font(15)).foregroundStyle(DF.faint).padding(.top, 1).padding(.leading, 5)
            }
            TextEditor(text: $note.myNotes).font(DF.font(15)).scrollContentBackground(.hidden).frame(minHeight: 300)
        }
    }

    @ViewBuilder private func notesTab(writing: Bool) -> some View {
        if writing {
            HStack(spacing: 12) {
                DFSpinner(size: 16)
                Text("\(writers.active?.title ?? "Your AI") is fixing the transcript and writing the notes. They appear here in a minute or two.")
                    .font(DF.font(14)).foregroundStyle(DF.muted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DF.canvas, in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 20)
        } else if let error = writers.errors[note.id] {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(DF.tiredInk)
                Text("Couldn\u{2019}t write the notes: \(error)").font(DF.font(13)).foregroundStyle(DF.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Try again") { writers.run(note) }.buttonStyle(.df(.secondary))
            }
            .padding(14).background(DF.tiredBg.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DF.tiredInk.opacity(0.15)))
            .padding(.bottom, 20)
        }
        if meetingNotes.isEmpty && !writing {
            VStack(alignment: .leading, spacing: 12) {
                Text(segments.isEmpty ? "Nothing was recorded in this meeting." : "No notes yet.")
                    .font(DF.serif(20))
                if !segments.isEmpty {
                    Text("Oatmeal can write Granola-style notes from the transcript and anything you typed.")
                        .font(DF.font(14)).foregroundStyle(DF.muted)
                    Button { createNotes() } label: { Label("Write notes", systemImage: "sparkles") }
                        .buttonStyle(.df(.honey, height: 34)).padding(.top, 4)
                }
            }
        } else if !meetingNotes.isEmpty {
            GranolaNotes(markdown: meetingNotes)
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 16) {
            if segments.isEmpty { Text("No transcript for this meeting.").font(DF.font(14)).foregroundStyle(DF.muted) }
            ForEach(segments) { s in
                HStack(alignment: .top, spacing: 14) {
                    Text(Duration.seconds(s.offset).formatted(.time(pattern: .minuteSecond))).font(DF.font(12)).monospacedDigit()
                        .foregroundStyle(DF.faint).frame(width: 44, alignment: .leading).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.speaker).font(DF.font(13, .bold))
                        Text(s.text).font(DF.font(15)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct TodayMeetings: View {
    @EnvironmentObject var calendars: CalendarStore
    @AppStorage("autoRecordIDs") private var autoRecordRaw = ""

    var body: some View {
        let events = calendars.events(on: Date()).filter { !$0.isAllDay }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").font(DF.serif(20))
                Spacer()
                PanelCloseButton()
            }
            .padding(.top, 20)
            Text(calendars.anyConnected ? "Turn on auto-record per meeting" : "Connect your calendar to see today\u{2019}s meetings")
                .font(DF.font(12)).foregroundStyle(DF.muted).padding(.bottom, 10)
            if !calendars.anyConnected {
                SecondaryButton(title: "Allow calendar access", symbol: "calendar") { Task { await calendars.requestAccess() } }
            } else if events.isEmpty {
                Text("Nothing else on your calendar today.").font(DF.font(13)).foregroundStyle(DF.faint)
            }
            ForEach(events) { e in
                let on = autoRecordRaw.split(separator: "|").contains(Substring(e.id))
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(e.end < Date() ? DF.checkbox : DF.honeyDeep).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(DF.font(13, .semibold)).lineLimit(1)
                        Text("\(e.start.formatted(date: .omitted, time: .shortened)) \u{2013} \(e.end.formatted(date: .omitted, time: .shortened))")
                            .font(DF.font(12)).foregroundStyle(DF.muted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { on }, set: { v in
                        var ids = Set(autoRecordRaw.split(separator: "|").map(String.init))
                        if v { ids.insert(e.id) } else { ids.remove(e.id) }
                        autoRecordRaw = ids.joined(separator: "|")
                    }))
                    .toggleStyle(.df)
                    .help("Record this meeting automatically")
                }
                .padding(.vertical, 8)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
        .background(DF.canvas)
    }
}

struct ModelBadge: View {
    let state: VoiceModelState
    var body: some View {
        let (text, color): (String, Color) = {
            switch state {
            case .ready: ("On-device model ready", DF.thrivingInk)
            case .downloading(let p): ("Downloading model \(Int(p * 100))%", DF.okayInk)
            case .notLoaded: ("Model loads on first use", DF.muted)
            case .failed: ("Model failed to load", DF.tiredInk)
            }
        }()
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(DF.font(12, .semibold)).foregroundStyle(DF.muted)
        }
        .padding(.horizontal, 10).frame(height: 28).background(DF.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(DF.line))
    }
}

/// Granola-style notes: short topic headings with terse bullets. Reads the light markdown in
/// `MeetingNote.notesMarkdown` (`### Heading`, `- bullet`, `  - detail`, **bold** inline).
struct GranolaNotes: View {
    let markdown: String

    private enum Line: Hashable { case heading(String), bullet(String, depth: Int), text(String) }

    private var lines: [Line] {
        markdown.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return nil }
            if t.hasPrefix("#") { return .heading(t.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)) }
            for marker in ["- ", "* ", "• "] where t.hasPrefix(marker) {
                return .bullet(String(t.dropFirst(marker.count)), depth: min(indent / 2, 2))
            }
            return .text(t)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                switch line {
                case .heading(let h):
                    Text(h).font(DF.serif(21)).padding(.top, i == 0 ? 0 : 18).padding(.bottom, 2)
                case .bullet(let b, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(depth == 0 ? DF.honeyDeep : DF.faint).frame(width: 5, height: 5).offset(y: -2)
                        Text(Self.inline(b)).font(DF.font(15)).foregroundStyle(depth == 0 ? DF.ink : DF.muted)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(depth) * 18)
                case .text(let t):
                    Text(Self.inline(t)).font(DF.font(15)).lineSpacing(2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
