import SwiftUI
import AppKit
import SwiftData

enum DictationTarget { case app, task }

enum PillState: Equatable {
    case resting
    case listening(DictationTarget)
    case transcribing
    case confirmed(title: String, detail: String, taskID: UUID?)
    case meetingPrompt(String)
    case recording
    case saved(String, UUID)
    case typed(String)
    case notPasted(String)
}

/// Owns the floating pill: a non-activating panel pinned to the bottom of the
/// screen the pointer is on. It never takes focus, so dictated text lands in
/// whatever app you were using.
@MainActor
final class PillController: ObservableObject {
    static let shared = PillController()

    @Published private(set) var state: PillState = .resting
    @Published var expanded = false
    /// Recording, shrunk to a small dot you can tuck away.
    @Published private(set) var minimized = false
    /// Where the visible pill and cards are, in the stage's SwiftUI coordinates (top-left origin).
    /// Only this part takes clicks; the rest of the transparent stage lets them through.
    var hitRect: CGRect = .null
    @Published var target: DictationTarget = .app
    @Published private(set) var dismissedPromptFor: String?
    /// The app dictated text will land in (captured when listening starts).
    @Published private(set) var frontApp: NSRunningApplication?

    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var resetWork: DispatchWorkItem?
    private var promptTimer: Timer?
    private var meetingTitle = "Meeting"

    private var visible: Bool { UserDefaults.standard.object(forKey: "pillVisible") as? Bool ?? true }

    func start() {
        makePanel()
        let rk = RightOptionKey.shared
        rk.onHoldStart = { [weak self] in self?.startDictation(into: .app) }
        rk.onMakeTask = { [weak self] in self?.switchToTask() }
        rk.onHoldEnd = { [weak self] in Task { await self?.finishDictation() } }
        rk.onTap = { [weak self] in self?.toggleSurface() }
        rk.onMeeting = { [weak self] in self?.toggleMeeting() }
        rk.onDoubleTap = { [weak self] in self?.startHandsFree() }
        rk.onPasteLast = { [weak self] in self?.pasteLast() }
        rk.tapIsImmediate = { [weak self] in self?.handsFree == true }
        rk.onEscape = { [weak self] in
            guard let self else { return false }
            if case .notPasted = self.state { self.dismiss(); return true }
            guard case .listening = self.state else { return false }
            self.cancelDictation(); return true
        }
        // Under XCTest the app is only a host: real key presses would leak into the key tests.
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !testing, !rk.install() {
            // No Accessibility yet: fall back to ⌥Space so dictation still works,
            // and keep retrying the right-⌥ tap once permission is granted.
            HotkeyService.shared.onPress = { [weak self] in self?.startDictation(into: .app) }
            HotkeyService.shared.onRelease = { [weak self] in Task { await self?.finishDictation() } }
            HotkeyService.shared.onMeeting = { [weak self] in self?.toggleMeeting() }
            HotkeyService.shared.onOpen = { [weak self] in self?.toggleSurface() }
            HotkeyService.shared.install()
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { t in
                Task { @MainActor in
                    if RightOptionKey.shared.install() { HotkeyService.shared.uninstall(); t.invalidate() }
                }
            }
        }
        observeWindows()
        MeetingReminders.shared.start()
        Task { await DictationService.shared.prepareModel() }
        promptTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForMeeting() }
        }
        setVisible(visible)
        if let demo = UserDefaults.standard.string(forKey: "pill") { showDemo(demo) }
    }

    /// Dev-only: put the pill in a state without touching the mic (for screenshots).
    private func showDemo(_ name: String) {
        frontApp = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }
        switch name {
        case "listening": set(.listening(.app))
        case "handsfree": handsFree = true; set(.listening(.app))
        case "task": set(.listening(.task))
        case "typed": set(.typed("Sounds good, I\u{2019}ll send the revised quote by Friday and book a review next week."))
        case "confirmed": set(.confirmed(title: "Call mum", detail: "Fri · 5:00 pm · 30m", taskID: UUID()))
        case "prompt": set(.meetingPrompt("Client catch-up"))
        case "writing": set(.transcribing)
        case "saved": set(.saved("Notes saved", UUID()))
        case "notpasted": set(.notPasted("Sounds good, I\u{2019}ll send the revised quote by Friday and book a review next week."))
        case "mictest":
            // Records 3 s with the chosen mic and logs what came in (nothing is pasted).
            DictationService.shared.start()
            Task { try? await Task.sleep(for: .seconds(3)); _ = await DictationService.shared.stop() }
        default: break
        }
    }

    // MARK: Panel

    static let stage = NSSize(width: 520, height: 380)

    /// One id per kind of state, so SwiftUI cross-fades between them.
    var stateKey: String {
        switch state {
        case .resting: "rest"; case .listening: "listen"; case .transcribing: "writing"
        case .confirmed: "done"; case .meetingPrompt: "prompt"; case .recording: minimized ? "rec-min" : "rec"; case .saved: "saved"
        case .typed: "typed"; case .notPasted: "notpasted"
        }
    }

    /// True while the pill has something to show.
    var isActive: Bool { busy }

    private func makePanel() {
        // A fixed, transparent stage: the capsule and notes card animate inside
        // it with SwiftUI springs, so nothing jumps when the content changes size.
        let p = PillPanel(contentRect: NSRect(origin: .zero, size: Self.stage),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        let host = NSHostingView(rootView: AnyView(PillView().environmentObject(self).environmentObject(AppModel.shared)
            .modelContainer(AppModel.shared.container)))
        host.wantsLayer = true
        p.contentView = host
        panel = p
        hosting = host
    }

    // MARK: One surface at a time

    /// The Oatmeal window is up front, so the pill steps aside.
    private var windowInFront: Bool {
        NSApp.isActive && NSApp.windows.contains { $0.isVisible && $0.isKeyWindow && !($0 is NSPanel) && $0.frame.width > 600 }
    }

    /// The pill only exists while something is happening: dictating, a meeting
    /// prompt, recording, or a short confirmation. At rest it's hidden.
    private var busy: Bool {
        if MeetingService.shared.isRecording { return true }
        if case .resting = state { return false }
        return true
    }

    private func observeWindows() {
        let nc = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    PillController.shared.syncVisibility()
                }
            }
        }
    }

    /// The stage stays ordered in; when nothing's happening it's empty and lets
    /// every click through.
    func syncVisibility() {
        guard let panel else { return }
        let active = busy && visible
        if active {
            if !dragging { relayout() }
            watchPointer(true)
            updatePassThrough()
        } else {
            watchPointer(false)
            panel.ignoresMouseEvents = true
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private var pointerTimer: Timer?

    /// The stage is much bigger than the pill (so cards can grow without the window jumping). Clicks
    /// land on the pill only while the pointer is over it; everywhere else they go to the app below.
    /// Polled rather than using event monitors, which miss moves over Oatmeal's own windows.
    private func watchPointer(_ on: Bool) {
        if on, pointerTimer == nil {
            pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
                Task { @MainActor in PillController.shared.updatePassThrough() }
            }
        } else if !on {
            pointerTimer?.invalidate(); pointerTimer = nil
        }
    }

    private func updatePassThrough() {
        guard let panel else { return }
        guard busy && visible else { panel.ignoresMouseEvents = true; return }
        if dragging { panel.ignoresMouseEvents = false; return }
        guard !hitRect.isNull else { panel.ignoresMouseEvents = true; return }
        let h = panel.frame.height
        let r = NSRect(x: hitRect.minX, y: h - hitRect.maxY, width: hitRect.width, height: hitRect.height).insetBy(dx: -4, dy: -4)
        let over = r.contains(panel.mouseLocationOutsideOfEventStream)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    fileprivate var shouldShow: Bool { busy }

    /// Tap right ⌥: window → pill, pill → window.
    func toggleSurface() {
        if handsFree { Task { await finishDictation() }; return }
        if windowInFront { AppModel.shared.hideWindow() } else { AppModel.shared.open(AppModel.shared.section) }
    }

    func toggleMeeting() {
        Task { @MainActor in
            if MeetingService.shared.isRecording { await stopMeeting() }
            else { await startMeeting(title: CalendarStore.shared.currentEvent()?.title ?? MeetingService.shared.detectedMeetingApp ?? "Meeting") }
        }
    }

    func switchToTask() {
        guard case .listening = state else { return }
        target = .task
        set(.listening(.task))
    }

    func setVisible(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "pillVisible")
        syncVisibility()
    }

    func toggleVisible() { setVisible(!(panel?.isVisible ?? false)) }

    /// Pins the stage bottom-centre on the screen the pointer is on, nudged by wherever the user dragged it.
    func relayout() {
        guard let panel, !dragging else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let base = Self.homeOrigin(in: vf)
        let d = UserDefaults.standard
        let origin = Self.clamp(NSPoint(x: base.x + d.double(forKey: "pillOffsetX"), y: base.y + d.double(forKey: "pillOffsetY")), in: vf)
        let frame = NSRect(origin: origin, size: Self.stage)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
    }

    private static func homeOrigin(in vf: NSRect) -> NSPoint {
        NSPoint(x: vf.midX - stage.width / 2, y: vf.minY + 8)
    }

    /// Keeps the pill itself on screen. It sits at the bottom centre of the stage, so the stage may hang off the edges.
    private static func clamp(_ p: NSPoint, in vf: NSRect) -> NSPoint {
        NSPoint(x: min(max(p.x, vf.minX + 70 - stage.width / 2), vf.maxX - 70 - stage.width / 2),
                y: min(max(p.y, vf.minY - 4), vf.maxY - 64))
    }

    // MARK: Dragging

    private(set) var dragging = false
    private var dragStart: (origin: NSPoint, mouse: NSPoint)?

    func dragChanged() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (panel.frame.origin, mouse); dragging = true; panel.ignoresMouseEvents = false }
        guard let s = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: s.origin.x + mouse.x - s.mouse.x, y: s.origin.y + mouse.y - s.mouse.y))
    }

    func dragEnded() {
        guard let panel, dragStart != nil else { return }
        dragStart = nil
        dragging = false
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: panel.frame.midX, y: panel.frame.minY + 30)) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let base = Self.homeOrigin(in: vf)
        let origin = Self.clamp(panel.frame.origin, in: vf)
        UserDefaults.standard.set(origin.x - base.x, forKey: "pillOffsetX")
        UserDefaults.standard.set(origin.y - base.y, forKey: "pillOffsetY")
        panel.setFrameOrigin(origin)
        updatePassThrough()
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: "pillOffsetX")
        UserDefaults.standard.removeObject(forKey: "pillOffsetY")
        relayout()
    }

    func setMinimized(_ on: Bool) {
        if on { expanded = false }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { minimized = on }
    }

    private func set(_ s: PillState) {
        resetWork?.cancel()
        if case .resting = state { relayout() }   // follow the pointer to the right screen before appearing
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { state = s }
        let escape: Bool
        switch s { case .listening, .notPasted: escape = true; default: escape = false }
        RightOptionKey.escapeIsOurs.withLock { $0 = escape }
        syncVisibility()
    }

    private func settle(after seconds: Double) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if MeetingService.shared.isRecording { self.set(.recording) } else { self.set(.resting) }
        }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Dictation

    @Published private(set) var handsFree = false
    private var listenStarted = Date()

    func startDictation(into target: DictationTarget) {
        guard !MeetingService.shared.isRecording else { DFLog.log("dictation", "ignored: a meeting is recording"); return }
        if case .listening = state { DFLog.log("dictation", "ignored: already listening"); return }
        DFLog.log("dictation", "start (\(target == .task ? "task" : "app"))")
        self.target = target
        let front = NSWorkspace.shared.frontmostApplication
        frontApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
        listenStarted = Date()
        DictationSounds.start()
        DictationService.shared.start()
        set(.listening(target))
    }

    /// Double-tap right ⌥: keep listening with hands off the keyboard.
    func startHandsFree() {
        if case .listening = state { return }
        handsFree = true
        startDictation(into: .app)
    }

    func dismiss() { set(.resting) }

    func cancelDictation() {
        handsFree = false
        DictationService.shared.cancel()
        DictationSounds.cancel()
        set(.resting)
    }

    func finishDictation() async {
        guard case .listening(let target) = state else { return }
        handsFree = false
        DictationSounds.stop()
        set(.transcribing)
        let raw = await DictationService.shared.stop()
        let seconds = Date().timeIntervalSince(listenStarted)
        let appKind = target == .task ? TextFormatter.AppKind.standard : TextFormatter.kind(for: frontApp?.bundleIdentifier)
        let local = TextFormatter.format(raw, app: appKind, options: VoiceSettings.shared.options)
        DFLog.log("dictation", "released after \(String(format: "%.1f", seconds))s: \(raw.count) chars heard")
        guard !local.isEmpty else {
            // Say so rather than vanish: a silent pill looks like Oatmeal broke.
            set(.confirmed(title: "Didn\u{2019}t catch that", detail: "Hold right \u{2325} and speak", taskID: nil))
            settle(after: 2.5)
            return
        }
        let text = local
        let ctx = AppModel.shared.context
        let appName = frontApp?.localizedName ?? ""
        do {
            // Put focus back where the words belong before pasting.
            frontApp?.activate()
            try? await Task.sleep(for: .milliseconds(60))
            let result = TextInserter.insert(text)
            lastText = text
            ctx.insert(DictationEntry(text: text, destination: "app", appName: appName, seconds: seconds))
            try? ctx.save()
            showPasteResult(result, text)
        }
    }

    private(set) var lastText: String?

    func pasteLast() {
        let ctx = AppModel.shared.context
        var desc = FetchDescriptor<DictationEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        desc.fetchLimit = 1
        guard let text = lastText ?? (try? ctx.fetch(desc))?.first?.text else { return }
        showPasteResult(TextInserter.insert(text), text)
    }

    private func showPasteResult(_ result: TextInserter.Result, _ text: String) {
        DFLog.log("paste", "\(result) into \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        switch result {
        case .pasted:
            // It landed: the words are in the field, so the pill just goes away.
            set(.resting)
        case .unsure:
            // Pasted, but the app wouldn't say if a field had focus: show what went in for a moment,
            // with a way to the drag-and-copy card if it didn't.
            set(.typed(text)); settle(after: 3.5)
        case .nowhere:
            // Nowhere to type: keep the words on screen to drag in or copy.
            showCard(text)
        }
    }

    /// The drag-or-copy card for words that didn't go in.
    func showCard(_ text: String) { set(.notPasted(text)); settle(after: 20) }

    func undo(_ id: UUID?) { set(.resting) }

    // MARK: Meetings

    /// Granola-style "meeting's over?": the calendar event ended a couple of
    /// minutes ago, or nobody has said anything for four minutes.
    @Published private(set) var meetingLikelyOver = false
    @Published var myNotes = ""
    private var meetingEvent: CalEvent?
    private var lastSegmentCount = 0
    private var lastSpeechAt = Date()

    private func checkForMeeting() {
        let ms = MeetingService.shared
        if ms.isRecording {
            if ms.segments.count != lastSegmentCount { lastSegmentCount = ms.segments.count; lastSpeechAt = Date() }
            let eventOver = meetingEvent.map { Date() > $0.end.addingTimeInterval(120) } ?? false
            let quiet = Date().timeIntervalSince(lastSpeechAt) > 240
            let over = eventOver || quiet
            if over != meetingLikelyOver { withAnimation(.snappy) { meetingLikelyOver = over } }
            return
        }
        guard UserDefaults.standard.object(forKey: "meetingPrompt") as? Bool ?? true else { return }
        switch state {
        case .resting, .meetingPrompt: break
        default: return
        }
        let event = CalendarStore.shared.currentEvent()
        let autoIDs = Set((UserDefaults.standard.string(forKey: "autoRecordIDs") ?? "").split(separator: "|").map(String.init))
        if let e = event, autoIDs.contains(e.id), dismissedPromptFor != e.id {
            dismissedPromptFor = e.id
            Task { await startMeeting(title: e.title) }
            return
        }
        // A calendar meeting starting (within 2 min either side) pops the pill up.
        if let e = event, abs(e.start.timeIntervalSinceNow) < 120, dismissedPromptFor != e.title {
            meetingTitle = e.title; set(.meetingPrompt(e.title)); return
        }
        if let app = ms.detectedMeetingApp {
            let title = event?.title ?? app
            if dismissedPromptFor != title { meetingTitle = title; set(.meetingPrompt(title)) }
        } else if case .meetingPrompt = state {
            set(.resting)
        }
    }

    func dismissPrompt() {
        if case .meetingPrompt(let t) = state { dismissedPromptFor = t }
        set(.resting)
    }

    func startMeeting(title: String) async {
        guard !MeetingService.shared.isRecording else { return }
        meetingEvent = CalendarStore.shared.currentEvent()
        myNotes = ""
        minimized = false
        meetingLikelyOver = false
        lastSegmentCount = 0; lastSpeechAt = Date()
        meetingTitle = title
        dismissedPromptFor = title
        do {
            try await MeetingService.shared.start(title: title)
            set(.recording)
        } catch {
            set(.confirmed(title: "Couldn\u{2019}t start recording", detail: error.localizedDescription, taskID: nil))
            settle(after: 5)
        }
    }

    func stopMeeting() async {
        guard MeetingService.shared.isRecording else { return }
        expanded = false
        minimized = false
        set(.transcribing)
        let rec = await MeetingService.shared.stop()
        let ctx = AppModel.shared.context
        let note = MeetingNote(title: rec.title, startedAt: rec.startedAt)
        note.duration = rec.duration
        note.transcriptData = (try? JSONEncoder().encode(rec.segments)) ?? Data()
        note.calendarEventID = meetingEvent?.id
        note.attendees = meetingEvent?.attendees ?? []
        note.myNotes = myNotes
        meetingLikelyOver = false
        meetingEvent = nil
        ctx.insert(note)
        try? ctx.save()
        AppModel.shared.selectedMeetingID = note.id
        NoteWriters.shared.meetingSaved(note)
        set(.saved("Notes saved", note.id))
        settle(after: 6)
    }

    func toggleExpanded() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { expanded.toggle() }
    }

    func openApp(_ section: Section = .meetings) {
        AppModel.shared.open(section)
    }
}

/// Borderless panels can't take keys by default; the live-notes card needs to,
/// so you can type your own notes without leaving the call.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { MainActor.assumeIsolated { PillController.shared.expanded } }
    override var canBecomeMain: Bool { false }
}
