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
    let allNotes: [MeetingNote]
    let folders: [MeetingFolder]

    @State private var query = ""
    @State private var sort: SortKey = .date
    @State private var ascending = false
    /// Meetings picked with ⌘- or ⇧-click.
    @State private var picked: Set<UUID> = []
    @State private var anchor: UUID?
    @State private var fileTargeted = false
    @State private var weekOnly = false

    private enum ViewKind: Hashable { case all, recent, week }
    private var viewKind: Binding<ViewKind> {
        Binding(get: { isRecent ? (weekOnly ? .week : .recent) : .all }, set: { v in
            weekOnly = v == .week
            model.go(v == .all ? .folder(nil) : .recent)
        })
    }
    private var topLevel: Bool { isRecent || here == nil }

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
        } else if isRecent && weekOnly {
            let start = Calendar.oatmeal.dateInterval(of: .weekOfYear, for: Date())!.start
            base = allNotes.filter { $0.startedAt >= start }
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
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header(count: list.count + subs.count)
                    if topLevel && !searching { UpNextStrip().padding(.top, 22) }
                    toolbar.padding(.top, 22).padding(.bottom, 6)
                    columns
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if meeting.isRecording { LiveMeetingRow().padding(.vertical, 8) }
                        if let job = importer.job { ImportRow(job: job).padding(.vertical, 8) }
                        ForEach(subs) { f in
                            FolderListRow(folder: f, items: MeetingFolders.children(of: f.id, in: folders).count + allNotes.filter { $0.folderID == f.id }.count)
                        }
                        ForEach(list) { n in
                            MeetingListRow(note: n, picked: picked.contains(n.id),
                                           path: searching || isRecent ? MeetingFolders.path(to: MeetingFolders.home(of: n, in: folders), in: folders).map(\.name).joined(separator: " / ") : nil)
                                .onTapGesture { click(n, in: list) }
                                .draggable(MeetingFolders.payload(n)) { DragChip(title: n.title, count: picked.contains(n.id) ? picked.count : 1) }
                                .dfContextMenu { menu(for: n) }
                        }
                        emptyMessage(subs: subs, list: list)
                    }
                }
                .pageColumn(DF.tableWidth)
                .padding(.top, 36).padding(.bottom, picked.count > 1 ? 80 : 40)
                .background(Color.clear.contentShape(Rectangle()).dfContextMenu { backgroundMenu })
            }
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
        .background(DF.paper)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !importer.busy else { return false }
            Task { await importer.importFile(url) }
            return true
        } isTargeted: { t in withAnimation(.easeOut(duration: 0.12)) { fileTargeted = t } }
        .onChange(of: model.place) { _, _ in picked = []; query = "" }
    }

    // MARK: Header

    @ViewBuilder private func header(count: Int) -> some View {
        if let current {
            NotionHeader(icon: .symbol("folder"), title: current.name,
                         description: "\(count) \(count == 1 ? "item" : "items")") { importButton }
        } else {
            NotionHeader(icon: .face("face-k"), title: "Meetings",
                         description: "Every call you\u{2019}ve recorded, with notes written for you. Nothing leaves this Mac.") {
                HStack(spacing: 8) {
                    importButton
                    Button { PillController.shared.toggleMeeting() } label: {
                        HStack(spacing: 7) {
                            Circle().fill(DF.now).frame(width: 7, height: 7)
                            Text(meeting.isRecording ? "Stop" : "Record")
                        }
                    }
                    .buttonStyle(.df(.primary, height: 32))
                    .help("Record a meeting (\u{2318}N)")
                }
            }
        }
    }

    private var importButton: some View {
        Button { importer.pickAndImport() } label: { Label("Import", systemImage: "arrow.down.to.line") }
            .buttonStyle(.df(.secondary, height: 32)).disabled(importer.busy)
            .help("Transcribe a recording: a voice memo, a Zoom file, a podcast. You can also drop one on the list.")
    }

    /// The views (at the top level), then search and a new-folder button.
    private var toolbar: some View {
        HStack(spacing: 8) {
            if topLevel {
                ViewTabs(items: [(ViewKind.all, "All meetings", "square.grid.2x2"), (.recent, "Recent", "clock"), (.week, "This week", "calendar")],
                         selection: viewKind)
            } else {
                Text(searching ? "Searching everything" : "In this folder").font(DF.font(14, .medium)).foregroundStyle(DF.muted)
            }
            Spacer(minLength: 8)
            if !isRecent {
                Button { newFolder() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.dfIcon(size: 30))
                    .help("New folder")
            }
            SearchField(text: $query, prompt: "Search meetings").frame(width: 220)
        }
    }

    private var columns: some View {
        HStack(spacing: 0) {
            column("Name", .name).frame(maxWidth: .infinity, alignment: .leading)
            column("People", .people).frame(width: 150, alignment: .leading)
            Text("Notes").font(DF.font(13, .medium)).foregroundStyle(DF.faint).frame(width: 96, alignment: .leading)
            column("Date", .date).frame(width: 130, alignment: .leading)
            column("Length", .length).frame(width: 64, alignment: .trailing)
        }
        .frame(height: 34)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func column(_ title: String, _ key: SortKey) -> some View {
        let on = sort == key
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if on { ascending.toggle() } else { sort = key; ascending = key == .name || key == .people }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).font(DF.font(13, .medium)).foregroundStyle(on ? DF.muted : DF.faint)
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
            .overlay(RoundedRectangle(cornerRadius: size * 0.16).strokeBorder(Color(hex: 0xD3D1CB), lineWidth: 1))
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: size * 0.11) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i == 0 ? DF.honeyDeep : Color(hex: 0xD3D1CB)).frame(width: size * (i == 2 ? 0.34 : 0.5), height: max(1, size * 0.07))
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
                    Text(folder.name).font(DF.font(15, .medium)).foregroundStyle(DF.ink).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\u{2014}").foregroundStyle(DF.faint).frame(width: 150, alignment: .leading)
            Color.clear.frame(width: 96)
            Text("\(items) \(items == 1 ? "item" : "items")").frame(width: 130, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(DF.faint).frame(width: 64, alignment: .trailing)
        }
        .font(DF.font(14)).foregroundStyle(DF.muted)
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
    /// The folder it's in, shown while searching or in Recent.
    let path: String?
    @ObservedObject private var writers = NoteWriters.shared
    @State private var hover = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                MeetingGlyph(size: 18)
                Text(note.title).font(DF.font(15, .medium)).foregroundStyle(DF.ink).lineLimit(1)
                if let path, !path.isEmpty {
                    HStack(spacing: 4) { FolderGlyph(size: 11); Text(path).lineLimit(1) }
                        .font(DF.font(13)).foregroundStyle(DF.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if note.attendees.isEmpty { Text("\u{2014}").foregroundStyle(DF.faint) }
                else { InitialsStack(names: note.attendees) }
            }
            .frame(width: 150, alignment: .leading)
            Group {
                if writers.running.contains(note.id) { NotionTag(text: "Writing\u{2026}", tone: .yellow, spinner: true) }
                else if note.notesMarkdown.isEmpty && note.summary.isEmpty { NotionTag(text: "No notes") }
                else { NotionTag(text: "Written", tone: .green) }
            }
            .frame(width: 96, alignment: .leading)
            Text(Self.when(note.startedAt)).lineLimit(1).frame(width: 130, alignment: .leading)
            Text("\(max(1, Int((note.duration / 60).rounded()))) min").monospacedDigit().frame(width: 64, alignment: .trailing)
        }
        .font(DF.font(14)).foregroundStyle(DF.muted)
        .modifier(ListRowChrome(hover: hover, picked: picked, targeted: false))
        .onHover { hover = $0 }
    }

    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(d) { return "Today \u{00B7} \(time)" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day, days < 7 {
            return d.formatted(.dateTime.weekday(.wide))
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
            .frame(height: 44)
            .overlay(alignment: .bottom) { Hairline() }
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(targeted ? DF.honey.opacity(0.45) : picked ? DF.honey.opacity(0.28) : hover ? DF.canvas : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(targeted ? DF.honeyDeep : .clear, lineWidth: 1.5))
            )
            .contentShape(Rectangle())
            .padding(.horizontal, -8)
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
                PageIcon(art: .meeting).padding(.bottom, 14)
                HStack(alignment: .top, spacing: 12) {
                    TextField("Untitled meeting", text: $note.title, axis: .vertical)
                        .textFieldStyle(.plain).font(DF.font(40, .bold)).tracking(-0.8)
                    Button {
                        Popups.shared.showMenu(MeetingMenu.items(for: note, all: allNotes, model: model), below: moreFrame, width: 230)
                    } label: { Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(.dfIcon(size: 32))
                    .popupAnchor($moreFrame)
                    .padding(.top, 4)
                    .help("More")
                }
                VStack(alignment: .leading, spacing: 2) {
                    property("calendar", "When") {
                        Text(note.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                             + " \u{00B7} \(max(1, Int((note.duration / 60).rounded()))) min")
                            .font(DF.font(15)).foregroundStyle(DF.ink)
                    }
                    if !note.attendees.isEmpty {
                        property("person.2", "People") {
                            HStack(spacing: 6) {
                                ForEach(note.attendees.prefix(6), id: \.self) { a in
                                    HStack(spacing: 6) {
                                        InitialsStack(names: [a], size: 18)
                                        Text(a).font(DF.font(14)).lineLimit(1)
                                    }
                                    .padding(.leading, 3).padding(.trailing, 8).frame(height: 24)
                                    .background(DF.wash, in: Capsule())
                                }
                            }
                        }
                    }
                    property("folder", "Folder") { MeetingFolderChip(note: note).padding(.leading, -7) }
                }
                .padding(.top, 18)

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
                .padding(.top, 22)
                .overlay(alignment: .bottom) { Rectangle().fill(DF.line).frame(height: 1) }
                .padding(.bottom, 24)

                Group {
                    if tab == 2 { myNotes } else if tab == 0 { notesTab(writing: writing) } else { transcript }
                }
            }
            .pageColumn()
            .padding(.top, 36).padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
        .background(DF.paper)
    }

    /// A Notion property: icon and name on the left, its value beside them.
    private func property<V: View>(_ icon: String, _ name: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 16)
                Text(name).font(DF.font(15))
            }
            .foregroundStyle(DF.muted)
            .frame(width: 150, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
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
            if !note.summary.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text("\u{1F4A1}").font(.system(size: 17))
                    Text(note.summary.map { l in let t = l.trimmingCharacters(in: .whitespaces); return t.last.map { ".!?".contains($0) } == true ? t : t + "." }.joined(separator: " ")).font(DF.font(16)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DF.canvas, in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 22)
            }
            if !note.notesMarkdown.isEmpty {
                GranolaNotes(markdown: note.notesMarkdown) { i in note.notesMarkdown = GranolaNotes.toggle(line: i, in: note.notesMarkdown) }
            } else if !note.actionItems.isEmpty {
                GranolaNotes(markdown: "### Next steps\n" + note.actionItems.map { "- [ ] \($0)" }.joined(separator: "\n"))
            }
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

/// Granola-style notes, drawn the way Notion draws a page: headings, small ink bullets, and to-dos.
/// Reads the light markdown in `MeetingNote.notesMarkdown` (`### Heading`, `- bullet`, `  - detail`,
/// `- [ ] to-do`, **bold** inline). Bullets under a "Next steps" or "Action items" heading are to-dos.
/// With `onToggle`, ticking a to-do hands back its line so the caller can save it.
struct GranolaNotes: View {
    let markdown: String
    var onToggle: ((Int) -> Void)? = nil

    private enum Kind: Hashable { case heading(String), bullet(String, depth: Int), todo(String, done: Bool, depth: Int), text(String) }
    private struct Line: Hashable { let index: Int; let kind: Kind }

    private var lines: [Line] {
        var out: [Line] = []
        var inSteps = false
        for (i, raw) in markdown.components(separatedBy: "\n").enumerated() {
            if let k = Self.parse(raw, inSteps: inSteps) {
                if case .heading(let h) = k { inSteps = Self.isSteps(h) }
                out.append(Line(index: i, kind: k))
            }
        }
        return out
    }

    static func isSteps(_ h: String) -> Bool {
        let l = h.lowercased()
        return l.contains("next step") || l.contains("action item") || l.contains("to-do") || l.contains("todo")
    }

    private static func parse(_ raw: String, inSteps: Bool) -> Kind? {
        let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if t.hasPrefix("#") { return .heading(t.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)) }
        for marker in ["- ", "* ", "\u{2022} "] where t.hasPrefix(marker) {
            let body = String(t.dropFirst(marker.count))
            let depth = min(indent / 2, 2)
            if body.hasPrefix("[ ] ") { return .todo(String(body.dropFirst(4)), done: false, depth: depth) }
            if body.lowercased().hasPrefix("[x] ") { return .todo(String(body.dropFirst(4)), done: true, depth: depth) }
            return inSteps && depth == 0 ? .todo(body, done: false, depth: 0) : .bullet(body, depth: depth)
        }
        return .text(t)
    }

    /// Ticks or unticks the to-do on line `i`.
    static func toggle(line i: Int, in markdown: String) -> String {
        var rows = markdown.components(separatedBy: "\n")
        guard rows.indices.contains(i) else { return markdown }
        let raw = rows[i]
        let lead = String(raw.prefix { $0 == " " || $0 == "\t" })
        var t = raw.trimmingCharacters(in: .whitespaces)
        guard let marker = ["- ", "* ", "\u{2022} "].first(where: { t.hasPrefix($0) }) else { return markdown }
        t = String(t.dropFirst(marker.count))
        if t.hasPrefix("[ ] ") { t = "[x] " + t.dropFirst(4) }
        else if t.lowercased().hasPrefix("[x] ") { t = "[ ] " + t.dropFirst(4) }
        else { t = "[x] " + t }
        rows[i] = lead + "- " + t
        return rows.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.element) { n, line in
                switch line.kind {
                case .heading(let h):
                    Text(h).font(DF.font(22, .semibold)).tracking(-0.3).padding(.top, n == 0 ? 0 : 20).padding(.bottom, 2)
                case .bullet(let b, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Group {
                            if depth == 0 { Circle().fill(DF.ink) } else { Circle().strokeBorder(DF.ink, lineWidth: 1) }
                        }
                        .frame(width: 5, height: 5).offset(y: -3).frame(width: 14)
                        Text(Self.inline(b)).font(DF.font(16)).foregroundStyle(DF.ink)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(depth) * 24)
                case .todo(let b, let done, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button { onToggle?(line.index) } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(done ? DF.ink : .clear)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(done ? DF.ink : DF.ink.opacity(0.55), lineWidth: 1.4))
                                .overlay { if done { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
                                .frame(width: 15, height: 15).offset(y: 2)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(onToggle == nil)
                        Text(Self.inline(b)).font(DF.font(16))
                            .foregroundStyle(done ? DF.faint : DF.ink).strikethrough(done, color: DF.faint)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(depth) * 24)
                case .text(let t):
                    Text(Self.inline(t)).font(DF.font(16)).lineSpacing(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// Your next calendar meeting today: when it starts, and a switch to record it when it does.
private struct UpNextStrip: View {
    @EnvironmentObject var calendars: CalendarStore
    @ObservedObject private var meeting = MeetingService.shared
    @AppStorage("autoRecordIDs") private var autoRecordRaw = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            if let e = next(at: ctx.date) { strip(e, now: ctx.date) }
        }
    }

    private func next(at now: Date) -> CalEvent? {
        guard calendars.anyConnected else { return nil }
        return calendars.events(on: now).filter { !$0.isAllDay && $0.end > now && $0.start < now.addingTimeInterval(4 * 3600) }
            .min { $0.start < $1.start }
    }

    private func strip(_ e: CalEvent, now: Date) -> some View {
        let started = e.start <= now
        let mins = max(1, Int((e.start.timeIntervalSince(now) / 60).rounded(.up)))
        let auto = autoRecordRaw.split(separator: "|").contains(Substring(e.id))
        let when = started ? "Happening now" : mins < 60 ? "Up next \u{00B7} in \(mins) min" : "Up next \u{00B7} at \(e.start.formatted(date: .omitted, time: .shortened))"
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: e.colorHex == 0 ? 0x2F80ED : e.colorHex)).frame(width: 3, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(when).font(DF.font(13, .medium)).foregroundStyle(started ? DF.now : DF.muted)
                HStack(spacing: 8) {
                    Text(e.title).font(DF.font(15, .semibold)).lineLimit(1)
                    Text("\(e.start.formatted(date: .omitted, time: .shortened)) \u{2013} \(e.end.formatted(date: .omitted, time: .shortened)) \u{00B7} \(e.calendarTitle)")
                        .font(DF.font(14)).foregroundStyle(DF.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if started {
                if !meeting.isRecording {
                    Button { PillController.shared.toggleMeeting() } label: {
                        HStack(spacing: 7) { Circle().fill(DF.now).frame(width: 7, height: 7); Text("Record now") }
                    }
                    .buttonStyle(.df(.secondary, height: 30))
                }
            } else {
                Button {
                    var ids = Set(autoRecordRaw.split(separator: "|").map(String.init))
                    if auto { ids.remove(e.id) } else { ids.insert(e.id) }
                    autoRecordRaw = ids.joined(separator: "|")
                } label: {
                    if auto { Label("Records when it starts", systemImage: "checkmark") } else { Text("Record when it starts") }
                }
                .buttonStyle(.df(.secondary, height: 30))
                .help(auto ? "Click to stop recording this one automatically" : "Oatmeal starts taking notes when the meeting starts")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(DF.canvas, in: RoundedRectangle(cornerRadius: 8))
    }
}
