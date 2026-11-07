import SwiftUI
import SwiftData

/// Folders, Finder-style: they nest, meetings and folders drag between them, and deleting one hands
/// what it held to the folder above. Shared by the sidebar, the meetings list, the detail and MCP.
@MainActor
enum MeetingFolders {
    static func all(_ ctx: ModelContext) -> [MeetingFolder] {
        sorted((try? ctx.fetch(FetchDescriptor<MeetingFolder>())) ?? [])
    }

    static func sorted(_ folders: [MeetingFolder]) -> [MeetingFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The folders directly inside `parent` (nil = the top level). A folder whose parent is gone counts as top level.
    static func children(of parent: UUID?, in folders: [MeetingFolder]) -> [MeetingFolder] {
        let ids = Set(folders.map(\.id))
        return sorted(folders.filter { f in
            let p = f.parentID.flatMap { ids.contains($0) ? $0 : nil }
            return p == parent
        })
    }

    /// From the top level down to `id`.
    static func path(to id: UUID?, in folders: [MeetingFolder]) -> [MeetingFolder] {
        var out: [MeetingFolder] = []
        var cur = id
        while let c = cur, let f = folders.first(where: { $0.id == c }), !out.contains(where: { $0.id == f.id }) {
            out.insert(f, at: 0)
            cur = f.parentID
        }
        return out
    }

    /// True when `id` is `ancestor` or sits somewhere inside it.
    static func isInside(_ id: UUID?, _ ancestor: UUID, in folders: [MeetingFolder]) -> Bool {
        path(to: id, in: folders).contains { $0.id == ancestor }
    }

    /// The folder a meeting lives in, treating a deleted folder as the top level.
    static func home(of note: MeetingNote, in folders: [MeetingFolder]) -> UUID? {
        note.folderID.flatMap { id in folders.contains { $0.id == id } ? id : nil }
    }

    /// Meetings in this folder and every folder inside it.
    static func meetingCount(in id: UUID, notes: [MeetingNote], folders: [MeetingFolder]) -> Int {
        notes.filter { n in n.folderID.map { isInside($0, id, in: folders) } ?? false }.count
    }

    /// The folder with this name (case-insensitive, any level), made at the top level if it doesn't exist. For MCP.
    @discardableResult
    static func named(_ raw: String, in ctx: ModelContext) -> MeetingFolder? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let f = all(ctx).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return f }
        let f = MeetingFolder(name: String(name.prefix(60)))
        ctx.insert(f)
        try? ctx.save()
        return f
    }

    /// A new folder inside `parent`, named "Untitled folder" (or "… 2") unless a name is given.
    @discardableResult
    static func create(_ name: String? = nil, in parent: UUID?, ctx: ModelContext) -> MeetingFolder {
        let siblings = Set(children(of: parent, in: all(ctx)).map { $0.name.lowercased() })
        var base = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "Untitled folder" }
        var final = String(base.prefix(60)), i = 2
        while siblings.contains(final.lowercased()) { final = "\(base) \(i)"; i += 1 }
        let f = MeetingFolder(name: final, parentID: parent)
        withAnimation(.snappy) { ctx.insert(f) }
        try? ctx.save()
        return f
    }

    static func rename(_ f: MeetingFolder, to raw: String, ctx: ModelContext) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        f.name = String(name.prefix(60))
        try? ctx.save()
    }

    static func move(_ note: MeetingNote, to folder: MeetingFolder?, in ctx: ModelContext) {
        move([note], to: folder?.id, in: ctx)
    }

    static func move(_ notes: [MeetingNote], to folder: UUID?, in ctx: ModelContext) {
        withAnimation(.snappy) { for n in notes { n.folderID = folder } }
        try? ctx.save()
    }

    /// Puts a folder inside another (nil = top level). Refuses to put a folder inside itself.
    @discardableResult
    static func moveFolder(_ f: MeetingFolder, into parent: UUID?, ctx: ModelContext) -> Bool {
        if let parent, isInside(parent, f.id, in: all(ctx)) { return false }
        guard f.parentID != parent else { return false }
        withAnimation(.snappy) { f.parentID = parent }
        try? ctx.save()
        return true
    }

    /// Deletes the folder; its meetings and folders move up to where it was.
    static func delete(_ folder: MeetingFolder, in ctx: ModelContext) {
        let id = folder.id, up = folder.parentID
        withAnimation(.snappy) {
            for n in (try? ctx.fetch(FetchDescriptor<MeetingNote>())) ?? [] where n.folderID == id { n.folderID = up }
            for f in all(ctx) where f.parentID == id { f.parentID = up }
            ctx.delete(folder)
        }
        try? ctx.save()
    }

    // MARK: Dragging

    static func payload(_ note: MeetingNote) -> String { "meeting:" + note.id.uuidString }
    static func payload(_ folder: MeetingFolder) -> String { "folder:" + folder.id.uuidString }

    /// Files dragged meetings and folders into `target` (nil = top level). True if anything moved.
    static func drop(_ payloads: [String], into target: UUID?, ctx: ModelContext) -> Bool {
        let notes = (try? ctx.fetch(FetchDescriptor<MeetingNote>())) ?? []
        let folders = all(ctx)
        var moved = false
        for p in payloads {
            if p.hasPrefix("meeting:"), let id = UUID(uuidString: String(p.dropFirst(8))), let n = notes.first(where: { $0.id == id }) {
                if n.folderID != target { move([n], to: target, in: ctx); moved = true }
            } else if p.hasPrefix("folder:"), let id = UUID(uuidString: String(p.dropFirst(7))), let f = folders.first(where: { $0.id == id }) {
                if moveFolder(f, into: target, ctx: ctx) { moved = true }
            }
        }
        return moved
    }

    // MARK: Menus

    /// Right-click on a folder (sidebar or list).
    static func menu(for f: MeetingFolder, model: AppModel, inSidebar: Bool) -> [DFMenuItem] {
        let ctx = model.context
        return [
            .action("Open", icon: "folder") { model.go(.folder(f.id)) },
            .action("New folder inside", icon: "folder.badge.plus") {
                let new = create(in: f.id, ctx: ctx)
                model.expandedFolders.insert(f.id)
                model.startRenaming(new, inSidebar: inSidebar)
            },
            .action("Rename", icon: "pencil") { model.startRenaming(f, inSidebar: inSidebar) },
            .submenu("Move to", icon: "arrow.turn.down.right", destinations(model: model, excluding: f) { dest in
                moveFolder(f, into: dest, ctx: ctx)
            }),
            .divider,
            .action("Delete folder", icon: "trash", destructive: true) { confirmDelete(f, model: model) },
        ]
    }

    static func confirmDelete(_ f: MeetingFolder, model: AppModel) {
        let ctx = model.context
        let folders = all(ctx)
        let notes = (try? ctx.fetch(FetchDescriptor<MeetingNote>())) ?? []
        let inside = notes.filter { $0.folderID == f.id }.count + children(of: f.id, in: folders).count
        let up = path(to: f.parentID, in: folders).last?.name ?? "Meetings"
        let leave = {
            if case .folder(let at) = model.place, let at, isInside(at, f.id, in: folders) { model.go(.folder(f.parentID)) }
            delete(f, in: ctx)
        }
        guard inside > 0 else { leave(); return }
        Popups.shared.confirm("Delete \u{201C}\(f.name)\u{201D}?",
                              "The \(inside == 1 ? "item" : "\(inside) items") inside move to \u{201C}\(up)\u{201D}. No meetings are deleted.",
                              confirm: "Delete folder", destructive: true, leave)
    }

    /// Every place something can be moved to: Meetings, then the folder tree, then a new folder.
    static func destinations(model: AppModel, excluding: MeetingFolder? = nil, current: UUID?? = nil,
                             _ move: @escaping (UUID?) -> Void) -> [DFMenuItem] {
        let ctx = model.context
        let folders = all(ctx)
        var items: [DFMenuItem] = [.action("Meetings", icon: "tray", checked: current == .some(nil)) { move(nil) }]
        func add(_ parent: UUID?, depth: Int) {
            for f in children(of: parent, in: folders) {
                if let ex = excluding, f.id == ex.id { continue }
                let indent = String(repeating: "    ", count: depth)
                items.append(.action(indent + f.name, icon: "folder", checked: current == .some(f.id)) { move(f.id) })
                add(f.id, depth: depth + 1)
            }
        }
        add(nil, depth: 0)
        items.append(.divider)
        items.append(.action("New folder\u{2026}", icon: "folder.badge.plus") {
            Popups.shared.prompt("New folder", placeholder: "Folder name", confirm: "Create and move") { name in
                move(create(name, in: nil, ctx: ctx).id)
            }
        })
        return items
    }
}

/// The folder chip under a meeting's title: shows where it's filed and moves it.
struct MeetingFolderChip: View {
    let note: MeetingNote
    @EnvironmentObject var model: AppModel
    @Query private var folders: [MeetingFolder]
    @State private var frame: CGRect = .zero
    @State private var hover = false

    var body: some View {
        let home = MeetingFolders.home(of: note, in: folders)
        let name = MeetingFolders.path(to: home, in: folders).map(\.name).joined(separator: " / ")
        Button {
            Popups.shared.showMenu(MeetingFolders.destinations(model: model, current: .some(home)) { dest in
                MeetingFolders.move([note], to: dest, in: model.context)
            }, below: frame, width: 240)
        } label: {
            HStack(spacing: 5) {
                FolderGlyph(size: 13)
                Text(name.isEmpty ? "Meetings" : name).font(DF.font(13, .medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(DF.faint)
            }
            .foregroundStyle(DF.muted)
            .padding(.horizontal, 7).frame(height: 24)
            .background(hover ? DF.wash.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .popupAnchor($frame)
        .help("Move to another folder")
    }
}

/// Oatmeal's folder icon: a honey folder with a darker tab.
struct FolderGlyph: View {
    var size: CGFloat = 16
    var open = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(DF.honeyDeep.opacity(0.75))
                .frame(width: size * 0.46, height: size * 0.3)
                .offset(y: size * 0.1)
            RoundedRectangle(cornerRadius: size * 0.14)
                .fill(LinearGradient(colors: [Color(hex: 0xF8D98C), DF.honey], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: size * 0.14).strokeBorder(DF.honeyDeep.opacity(0.55), lineWidth: 0.75))
                .frame(width: size, height: size * 0.68)
                .offset(y: size * 0.22)
        }
        .frame(width: size, height: size * 0.9, alignment: .topLeading)
    }
}
