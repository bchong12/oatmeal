import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(compact: model.sidebarCollapsed)
            Rectangle().fill(DF.line).frame(width: 1)
            VStack(spacing: 0) {
                TopBar()
                Group {
                    switch model.section {
                    case .meetings: MeetingsView()
                    case .dictation: DictationView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .id(model.section)
            }
            .animation(.easeOut(duration: 0.18), value: model.section)
        }
        .overlay { PopupLayer() }
        .coordinateSpace(.named(Popups.space))
        .background(DF.paper)
        .ignoresSafeArea(.container, edges: .top)   // top bar sits on the window-button line
        .font(DF.font(14))
        .foregroundStyle(DF.ink)
        .tint(DF.ink)
    }
}

// MARK: - Sidebar

/// Finder-style sidebar: the logo and record button, the places (Recent, Meetings, Flow), the folder
/// tree, then Settings and the needs-you bell. Collapses to a slim rail of icons.
private struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var meeting = MeetingService.shared
    @Query private var folders: [MeetingFolder]
    @Query private var notes: [MeetingNote]
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BrandMark(size: 24)
                if !compact { Text("oatmeal").font(DF.serif(24)).tracking(-0.4) }
            }
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .padding(.horizontal, compact ? 0 : 6)
            .padding(.top, 48).padding(.bottom, 16)

            RecordButton(compact: compact, recording: meeting.isRecording, elapsed: meeting.elapsed)
                .padding(.bottom, 18)

            VStack(spacing: 1) {
                SidebarRow(icon: "clock", title: "Recent", compact: compact,
                           selected: model.section == .meetings && model.place == .recent) { model.go(.recent) }
                SidebarRow(icon: "tray", title: "Meetings", count: notes.count, compact: compact,
                           selected: model.section == .meetings && model.place == .folder(nil),
                           drop: { MeetingFolders.drop($0, into: nil, ctx: model.context) }) { model.go(.folder(nil)) }
                SidebarRow(icon: "waveform", title: "Flow", compact: compact, selected: model.section == .dictation) {
                    withAnimation(.snappy(duration: 0.22)) { model.section = .dictation }
                }
            }

            if !compact {
                FolderTree(folders: folders, notes: notes).padding(.top, 22)
            }

            Spacer(minLength: 12)
            HStack(spacing: 4) {
                SidebarRow(icon: "gearshape", title: "Settings", compact: compact, selected: model.section == .settings) {
                    withAnimation(.snappy(duration: 0.22)) { model.section = .settings }
                }
                .help("Settings (\u{2318},)")
                if !compact { NotificationBell() }
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, compact ? 10 : 12)
        .frame(width: compact ? 64 : 240)
        .background(Color(hex: 0xF5F0E3))
    }
}

/// One place in the sidebar. Rows that hold meetings take drops.
private struct SidebarRow: View {
    let icon: String
    let title: String
    var count: Int? = nil
    let compact: Bool
    let selected: Bool
    var drop: (([String]) -> Bool)? = nil
    let action: () -> Void
    @State private var hover = false
    @State private var targeted = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? DF.ink : DF.muted).frame(width: 18)
                if !compact {
                    Text(title).font(DF.font(14, selected ? .semibold : .medium)).foregroundStyle(selected ? DF.ink : Color(hex: 0x4A443B))
                    Spacer(minLength: 4)
                    if let count, count > 0 { Text("\(count)").font(DF.font(12, .medium)).foregroundStyle(DF.faint).monospacedDigit() }
                }
            }
            .padding(.horizontal, compact ? 0 : 8).frame(maxWidth: compact ? 44 : .infinity).frame(height: 30)
            .background(SidebarHighlight(selected: selected, hover: hover, targeted: targeted))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .modifier(OptionalDrop(drop: drop, targeted: $targeted))
        .help(compact ? title : "")
    }
}

/// Selected rows sit on paper with a hairline; hover is a soft wash; a drop target glows honey.
private struct SidebarHighlight: View {
    let selected: Bool
    let hover: Bool
    var targeted = false
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(targeted ? DF.honey.opacity(0.45) : selected ? DF.paper : hover ? Color(hex: 0xEBE4D2) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? DF.honeyDeep : selected ? DF.line : .clear, lineWidth: targeted ? 1.5 : 1))
            .shadow(color: selected ? Color(hex: 0x3B2A20).opacity(0.06) : .clear, radius: 2, y: 1)
    }
}

private struct OptionalDrop: ViewModifier {
    let drop: (([String]) -> Bool)?
    @Binding var targeted: Bool
    func body(content: Content) -> some View {
        if let drop {
            content.dropDestination(for: String.self) { items, _ in drop(items) } isTargeted: { t in
                withAnimation(.easeOut(duration: 0.12)) { targeted = t }
            }
        } else {
            content
        }
    }
}

/// "Folders" and the tree under it, with a + to make one.
private struct FolderTree: View {
    @EnvironmentObject var model: AppModel
    let folders: [MeetingFolder]
    let notes: [MeetingNote]
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("Folders").font(DF.font(12, .semibold)).foregroundStyle(DF.faint)
                Spacer()
                Button {
                    let f = MeetingFolders.create(in: nil, ctx: model.context)
                    model.startRenaming(f, inSidebar: true)
                } label: { Image(systemName: "plus") }
                .buttonStyle(.dfIcon(size: 22))
                .opacity(hover || folders.isEmpty ? 1 : 0)
                .help("New folder")
            }
            .padding(.leading, 8).padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 1) {
                    if folders.isEmpty {
                        Text("Make folders for clients, teams or projects, then drag meetings in.")
                            .font(DF.font(12)).foregroundStyle(DF.faint).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8).padding(.top, 2)
                    }
                    ForEach(rows, id: \.folder.id) { row in
                        FolderTreeRow(folder: row.folder, depth: row.depth,
                                      hasChildren: !MeetingFolders.children(of: row.folder.id, in: folders).isEmpty,
                                      count: MeetingFolders.meetingCount(in: row.folder.id, notes: notes, folders: folders))
                    }
                }
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }

    /// The tree flattened top to bottom, skipping inside closed folders.
    private var rows: [(folder: MeetingFolder, depth: Int)] {
        var out: [(MeetingFolder, Int)] = []
        func add(_ parent: UUID?, _ depth: Int) {
            for f in MeetingFolders.children(of: parent, in: folders) {
                out.append((f, depth))
                if model.expandedFolders.contains(f.id) { add(f.id, depth + 1) }
            }
        }
        add(nil, 0)
        return out
    }
}

private struct FolderTreeRow: View {
    @EnvironmentObject var model: AppModel
    let folder: MeetingFolder
    let depth: Int
    let hasChildren: Bool
    let count: Int
    @State private var hover = false
    @State private var targeted = false

    var body: some View {
        let open = model.expandedFolders.contains(folder.id)
        let selected = model.section == .meetings && model.place == .folder(folder.id)
        HStack(spacing: 5) {
            Group {
                if hasChildren {
                    Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold)).foregroundStyle(DF.faint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 14, height: 22).contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) {
                                if open { model.expandedFolders.remove(folder.id) } else { model.expandedFolders.insert(folder.id) }
                            }
                        }
                } else {
                    Color.clear.frame(width: 14)
                }
            }
            FolderGlyph(size: 15)
            if model.renaming?.id == folder.id && model.renaming?.inSidebar == true {
                FolderNameField(folder: folder)
            } else {
                Text(folder.name).font(DF.font(14, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? DF.ink : Color(hex: 0x4A443B)).lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 { Text("\(count)").font(DF.font(12, .medium)).foregroundStyle(DF.faint).monospacedDigit() }
            }
        }
        .padding(.leading, 2 + CGFloat(depth) * 14).padding(.trailing, 8)
        .frame(height: 30)
        .background(SidebarHighlight(selected: selected, hover: hover, targeted: targeted))
        .contentShape(Rectangle())
        .onTapGesture { model.go(.folder(folder.id)) }
        .onHover { hover = $0 }
        .draggable(MeetingFolders.payload(folder)) {
            HStack(spacing: 6) { FolderGlyph(size: 15); Text(folder.name).font(DF.font(13, .semibold)) }
                .padding(.horizontal, 10).frame(height: 30).background(DF.paper, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, _ in
            let moved = MeetingFolders.drop(items, into: folder.id, ctx: model.context)
            if moved && items.contains(where: { $0.hasPrefix("folder:") }) { model.expandedFolders.insert(folder.id) }
            return moved
        } isTargeted: { t in withAnimation(.easeOut(duration: 0.12)) { targeted = t } }
        .dfContextMenu { MeetingFolders.menu(for: folder, model: model, inSidebar: true) }
        .help(folder.name)
    }
}

/// Edits a folder's name in place: Return or clicking away saves, Esc cancels.
struct FolderNameField: View {
    @EnvironmentObject var model: AppModel
    let folder: MeetingFolder
    var size: CGFloat = 14
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var done = false

    var body: some View {
        TextField("Folder name", text: $text)
            .textFieldStyle(.plain).font(DF.font(size, .semibold))
            .focused($focused)
            .padding(.horizontal, 5).frame(height: 24)
            .background(DF.paper, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DF.honeyDeep, lineWidth: 1.5))
            .onAppear {
                text = folder.name
                DispatchQueue.main.async { focused = true }
            }
            .onSubmit(commit)
            .onExitCommand { done = true; model.renaming = nil }
            .onChange(of: focused) { _, f in if !f { commit() } }
    }

    private func commit() {
        guard !done else { return }
        done = true
        MeetingFolders.rename(folder, to: text, ctx: model.context)
        model.renaming = nil
    }
}

/// The honey button that starts (or stops) meeting notes.
private struct RecordButton: View {
    let compact: Bool
    let recording: Bool
    let elapsed: TimeInterval
    var body: some View {
        Button { PillController.shared.toggleMeeting() } label: {
            HStack(spacing: 8) {
                ZStack {
                    if recording {
                        RoundedRectangle(cornerRadius: 2).fill(DF.now).frame(width: 8, height: 8)
                    } else {
                        Circle().fill(DF.now).frame(width: 8, height: 8)
                    }
                }
                if !compact {
                    Text(recording ? "Stop \u{00B7} \(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))" : "Record a meeting")
                        .font(DF.font(14, .semibold)).monospacedDigit()
                }
            }
            .frame(maxWidth: compact ? 24 : .infinity)
        }
        .buttonStyle(.df(.honey, height: 36))
        .help("Right \u{2325} M from anywhere")
    }
}

// MARK: - Top bar

/// Sidebar toggle, back, and the path: "Meetings › Clients › Acme › Pricing review". Every folder in
/// the path opens on click and takes dropped meetings, like Finder's path bar.
struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @Query private var meetings: [MeetingNote]
    @Query private var folders: [MeetingFolder]

    private struct Crumb: Hashable { let title: String; let place: Place?; let folder: UUID?; let isFolder: Bool }

    private var crumbs: [Crumb] {
        guard model.section == .meetings else { return [Crumb(title: model.section.title, place: nil, folder: nil, isFolder: false)] }
        let open = meetings.first { $0.id == model.selectedMeetingID }
        var out: [Crumb] = []
        if model.place == .recent {
            out.append(Crumb(title: "Recent", place: .recent, folder: nil, isFolder: false))
        } else {
            let at: UUID? = open.map { MeetingFolders.home(of: $0, in: folders) } ?? { if case .folder(let f) = model.place { return f }; return nil }()
            out.append(Crumb(title: "Meetings", place: .folder(nil), folder: nil, isFolder: true))
            for f in MeetingFolders.path(to: at, in: folders) { out.append(Crumb(title: f.name, place: .folder(f.id), folder: f.id, isFolder: true)) }
        }
        if let open { out.append(Crumb(title: open.title, place: nil, folder: nil, isFolder: false)) }
        return out
    }

    private var canGoBack: Bool {
        guard model.section == .meetings else { return false }
        if model.selectedMeetingID != nil { return true }
        if case .folder(let f) = model.place { return f != nil }
        return false
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { model.toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.dfIcon())
                .help("Hide or show the sidebar (\u{2303}\u{2318}S)")
            Button { back() } label: { Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.dfIcon()).disabled(!canGoBack)
                .help("Back")
            Rectangle().fill(DF.line).frame(width: 1, height: 16).padding(.horizontal, 6)
            HStack(spacing: 2) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                    if i > 0 { Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold)).foregroundStyle(DF.faint).padding(.horizontal, 2) }
                    CrumbButton(title: c.title, isFolder: c.isFolder && c.folder != nil, last: i == crumbs.count - 1,
                                action: c.place.map { p in { model.go(p) } },
                                drop: c.isFolder ? { MeetingFolders.drop($0, into: c.folder, ctx: model.context) } : nil)
                }
            }
            Spacer()
            if model.section == .meetings {
                Button { model.setSidePanel(!model.sidePanelOpen) } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(.dfIcon(active: model.sidePanelOpen))
                    .help(model.sidePanelOpen ? "Hide today\u{2019}s meetings" : "Show today\u{2019}s meetings")
            }
        }
        .padding(.leading, model.sidebarCollapsed ? 24 : 14).padding(.trailing, 14).frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(DF.line).frame(height: 1) }
        .background(DF.paper)
        .animation(.easeOut(duration: 0.15), value: crumbs)
    }

    private func back() {
        if model.selectedMeetingID != nil { withAnimation(.snappy(duration: 0.22)) { model.selectedMeetingID = nil }; return }
        if case .folder(let f) = model.place, let f { model.go(.folder(folders.first { $0.id == f }?.parentID)) }
    }
}

private struct CrumbButton: View {
    let title: String
    let isFolder: Bool
    let last: Bool
    let action: (() -> Void)?
    let drop: (([String]) -> Bool)?
    @State private var hover = false
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 5) {
            if isFolder { FolderGlyph(size: 13) }
            Text(title).font(DF.font(13, last ? .semibold : .medium)).foregroundStyle(last ? DF.ink : DF.muted).lineLimit(1)
        }
        .padding(.horizontal, 6).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(targeted ? DF.honey.opacity(0.45) : (hover && action != nil && !last) ? DF.wash.opacity(0.8) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if !last { action?() } }
        .modifier(OptionalDrop(drop: drop, targeted: $targeted))
    }
}

// MARK: - Shared pieces

/// Shared header: big serif title, optional subtitle, actions on the right.
struct PageHeader<Actions: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(DF.serif(32)).tracking(-0.6).lineLimit(1).fixedSize()
            if !subtitle.isEmpty { Text(subtitle).font(DF.font(14)).foregroundStyle(DF.muted).lineLimit(1) }
            Spacer(minLength: 8)
            actions.fixedSize()
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 14)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String = "plus"
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol) }.buttonStyle(.df(.primary))
    }
}

struct SecondaryButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .buttonStyle(.df(.secondary))
    }
}

/// What currently needs the user: permissions and calendar. Drives the bell's dot and its menu.
@MainActor
func needsYouItems(model: AppModel, calendars: CalendarStore) -> [(icon: String, title: String, sub: String, action: () -> Void)] {
    var out: [(String, String, String, () -> Void)] = []
    if model.needsAccessibility {
        out.append(("keyboard", "Turn on Accessibility", "So right \u{2325} works in every app", { model.requestAccessibility() }))
    }
    if model.micStatus != .authorized {
        out.append(("mic", "Allow the microphone", "For dictation and meeting notes", {
            if model.micStatus == .notDetermined { model.requestMic() }
            else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
        }))
    }
    if !calendars.anyConnected {
        out.append(("calendar", "Connect your calendar", "See meetings and get reminders", { Task { await calendars.requestAccess() } }))
    }
    return out
}

/// Bell beside Settings: a dot when something needs you (permissions, calendar).
struct NotificationBell: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var calendars: CalendarStore
    @State private var frame: CGRect = .zero

    var body: some View {
        let list = needsYouItems(model: model, calendars: calendars)
        Button {
            var items: [DFMenuItem] = [.header(list.isEmpty ? "All set" : "Needs you")]
            if list.isEmpty {
                items.append(.action("Right \u{2325}, mic and calendar all work", icon: "checkmark.circle") {})
            }
            for item in list { items.append(.action(item.title, icon: item.icon, hint: nil, item.action)) }
            Popups.shared.showMenu(items, below: frame, width: 250)
        } label: {
            Image(systemName: "bell")
                .overlay(alignment: .topTrailing) {
                    if !list.isEmpty { Circle().fill(DF.now).frame(width: 7, height: 7).offset(x: 3, y: -2) }
                }
        }
        .buttonStyle(.dfIcon(size: 30))
        .popupAnchor($frame)
        .help(list.isEmpty ? "All set" : "Needs you")
    }
}

/// Centred empty state: the mark, a line, and a hint. Fills whatever space it's given.
struct EmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            BrandMark(size: 56)
            Text(title).font(DF.serif(22))
            Text(message).font(DF.font(14)).foregroundStyle(DF.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

/// Search field in the app's style.
struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(DF.faint)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(DF.font(14)).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.dfIcon(size: 20))
            }
        }
        .padding(.leading, 10).padding(.trailing, 5).frame(height: 32)
        .background(DF.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? DF.ink.opacity(0.5) : DF.line.opacity(1.6), lineWidth: focused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// × in the corner of a side panel.
struct PanelCloseButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button { model.setSidePanel(false) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
            .buttonStyle(.dfIcon(size: 26))
            .help("Close panel")
    }
}
