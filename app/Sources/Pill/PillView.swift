import SwiftUI
import SwiftData

/// The capsule and, while recording, the live-notes card that grows above it.
struct PillView: View {
    @EnvironmentObject var pill: PillController
    @ObservedObject private var meeting = MeetingService.shared

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if pill.expanded, !pill.minimized, case .recording = pill.state {
                LiveNotesCard()
                    .reportsPillHitArea()
                    .transition(.asymmetric(insertion: .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity),
                                            removal: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity)))
            }
            if pill.isActive {
                capsule
                    .reportsPillHitArea()
                    // Drag the pill anywhere; it remembers the spot. Taps still reach its buttons.
                    .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { _ in pill.dragChanged() }
                        .onEnded { _ in pill.dragEnded() })
                    .contextMenu {
                        if case .recording = pill.state {
                            Button(pill.minimized ? "Show full pill" : "Minimize") { pill.setMinimized(!pill.minimized) }
                        }
                        Button("Move back to bottom centre") { pill.resetPosition() }
                    }
                    .transition(.asymmetric(insertion: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 10)),
                                            removal: .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity)))
            }
        }
        .padding(.bottom, 10)
        .frame(width: PillController.stage.width, height: PillController.stage.height, alignment: .bottom)
        .coordinateSpace(name: PillHitArea.space)
        .onPreferenceChange(PillHitArea.self) { rect in
            MainActor.assumeIsolated { PillController.shared.hitRect = rect }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var capsule: some View {
        if case .listening(let target) = pill.state {
            ListeningCard(target: target)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if case .notPasted(let text) = pill.state {
            NotPastedCard(text: text)
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
        } else {
            Group {
                switch pill.state {
                case .resting: RestingPill()
                case .transcribing: TranscribingPill()
                case .confirmed(let title, let detail, let id): ConfirmedPill(title: title, detail: detail, id: id)
                case .meetingPrompt(let title): MeetingPromptPill(title: title)
                case .recording: if pill.minimized { MinimizedRecordingPill() } else { RecordingPill() }
                case .saved(let text, let id): SavedPill(text: text, id: id)
                case .typed(let text): TypedPill(text: text)
                case .listening, .notPasted: EmptyView()
                }
            }
            .id(pill.stateKey)
            .frame(height: pill.minimized && pill.state == .recording ? 30 : 40)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .background {
                Capsule().fill(Color(.sRGB, red: 0.094, green: 0.098, blue: 0.11, opacity: 0.94))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
            }
            .foregroundStyle(.white)
            .fixedSize()
        }
    }
}

/// Frosted glass, like Spokenly's recorder.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Listening: the app the words are going into, waves, and the Oatmeal mark.
private struct ListeningCard: View {
    let target: DictationTarget
    @EnvironmentObject var pill: PillController
    @ObservedObject private var dictation = DictationService.shared

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if target == .task {
                    Image(systemName: "checklist").font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22).background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                } else if let icon = pill.frontApp?.icon {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                } else {
                    Image(systemName: "text.cursor").font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22).background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .help(target == .task ? "Becomes a task" : (pill.frontApp?.localizedName ?? ""))
            if let problem = dictation.micProblem {
                Text(problem).font(DF.font(12, .semibold)).foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).fixedSize()
            } else {
                DotWaves()
            }
            if pill.handsFree {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                    .help("Hands-free: tap right ⌥ to finish, Esc to cancel")
            }
            BrandMarkMono(size: 13, color: .white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .fixedSize()
        .foregroundStyle(.white)
        .background {
            Capsule().fill(Color(.sRGB, red: 0.094, green: 0.098, blue: 0.11, opacity: 0.94))
                .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
        }
    }
}

/// A rolling waveform: each mic reading comes in on the left and slides right. Louder is taller.
struct DotWaves: View {
    static let count = 24
    @ObservedObject private var dictation = DictationService.shared
    @State private var levels: [CGFloat] = Array(repeating: 0, count: DotWaves.count)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<Self.count, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.45 + 0.55 * levels[i]))
                    .frame(width: 3, height: 3 + levels[i] * 23)
            }
        }
        .frame(width: CGFloat(Self.count) * 6, height: 28)
        .onReceive(dictation.$level) { lvl in
            // Lift quiet speech so it still shows; loud stays near the top.
            let l = pow(CGFloat(min(max(lvl, 0), 1)), 0.6)
            withAnimation(.linear(duration: 1.0 / 30)) {
                levels.removeLast()
                levels.insert(l * CGFloat.random(in: 0.85...1), at: 0)
            }
        }
    }
}

private struct PillButton: View {
    let symbol: String
    var fill: Color = .white.opacity(0.12)
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28).background(fill, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct RestingPill: View {
    @EnvironmentObject var pill: PillController

    var body: some View {
        HStack(spacing: 10) {
            Button { pill.openApp() } label: {
                HStack(spacing: 10) {
                    BrandMarkMono(size: 22, color: .white.opacity(0.85))
                        .frame(width: 36, height: 36).background(.white.opacity(0.10), in: Circle())
                    Text("Hold right \u{2325} to talk").font(DF.font(13, .semibold)).foregroundStyle(.white.opacity(0.85))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Oatmeal")
            PillButton(symbol: "record.circle") { pill.toggleMeeting() }
                .help("Take meeting notes")
        }
        .padding(.leading, 8).padding(.trailing, 8)
    }
}

/// Bars that follow the mic level, like Spokenly's capsule.
struct LevelWaves: View {
    var bars = 21
    @ObservedObject private var dictation = DictationService.shared
    @State private var history: [CGFloat] = Array(repeating: 0, count: 21)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                let centre = 1 - abs(CGFloat(i) - CGFloat(bars - 1) / 2) / (CGFloat(bars) / 2)
                Capsule().fill(.white)
                    .frame(width: 4, height: 4 + history[i] * 28 * (0.45 + 0.55 * centre))
            }
        }
        .frame(height: 32)
        .onReceive(dictation.$level) { lvl in
            withAnimation(.linear(duration: 0.06)) {
                history.removeFirst()
                history.append(CGFloat(min(max(lvl, 0), 1)) * CGFloat.random(in: 0.75...1.0))
            }
        }
    }
}

private struct TranscribingPill: View {
    var body: some View {
        HStack(spacing: 10) {
            // Dayform's spinner: the pill floats over other apps, so it keeps the system one.
            ProgressView().controlSize(.small).tint(.white)
            Text("Writing it down…").font(DF.font(13, .semibold))
        }
        .padding(.horizontal, 20)
    }
}

private struct ConfirmedPill: View {
    let title: String
    let detail: String
    let id: UUID?
    @EnvironmentObject var pill: PillController
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").font(.system(size: 17)).foregroundStyle(Color(hex: 0x7BD88F))
            Text(id == nil ? title : "Added").font(DF.font(13, .semibold))
            Text(id == nil ? detail : [title, detail].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(DF.font(13)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 320, alignment: .leading).fixedSize(horizontal: true, vertical: false)
            if id != nil {
                Button("Undo") { pill.undo(id) }
                    .buttonStyle(.plain).font(DF.font(13, .semibold))
                    .padding(.horizontal, 10).frame(height: 28).background(.white.opacity(0.12), in: Capsule())
            }
        }
        .padding(.leading, 12).padding(.trailing, 6)
    }
}

private struct MeetingPromptPill: View {
    let title: String
    @EnvironmentObject var pill: PillController
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            Text(title).font(DF.font(13, .semibold)).lineLimit(1).frame(maxWidth: 200, alignment: .leading).fixedSize(horizontal: true, vertical: false)
            Text("is starting").font(DF.font(13)).foregroundStyle(.white.opacity(0.6))
            Button { Task { await pill.startMeeting(title: title) } } label: {
                HStack(spacing: 6) { Circle().fill(.white).frame(width: 7, height: 7); Text("Take notes") }
                    .font(DF.font(13, .bold)).padding(.horizontal, 12).frame(height: 28).background(DF.now, in: Capsule())
            }
            .buttonStyle(.plain)
            PillButton(symbol: "xmark") { pill.dismissPrompt() }
        }
        .padding(.leading, 12).padding(.trailing, 6)
    }
}

private struct RecordingPill: View {
    @EnvironmentObject var pill: PillController
    @ObservedObject private var meeting = MeetingService.shared
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(meeting.isPaused ? Color.orange : DF.now).frame(width: 9, height: 9)
            Text("\(meeting.isPaused ? "Paused" : "Recording") · \(Duration.seconds(meeting.elapsed).formatted(.time(pattern: .minuteSecond)))")
                .font(DF.font(13, .semibold)).monospacedDigit()
            if pill.meetingLikelyOver {
                Button { Task { await pill.stopMeeting() } } label: {
                    Text("Meeting over? Save notes").font(DF.font(12, .semibold))
                        .padding(.horizontal, 10).frame(height: 28).background(.white.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            PillButton(symbol: pill.expanded ? "chevron.down" : "text.alignleft") { pill.toggleExpanded() }
                .help("Live notes")
            PillButton(symbol: meeting.isPaused ? "play.fill" : "pause.fill") { meeting.isPaused ? meeting.resume() : meeting.pause() }
            PillButton(symbol: "stop.fill", fill: DF.now) { Task { await pill.stopMeeting() } }
            PillButton(symbol: "minus", fill: .clear) { pill.setMinimized(true) }
                .help("Minimize (keeps recording)")
        }
        .padding(.leading, 14).padding(.trailing, 6)
    }
}

/// Recording, tucked away: a red dot and the time. Click to bring the full pill back.
private struct MinimizedRecordingPill: View {
    @EnvironmentObject var pill: PillController
    @ObservedObject private var meeting = MeetingService.shared
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(meeting.isPaused ? Color.orange : DF.now).frame(width: 8, height: 8)
            Text(Duration.seconds(meeting.elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(DF.font(12, .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 11)
        .frame(maxHeight: .infinity)
        .contentShape(Capsule())
        // One gesture for both: a Button here would swallow the drag. Moving more than a few points
        // drags the pill; letting go without moving brings the full pill back.
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if pill.dragging || hypot(v.translation.width, v.translation.height) > 3 { pill.dragChanged() }
            }
            .onEnded { _ in
                if pill.dragging { pill.dragEnded() } else { pill.setMinimized(false) }
            })
        .help(meeting.isPaused ? "Paused. Click to show the pill, drag to move it" : "Recording. Click to show the pill, drag to move it")
    }
}

/// The union of the pill's visible pieces, so the panel only takes clicks there.
struct PillHitArea: PreferenceKey {
    static let space = "pillStage"
    static let defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = value.union(nextValue()) }
}

private extension View {
    func reportsPillHitArea() -> some View {
        background(GeometryReader { g in Color.clear.preference(key: PillHitArea.self, value: g.frame(in: .named(PillHitArea.space))) })
    }
}

/// After dictating: exactly what was typed, so you can see it landed.
private struct TypedPill: View {
    let text: String
    @EnvironmentObject var pill: PillController
    var body: some View {
        HStack(spacing: 8) {
            if let icon = pill.frontApp?.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            else { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x7BD88F)) }
            Text(text.replacingOccurrences(of: "\n", with: " ⏎ "))
                .font(DF.font(13, .medium)).foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 300, alignment: .leading)
            Button { pill.showCard(text) } label: {
                Text("Didn\u{2019}t go in?").font(DF.font(12, .semibold))
                    .padding(.horizontal, 10).frame(height: 26).background(.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Show the words to drag in or copy. They\u{2019}re on your clipboard too.")
        }
        .padding(.leading, 14).padding(.trailing, 7)
    }
}

private struct SavedPill: View {
    let text: String
    let id: UUID
    @EnvironmentObject var pill: PillController
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").font(.system(size: 17)).foregroundStyle(Color(hex: 0x7BD88F))
            Text(text).font(DF.font(13, .semibold))
            Button("Open") { AppModel.shared.selectedMeetingID = id; pill.openApp(.meetings) }
                .buttonStyle(.plain).font(DF.font(13, .semibold))
                .padding(.horizontal, 10).frame(height: 28).background(.white.opacity(0.12), in: Capsule())
        }
        .padding(.leading, 12).padding(.trailing, 6)
    }
}

/// Grows out of the pill while recording: notes so far and tasks it heard.
private struct LiveNotesCard: View {
    @ObservedObject private var meeting = MeetingService.shared
    @EnvironmentObject var pill: PillController
    @State private var tab = 0
    @State private var copied = false

    private var copyText: String { tab == 0 ? pill.myNotes : meeting.segments.plainText }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                DFSegmented(items: [(0, "My notes"), (1, "Transcript")], selection: $tab)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(copyText, forType: .string)
                    withAnimation(.snappy) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(.snappy) { copied = false } }
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.plain).foregroundStyle(copied ? DF.thrivingInk : DF.muted)
                    .disabled(copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(tab == 0 ? "Copy my notes" : "Copy the transcript so far")
                Button { pill.openApp(.meetings) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain).foregroundStyle(DF.muted).help("Open in Oatmeal")
            }
            .padding(12)
            .overlay(alignment: .bottom) { Divider().overlay(DF.line) }

            if tab == 0 {
                ZStack(alignment: .topLeading) {
                    if pill.myNotes.isEmpty {
                        Text("Jot anything down. Your notes shape the meeting notes.")
                            .font(DF.font(13)).foregroundStyle(DF.faint).padding(.top, 1).padding(.leading, 5)
                    }
                    TextEditor(text: $pill.myNotes)
                        .font(DF.font(13)).scrollContentBackground(.hidden)
                        .onAppear { NSApp.activate(ignoringOtherApps: true) }
                }
                .padding(16)
                .frame(height: 200)
            } else {
                // The whole transcript, following along at the bottom as people talk.
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if meeting.segments.isEmpty {
                                Text("Listening\u{2026} the transcript appears here as people talk.").font(DF.font(13)).foregroundStyle(DF.muted)
                            }
                            ForEach(meeting.segments) { s in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.speaker).font(DF.font(12, .bold))
                                    Text(s.text).font(DF.font(13)).fixedSize(horizontal: false, vertical: true)
                                }
                                .textSelection(.enabled)
                                .id(s.id)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                    .onAppear { if let last = meeting.segments.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    .onChange(of: meeting.segments.count) { _, _ in
                        if let last = meeting.segments.last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }
        }
        .frame(width: 380)
        .background(DF.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
        .environment(\.colorScheme, .light)
        .foregroundStyle(DF.ink)
    }
}

/// Nowhere to type: the words stay here to drag into any app, or copy.
private struct NotPastedCard: View {
    let text: String
    @EnvironmentObject var pill: PillController
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hand.draw").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text("Drag it where it goes").font(DF.font(12, .semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button { pill.dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22).background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain).help("Dismiss (Esc)")
            }
            Text(text)
                .font(DF.font(14, .medium)).foregroundStyle(.white)
                .lineLimit(6).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .overlay {
                    // Dropped somewhere that took it: it's done, so the card goes away.
                    TextDragSource(text: text) { pill.dismiss() }
                }
            HStack {
                Text("Also on your clipboard").font(DF.font(11)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(.snappy) { copied = true }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(DF.font(12, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 26).background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 380)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Color(.sRGB, red: 0.094, green: 0.098, blue: 0.11, opacity: 0.96))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        }
    }
}

/// Drags plain text out of the pill. SwiftUI's .draggable never says whether the drop landed;
/// AppKit's dragging session does, so the card can close once the words are in.
private struct TextDragSource: NSViewRepresentable {
    let text: String
    let dropped: () -> Void

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ v: DragView, context: Context) { v.text = text; v.dropped = dropped }

    final class DragView: NSView, NSDraggingSource {
        var text = ""
        var dropped: () -> Void = {}
        private var downAt: NSPoint?

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }

        override func mouseDragged(with event: NSEvent) {
            guard let start = downAt, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 else { return }
            downAt = nil
            let item = NSDraggingItem(pasteboardWriter: text as NSString)
            let image = preview()
            let at = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: at.x - 20, y: at.y - image.size.height + 12, width: image.size.width, height: image.size.height), contents: image)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .generic] : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            if !operation.isEmpty { DispatchQueue.main.async { self.dropped() } }
        }

        @MainActor private func preview() -> NSImage {
            let r = ImageRenderer(content: Text(text).font(DF.font(13)).lineLimit(3).padding(10).frame(width: 260, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(DF.ink))
            r.scale = window?.backingScaleFactor ?? 2
            return r.nsImage ?? NSImage(size: NSSize(width: 260, height: 40))
        }
    }
}
