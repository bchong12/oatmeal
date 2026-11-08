import Foundation
import SwiftData

/// Who can write a meeting's notes: the AI CLIs on this Mac, each on the user's own plan, or
/// Oatmeal AI, which the connected site runs for Pro members.
enum NoteWriterKind: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, gemini, oatmeal
    var id: String { rawValue }
    /// The ones that run as a command on this Mac.
    static var clis: [NoteWriterKind] { [.claude, .codex, .gemini] }
    var title: String {
        switch self { case .claude: "Claude Code"; case .codex: "Codex"; case .gemini: "Gemini CLI"; case .oatmeal: "Oatmeal AI" }
    }
    var command: String { rawValue }
    var plan: String {
        switch self {
        case .claude: "your Claude plan"
        case .codex: "your ChatGPT plan"
        case .gemini: "your Google account"
        case .oatmeal: "your Pro plan"
        }
    }
    /// Brand tile in Resources/Brand.
    var logo: String {
        switch self { case .claude: "ai-claude"; case .codex: "ai-chatgpt"; case .gemini: "ai-gemini"; case .oatmeal: "mark" }
    }
    var installHint: String {
        switch self {
        case .claude: "npm i -g @anthropic-ai/claude-code"
        case .codex: "npm i -g @openai/codex"
        case .gemini: "npm i -g @google/gemini-cli"
        case .oatmeal: "Part of Pro, nothing to install"
        }
    }
}

/// Writes a meeting's notes once the meeting is saved, so nobody has to paste the "Create notes"
/// prompt. Runs Claude Code, Codex or Gemini CLI headless on this Mac, signed in with the user's own
/// plan, and lets it reach only Oatmeal's MCP tools for reading and updating meetings.
@MainActor
final class NoteWriters: ObservableObject {
    static let shared = NoteWriters()

    /// Meetings being written right now.
    @Published private(set) var running: Set<UUID> = []
    /// Why the last try failed, per meeting.
    @Published private(set) var errors: [UUID: String] = [:]
    /// Where each CLI lives; missing until looked up, "" when it isn't installed.
    @Published private(set) var paths: [NoteWriterKind: String] = [:]
    @Published private(set) var lookedUp = false

    static let enabledKey = "notes.auto"
    static let writerKey = "notes.writer"
    var autoEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey); objectWillChange.send() }
    }

    /// The writer the user picked, if any.
    var preferred: NoteWriterKind? {
        get { UserDefaults.standard.string(forKey: Self.writerKey).flatMap(NoteWriterKind.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: Self.writerKey); objectWillChange.send() }
    }

    func isInstalled(_ k: NoteWriterKind) -> Bool {
        k == .oatmeal ? OatmealAccount.shared.me?.oatmealAI == true : !(paths[k] ?? "").isEmpty
    }

    /// The picked writer if it's ready, else the first CLI found, else Oatmeal AI.
    var active: NoteWriterKind? {
        if let p = preferred, isInstalled(p) { return p }
        return NoteWriterKind.clis.first(where: isInstalled) ?? (isInstalled(.oatmeal) ? .oatmeal : nil)
    }

    var available: Bool { active != nil }

    private init() { Task { await locateAll() } }

    /// What the writer is asked to do: the same prompt the Create notes button copies.
    static func prompt(for note: MeetingNote) -> String {
        """
        Use the Oatmeal MCP to create the notes for my meeting "\(note.title)" (\(note.startedAt.formatted(date: .abbreviated, time: .shortened)), id \(note.id.uuidString)).

        1. Call get_meeting with that id. Read the whole transcript and my own notes.
        2. Fix the transcript: correct mis-heard words, names, product names and jargon, and wrong speaker labels (You is me, Them is the call). Use my notes and the rest of the conversation for context. Don't add anything that wasn't said. Save the fixes with update_meeting transcript_edits, using the #numbers from get_meeting.
        3. Write Granola-style notes and save them with one update_meeting call:
           - title: short and specific, 2 to 6 words, from what was discussed.
           - notes: 2 to 6 topic sections in meeting order, each "### Short topic" then 2 to 6 terse "- " bullets. Fragments, not sentences. Keep names, numbers, dates, prices and decisions exact. Build the sections around what I wrote in my notes.
           - End the notes with a "### Next steps" section: one clear task per bullet, starting with a verb, with owner and date only if they were said. Skip it if nothing was agreed.
           - summary: 1 to 3 short lines with the gist.
           Leave my own notes alone.
        4. Reply with a two-line recap of what you changed.
        """
    }

    /// Called when a meeting is saved: writes its notes if that's switched on and there's something to write from.
    func meetingSaved(_ note: MeetingNote) {
        guard autoEnabled, note.notesMarkdown.isEmpty, !note.transcriptData.isEmpty else { return }
        run(note)
    }

    /// Meetings waiting their turn: one meeting's notes at a time.
    private var queue: [(id: UUID, prompt: String)] = []
    private var busy = false

    /// Queues the active writer on this meeting. Its notes appear in Oatmeal as soon as it saves them over MCP.
    func run(_ note: MeetingNote) {
        let id = note.id
        guard !running.contains(id) else { return }
        guard let kind = active else {
            errors[id] = OatmealAccount.shared.site == nil
                ? "Install Claude Code, Codex or Gemini CLI to write notes on your own plan."
                : "Install Claude Code, Codex or Gemini CLI, or get Oatmeal AI with Pro."
            return
        }
        guard kind == .oatmeal || MCPServer.shared.isRunning else { errors[id] = "Oatmeal\u{2019}s MCP server is off (Settings \u{203A} MCP)."; return }
        errors[id] = nil
        running.insert(id)
        queue.append((id, Self.prompt(for: note)))
        next()
    }

    private func next() {
        guard !busy, !queue.isEmpty, let kind = active else { return }
        if kind == .oatmeal { return nextHosted() }
        guard let path = paths[kind] else { return }
        busy = true
        let (id, prompt) = queue.removeFirst()
        DFLog.log("notes", "\(kind.title) writing notes for \(id.uuidString) (\(queue.count) waiting)")
        let job = Self.job(kind, prompt: prompt, url: MCPSettingsTab.url)
        Task.detached(priority: .utility) {
            let outcome = Self.execute(kind, path, job.args, cwd: job.cwd)
            await MainActor.run {
                let me = NoteWriters.shared
                me.running.remove(id)
                // A clean exit isn't proof: a CLI that never reached update_meeting still exits 0.
                var outcome = outcome
                if case .success = outcome, me.notesMissing(id) {
                    outcome = .failure("\(kind.title) finished without saving notes. Try again, or pick another writer in Settings.")
                }
                if case .failure(let reason) = outcome {
                    me.errors[id] = reason
                    DFLog.log("notes", "\(kind.title) failed for \(id.uuidString): \(reason)")
                } else {
                    DFLog.log("notes", "\(kind.title) wrote notes for \(id.uuidString)")
                }
                me.busy = false
                me.next()
            }
        }
    }

    /// Oatmeal AI: the connected site writes the notes and they're saved here, no MCP involved.
    private func nextHosted() {
        busy = true
        let (id, _) = queue.removeFirst()
        DFLog.log("notes", "Oatmeal AI writing notes for \(id.uuidString) (\(queue.count) waiting)")
        Task { @MainActor in
            var failure: String?
            if let note = Self.note(id) {
                let segments = (try? JSONDecoder().decode([TranscriptSegment].self, from: note.transcriptData)) ?? []
                do {
                    let written = try await OatmealAccount.shared.writeNotes(
                        title: note.title, startedAt: note.startedAt, attendees: note.attendees,
                        transcript: segments.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n"), myNotes: note.myNotes)
                    note.notesMarkdown = written.notes
                    if !written.title.isEmpty { note.title = written.title }
                    if !written.summary.isEmpty { note.summary = written.summary }
                    try? AppModel.shared.context.save()
                } catch {
                    failure = (error as? OatmealAccount.AccountError)?.message ?? "Sign in again in Settings \u{203A} General."
                }
            } else {
                failure = "That meeting was deleted."
            }
            running.remove(id)
            if let failure {
                errors[id] = failure
                DFLog.log("notes", "Oatmeal AI failed for \(id.uuidString): \(failure)")
            } else {
                DFLog.log("notes", "Oatmeal AI wrote notes for \(id.uuidString)")
            }
            busy = false
            next()
        }
    }

    private static func note(_ id: UUID) -> MeetingNote? {
        try? AppModel.shared.context.fetch(FetchDescriptor<MeetingNote>(predicate: #Predicate { $0.id == id })).first
    }

    private func notesMissing(_ id: UUID) -> Bool {
        let context = AppModel.shared.context
        context.processPendingChanges()
        let note = try? context.fetch(FetchDescriptor<MeetingNote>(predicate: #Predicate { $0.id == id })).first
        return note?.notesMarkdown.isEmpty ?? false
    }

    /// The command line for each CLI, with only Oatmeal's two meeting tools reachable.
    nonisolated static func job(_ kind: NoteWriterKind, prompt: String, url: String) -> (args: [String], cwd: URL) {
        let tmp = FileManager.default.temporaryDirectory
        switch kind {
        case .claude:
            let mcp = #"{"mcpServers":{"oatmeal":{"type":"http","url":"\#(url)"}}}"#
            return (["-p", prompt,
                     "--mcp-config", mcp, "--strict-mcp-config",
                     "--allowedTools", "mcp__oatmeal__get_meeting mcp__oatmeal__update_meeting",
                     "--model", "sonnet", "--output-format", "json"], tmp)
        case .codex:
            // Headless Codex refuses MCP calls that would need a prompt, so Oatmeal's tools are pre-approved.
            // The sandbox stays read-only for everything else.
            return (["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only",
                     "-c", #"mcp_servers.oatmeal.url="\#(url)""#,
                     "-c", #"mcp_servers.oatmeal.default_tools_approval_mode="approve""#,
                     "-c", #"approval_policy="never""#,
                     prompt], tmp)
        case .oatmeal:
            return ([], tmp)   // Runs on the site, not as a command (see nextHosted).
        case .gemini:
            // Gemini reads MCP servers from .gemini/settings.json in its working folder. Shell and file
            // tools are switched off, so auto-approving only lets it use Oatmeal's meeting tools.
            let dir = tmp.appendingPathComponent("oatmeal-gemini", isDirectory: true)
            let cfg = dir.appendingPathComponent(".gemini", isDirectory: true)
            try? FileManager.default.createDirectory(at: cfg, withIntermediateDirectories: true)
            let settings = #"{"mcpServers":{"oatmeal":{"httpUrl":"\#(url)","trust":true}},"excludeTools":["run_shell_command","write_file","replace","web_fetch"]}"#
            try? settings.write(to: cfg.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
            // Gemini drops yolo back to prompting in an untrusted folder; --skip-trust trusts only this temp folder, this run.
            return (["-p", prompt, "--approval-mode", "yolo", "--skip-trust", "--allowed-mcp-server-names", "oatmeal", "-o", "json"], dir)
        }
    }

    enum Outcome { case success, failure(String) }

    /// Runs the CLI and waits (up to 15 minutes). A GUI app gets a bare PATH, so Homebrew's, npm's and
    /// the usual install folders go first; the npm builds need `node` from there.
    nonisolated private static func execute(_ kind: NoteWriterKind, _ path: String, _ args: [String], cwd: URL) -> Outcome {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.claude/local",
                       env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        p.environment = env
        p.currentDirectoryURL = cwd
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .failure("Couldn\u{2019}t start \(kind.title): \(error.localizedDescription)") }
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15 * 60, execute: timeout)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        timeout.cancel()
        return outcome(kind, status: p.terminationStatus, stdout: data, stderr: errText)
    }

    nonisolated static func outcome(_ kind: NoteWriterKind, status: Int32, stdout: Data, stderr: String) -> Outcome {
        // Claude: `{ "is_error": Bool, "result": String }`. Gemini: `{ "response": ..., "error": {...} }`.
        if let json = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any] {
            if json["is_error"] as? Bool == true {
                return .failure((json["result"] as? String).map { String($0.prefix(200)) } ?? "\(kind.title) stopped with an error.")
            }
            if let e = json["error"] as? [String: Any], let m = e["message"] as? String { return .failure(String(m.prefix(200))) }
        }
        if status == 0 { return .success }
        let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = reason.lowercased()
        if lower.contains("login") || lower.contains("auth") || lower.contains("sign in") {
            return .failure("\(kind.title) isn\u{2019}t signed in. Run `\(kind.command)` in Terminal once to sign in.")
        }
        return .failure(reason.isEmpty ? "\(kind.title) stopped (exit \(status))." : String(reason.suffix(200)))
    }

    /// Finds each CLI in the usual places, then asks a login shell (which has the user's PATH).
    func locateAll() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: [NoteWriterKind: String] = [:]
        for k in NoteWriterKind.clis {
            let c = k.command
            let known = ["/opt/homebrew/bin/\(c)", "/usr/local/bin/\(c)", "\(home)/.local/bin/\(c)", "\(home)/.npm-global/bin/\(c)", "\(home)/.claude/local/\(c)"]
            if let hit = known.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { found[k] = hit; continue }
            found[k] = await Task.detached(priority: .utility) { () -> String in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", "command -v \(c)"]
                let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
                guard (try? p.run()) != nil else { return "" }
                let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit()
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }.value
        }
        paths = found
        lookedUp = true
    }
}
