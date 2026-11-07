import SwiftUI
import SwiftData
import AppKit
import AVFoundation
import ApplicationServices

@main
struct OatmealApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Oatmeal", id: "main") {
            RootView()
                .preferredColorScheme(.light)
                .environmentObject(model)
                .environmentObject(CalendarStore.shared)
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(AppModel.shared.container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Take Notes Now") { HotkeyService.shared.onMeeting?() }.keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Go") {
                ForEach(Section.main) { s in
                    Button(s.title) { model.section = s }.keyboardShortcut(s.key, modifiers: .command)
                }
                Divider()
                Button("Toggle Sidebar") { model.toggleSidebar() }.keyboardShortcut("s", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.open(.settings) }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

enum Place: Hashable {
    case recent
    case folder(UUID?)
}

enum Section: String, CaseIterable, Identifiable {
    case meetings, dictation, settings
    var id: String { rawValue }
    /// The sections in the sidebar's main switch (Settings sits at the bottom).
    static var main: [Section] { [.meetings, .dictation] }
    var title: String {
        switch self { case .meetings: "Notes"; case .dictation: "Flow"; case .settings: "Settings" }
    }
    var symbol: String {
        switch self { case .meetings: "note.text"; case .dictation: "waveform"; case .settings: "gearshape" }
    }
    var key: KeyEquivalent {
        switch self { case .meetings: "1"; case .dictation: "2"; case .settings: "," }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let container: ModelContainer
    @Published var section: Section = .meetings
    /// The open meeting; nil shows the list for `place`.
    @Published var selectedMeetingID: UUID?
    /// Where the meetings list is, like a Finder window: Recent, or a folder (nil = the top level).
    @Published var place: Place = .folder(nil)
    /// Folders open in the sidebar tree.
    @Published var expandedFolders: Set<UUID> = Set((UserDefaults.standard.stringArray(forKey: "expandedFolders") ?? []).compactMap(UUID.init)) {
        didSet { UserDefaults.standard.set(expandedFolders.map(\.uuidString), forKey: "expandedFolders") }
    }
    /// The folder whose name is being edited in place, and whether that's in the sidebar or the list.
    @Published var renaming: (id: UUID, inSidebar: Bool)?
    @Published var now = Date()

    func go(_ p: Place) {
        // Open the sidebar tree down to where we're going, like Finder revealing a folder.
        if case .folder(let id) = p, let id {
            let folders = MeetingFolders.all(context)
            for f in MeetingFolders.path(to: id, in: folders).dropLast() { expandedFolders.insert(f.id) }
        }
        withAnimation(.snappy(duration: 0.22)) {
            section = .meetings
            selectedMeetingID = nil
            place = p
        }
    }

    func startRenaming(_ f: MeetingFolder, inSidebar: Bool) {
        // The list can only edit folders it's showing; anywhere else, edit in the sidebar.
        let listShows: Bool = { if case .folder(let at) = place { return section == .meetings && selectedMeetingID == nil && at == f.parentID }; return false }()
        if inSidebar || !listShows, let p = f.parentID { expandedFolders.insert(p) }
        renaming = (f.id, inSidebar || !listShows)
    }
    @Published var sidebarCollapsed = UserDefaults.standard.bool(forKey: "sidebarCollapsed")
    /// Right-hand panels (the meeting's details).
    @Published var sidePanelOpen = UserDefaults.standard.object(forKey: "sidePanelOpen") as? Bool ?? true
    @Published var settingsTab = "General"
    @Published var notificationsOpen = false
    func setNotifications(_ open: Bool) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) { notificationsOpen = open }
    }
    func closeMenus() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) { notificationsOpen = false }
    }

    func setSidePanel(_ open: Bool) {
        guard open != sidePanelOpen else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { sidePanelOpen = open }
        UserDefaults.standard.set(open, forKey: "sidePanelOpen")
    }

    func toggleSidebar() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { sidebarCollapsed.toggle() }
        UserDefaults.standard.set(sidebarCollapsed, forKey: "sidebarCollapsed")
    }

    private var clock: Timer?

    private init() {
        // Under XCTest the app is only a test host: keep its data in memory so tests never touch the
        // real store. (They used to: MCP tests created and deleted meetings in it.)
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !testing { StoreLocation.prepare() }
        let config = testing ? ModelConfiguration(isStoredInMemoryOnly: true) : ModelConfiguration(url: StoreLocation.url)
        do {
            container = try ModelContainer(for: MeetingNote.self, MeetingFolder.self, DictationEntry.self,
                                           configurations: config)
        } catch {
            fatalError("Couldn't open the Oatmeal store: \(error)")
        }
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var context: ModelContext { container.mainContext }

    func bootstrap() {
        applyLaunchArguments()
    }

    /// Dev-only launch options for screenshots and checks, e.g.
    /// `Oatmeal -section goals -sheet goal -pill recording`.
    private func applyLaunchArguments() {
        let d = UserDefaults.standard
        if let s = d.string(forKey: "section"), let sec = Section(rawValue: s) { section = sec }
        if let t = d.string(forKey: "settingsTab") { settingsTab = t }
        if let p = d.string(forKey: "place") {
            if p == "recent" { place = .recent }
            else if let f = MeetingFolders.all(context).first(where: { $0.name == p }) {
                place = .folder(f.id)
                MeetingFolders.path(to: f.parentID, in: MeetingFolders.all(context)).forEach { expandedFolders.insert($0.id) }
            }
        }
        if let demo = d.string(forKey: "demo") {
            // Opens a menu or dialog for screenshots: `-demo menu` or `-demo dialog`.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
                guard let f = MeetingFolders.all(context).first else { return }
                if demo == "menu" { Popups.shared.showMenu(MeetingFolders.menu(for: f, model: self, inSidebar: true), at: CGPoint(x: 150, y: 405)) }
                if demo == "dialog" { MeetingFolders.confirmDelete(f, model: self) }
            }
        }
        if d.bool(forKey: "openFirst") {
            selectedMeetingID = (try? context.fetch(FetchDescriptor<MeetingNote>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])))?.first?.id
        }
        if let v = d.volatileDomain(forName: UserDefaults.argumentDomain)["rail"] as? String { sidebarCollapsed = (v == "YES") }
        if let v = d.volatileDomain(forName: UserDefaults.argumentDomain)["panel"] as? String { sidePanelOpen = (v == "YES") }
        if d.bool(forKey: "shots") {
            // Screenshot mode: show on whatever desktop is visible, without taking focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                for w in NSApp.windows where !(w is NSPanel) && w.frame.width > 600 {
                    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    w.level = .floating
                    w.setFrame(NSRect(x: 60, y: 60, width: 1240, height: 800), display: true)
                    w.orderFrontRegardless()
                }
                for w in NSApp.windows where w.isSheet || w.sheetParent != nil { w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; w.level = .floating; w.orderFrontRegardless() }
            }
            // Draw each window into a PNG from inside the app. This works even when the
            // screen is locked, where ordinary screenshots come back empty.
            DispatchQueue.main.asyncAfter(deadline: .now() + (d.double(forKey: "shotDelay") > 0 ? d.double(forKey: "shotDelay") : 3.0)) {
                let dir = URL(fileURLWithPath: d.string(forKey: "shotDir") ?? "/tmp/oatmeal-shots")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let name = d.string(forKey: "shotName") ?? "shot"
                var i = 0
                for w in NSApp.windows where w.isVisible || w.isSheet || w is NSPanel {
                    guard let v = w.contentView, v.bounds.width > 50, v.bounds.height > 20 else { continue }
                    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                    v.cacheDisplay(in: v.bounds, to: rep)
                    let kind = w is NSPanel ? (w.isSheet ? "sheet" : "pill") : (w.isSheet ? "sheet" : "window")
                    let url = dir.appendingPathComponent("\(name)-\(kind)-\(i).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    i += 1
                }
                print("[Shots] wrote \(i) images for \(name)")
            }
        }
    }

    private func tick() {
        refreshPermissions()
        now = Date()
    }

    private var fallbackWindow: NSWindow?

    /// The main window, if SwiftUI has one alive.
    var mainWindow: NSWindow? {
        NSApp.windows.first { !($0 is NSPanel) && $0.frame.width > 600 && ($0.identifier?.rawValue.contains("main") == true || $0.title == "Oatmeal") }
    }

    func open(_ s: Section) {
        section = s
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let w = mainWindow {
            if w.isMiniaturized { w.deminiaturize(nil) }
            fadeIn(w)
            return
        }
        // SwiftUI restored the window as closed: build one ourselves.
        let host = NSHostingController(rootView: RootView().preferredColorScheme(.light)
            .environmentObject(self).environmentObject(CalendarStore.shared)
            .frame(minWidth: 900, minHeight: 600)
            .modelContainer(container))
        let w = NSWindow(contentViewController: host)
        w.title = "Oatmeal"
        w.styleMask.insert([.fullSizeContentView, .titled, .closable, .miniaturizable, .resizable])
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 1240, height: 800))
        w.center()
        fadeIn(w)
        fallbackWindow = w
    }

    private func fadeIn(_ w: NSWindow) {
        let wasVisible = w.isVisible && w.alphaValue > 0.99 && NSApp.isActive
        if !wasVisible { w.alphaValue = 0 }
        w.makeKeyAndOrderFront(nil)
        guard !wasVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().alphaValue = 1
        }
    }

    /// Fades the window out, then hides Oatmeal so the app you were in comes back.
    func hideWindow() {
        guard let w = mainWindow, w.isVisible else { NSApp.hide(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            w.animator().alphaValue = 0
        }, completionHandler: {
            NSApp.hide(nil)
            w.alphaValue = 1
        })
    }

    // MARK: Permissions

    @Published var needsAccessibility = !AXIsProcessTrusted()
    @Published var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    func refreshPermissions() {
        needsAccessibility = !AXIsProcessTrusted()
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// tccutil: wipe Oatmeal's Accessibility / Microphone / Calendar / audio-capture
    /// records (stale entries from older builds are the usual reason a switch is
    /// "on" but right ⌥ still does nothing), then relaunch so macOS asks again.
    func resetPermissions() {
        Popups.shared.confirm("Reset Oatmeal\u{2019}s permissions?",
                              "Oatmeal will be removed from Accessibility, Microphone and Calendars, then relaunch and ask again. Use this if right \u{2325} or dictation stopped working.",
                              confirm: "Reset and relaunch", destructive: true) { [weak self] in self?.resetPermissionsNow() }
    }

    private func resetPermissionsNow() {
        let id = Bundle.main.bundleIdentifier ?? "com.oatmeal.app"
        for service in ["Accessibility", "Microphone", "Calendar", "ListenEvent", "AudioCapture"] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", service, id]
            try? p.run(); p.waitUntilExit()
        }
        let path = Bundle.main.bundlePath
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { AppModel.shared.refreshPermissions() }
        }
    }

}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IOLBF, 0)
        // Oatmeal is designed light. Without this, a Mac in dark mode draws native
        // controls (pickers, toggles, menus) with white text on our white cards.
        NSApp.appearance = NSAppearance(named: .aqua)
        print("[Oatmeal] Accessibility trusted: \(AXIsProcessTrusted()) · mic: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        Task { @MainActor in
            AppModel.shared.bootstrap()
            // Dev: `-rebuildMeetings YES` turns every recording without a meeting back into one.
            if UserDefaults.standard.bool(forKey: "rebuildMeetings") { Task { await AudioImporter.shared.rebuildFromRecordings() } }
            // Dev: `-importAudio /path/file.m4a` imports a recording like dropping it on the list;
            // `-noteWriter codex` picks who writes the notes.
            if let w = UserDefaults.standard.string(forKey: "noteWriter") { NoteWriters.shared.preferred = NoteWriterKind(rawValue: w) }
            if let path = UserDefaults.standard.string(forKey: "importAudio") {
                Task { await AudioImporter.shared.importFile(URL(fileURLWithPath: path), title: "Pricing review") }
            }
            MCPServer.shared.start()
            CalendarStore.shared.refreshAuth()
            PillController.shared.start()
            self.installStatusItem()
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { AppModel.shared.requestMic() }
            // Right ⌥ and typing into other apps both need Accessibility: ask once at launch.
            if !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: "shots") {
                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(opts)
            }
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    AppModel.shared.refreshPermissions()
                }
            }
            try? await Task.sleep(for: .milliseconds(400))
            AppModel.shared.open(AppModel.shared.section)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Task { @MainActor in AppModel.shared.open(AppModel.shared.section) } }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "MarkTemplate", withExtension: "png", subdirectory: "Brand"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 26, height: 10)
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "o"
        }
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector, _ key: String, _ mods: NSEvent.ModifierFlags) {
            let i = menu.addItem(withTitle: title, action: sel, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods; i.target = self
        }
        add("Open Oatmeal  (tap right ⌥)", #selector(openMain), "", [])
        add("Start or Stop Meeting Notes  (right ⌥ M)", #selector(toggleMeeting), "", [])
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "Hold right ⌥ to dictate · tap it to open Oatmeal", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(withTitle: "Show Pill", action: #selector(togglePill), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Oatmeal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openMain() { Task { @MainActor in AppModel.shared.open(.meetings) } }
    @objc private func toggleMeeting() { Task { @MainActor in HotkeyService.shared.onMeeting?() } }
    @objc private func togglePill() { Task { @MainActor in PillController.shared.toggleVisible() } }
}
