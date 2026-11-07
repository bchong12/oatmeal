import XCTest
import SwiftData
@testable import Oatmeal

/// Finder-style folders: nesting, moving, and what deleting a folder does to what it held.
@MainActor
final class MeetingFolderTests: XCTestCase {
    // The container has to outlive the context: a context whose container is gone traps on fetch.
    private var container: ModelContainer!

    private func context() throws -> ModelContext {
        let (c, ctx) = try makeContext()
        container = c
        return ctx
    }

    func testNestingAndPath() throws {
        let ctx = try context()
        let clients = MeetingFolders.create("Clients", in: nil, ctx: ctx)
        let acme = MeetingFolders.create("Acme", in: clients.id, ctx: ctx)
        let all = MeetingFolders.all(ctx)
        XCTAssertEqual(MeetingFolders.children(of: nil, in: all).map(\.name), ["Clients"])
        XCTAssertEqual(MeetingFolders.children(of: clients.id, in: all).map(\.name), ["Acme"])
        XCTAssertEqual(MeetingFolders.path(to: acme.id, in: all).map(\.name), ["Clients", "Acme"])
        XCTAssertTrue(MeetingFolders.isInside(acme.id, clients.id, in: all))
        XCTAssertFalse(MeetingFolders.isInside(clients.id, acme.id, in: all))
    }

    func testNewFolderNamesDontClash() throws {
        let ctx = try context()
        XCTAssertEqual(MeetingFolders.create(in: nil, ctx: ctx).name, "Untitled folder")
        XCTAssertEqual(MeetingFolders.create(in: nil, ctx: ctx).name, "Untitled folder 2")
        // Names only need to be unique next to each other, like Finder.
        let parent = MeetingFolders.create("Team", in: nil, ctx: ctx)
        XCTAssertEqual(MeetingFolders.create(in: parent.id, ctx: ctx).name, "Untitled folder")
    }

    func testAFolderCantGoInsideItself() throws {
        let ctx = try context()
        let clients = MeetingFolders.create("Clients", in: nil, ctx: ctx)
        let acme = MeetingFolders.create("Acme", in: clients.id, ctx: ctx)
        XCTAssertFalse(MeetingFolders.moveFolder(clients, into: acme.id, ctx: ctx))
        XCTAssertFalse(MeetingFolders.moveFolder(clients, into: clients.id, ctx: ctx))
        XCTAssertNil(clients.parentID)
        XCTAssertTrue(MeetingFolders.moveFolder(acme, into: nil, ctx: ctx))
        XCTAssertNil(acme.parentID)
    }

    func testDroppingMeetingsAndFolders() throws {
        let ctx = try context()
        let clients = MeetingFolders.create("Clients", in: nil, ctx: ctx)
        let team = MeetingFolders.create("Team", in: nil, ctx: ctx)
        let note = MeetingNote(title: "Pricing review", startedAt: date(2026, 11, 6, 10))
        ctx.insert(note)
        XCTAssertTrue(MeetingFolders.drop([MeetingFolders.payload(note), MeetingFolders.payload(team)], into: clients.id, ctx: ctx))
        XCTAssertEqual(note.folderID, clients.id)
        XCTAssertEqual(team.parentID, clients.id)
        // Dropping where it already is changes nothing.
        XCTAssertFalse(MeetingFolders.drop([MeetingFolders.payload(note)], into: clients.id, ctx: ctx))
        XCTAssertEqual(MeetingFolders.meetingCount(in: clients.id, notes: [note], folders: MeetingFolders.all(ctx)), 1)
    }

    func testDeletingAFolderKeepsWhatWasInside() throws {
        let ctx = try context()
        let clients = MeetingFolders.create("Clients", in: nil, ctx: ctx)
        let acme = MeetingFolders.create("Acme", in: clients.id, ctx: ctx)
        let inner = MeetingFolders.create("Q4", in: acme.id, ctx: ctx)
        let note = MeetingNote(title: "Kickoff", startedAt: date(2026, 11, 2, 9))
        ctx.insert(note)
        MeetingFolders.move([note], to: acme.id, in: ctx)

        MeetingFolders.delete(acme, in: ctx)
        let notes = try ctx.fetch(FetchDescriptor<MeetingNote>())
        XCTAssertEqual(notes.count, 1, "deleting a folder never deletes meetings")
        XCTAssertEqual(note.folderID, clients.id)
        XCTAssertEqual(inner.parentID, clients.id)
        XCTAssertEqual(MeetingFolders.all(ctx).map(\.name).sorted(), ["Clients", "Q4"])
    }

    func testMeetingInADeletedFolderShowsAtTheTop() throws {
        let ctx = try context()
        let note = MeetingNote(title: "Orphan", startedAt: date(2026, 11, 1))
        note.folderID = UUID()
        ctx.insert(note)
        XCTAssertNil(MeetingFolders.home(of: note, in: MeetingFolders.all(ctx)))
    }
}
