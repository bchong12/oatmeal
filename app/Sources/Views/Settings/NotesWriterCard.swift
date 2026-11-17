import SwiftUI
import AppKit

/// Settings › General: which AI writes your meeting notes. Each runs on this Mac on the user's own plan.
struct NotesWriterCard: View {
    @ObservedObject private var writers = NoteWriters.shared
    private var kinds: [NoteWriterKind] { NoteWriterKind.allCases }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who writes your notes").font(DF.font(17, .semibold)).foregroundStyle(DF.ink).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(kinds.enumerated()), id: \.element) { i, k in
                    if i > 0 { Divider().overlay(DF.line) }
                    row(k)
                }
            }
            .dfCard()
            Text("Oatmeal runs Claude Code, Codex or Gemini CLI on this Mac and gives it only two tools: read a meeting, save its notes.")
                .font(DF.font(12)).foregroundStyle(DF.faint)
        }
    }

    private func row(_ k: NoteWriterKind) -> some View {
        let installed = writers.isInstalled(k)
        let on = writers.active == k
        return HStack(spacing: 14) {
            logo(k).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(k.title).font(DF.font(15, .semibold))
                if !writers.lookedUp {
                    Text("Looking on this Mac\u{2026}").font(DF.font(13)).foregroundStyle(DF.faint)
                } else if installed {
                    Text("Found on this Mac \u{00B7} \(k.plan)").font(DF.font(13)).foregroundStyle(DF.thrivingInk)
                } else {
                    Text("Not installed \u{00B7} \(k.installHint)").font(DF.font(13)).foregroundStyle(DF.muted)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            DFRadio(on: on).opacity(installed ? 1 : 0.4)
        }
        .padding(.vertical, 14)
        
        .contentShape(Rectangle())
        .onTapGesture { if installed { writers.preferred = k } }
    }

    @ViewBuilder private func logo(_ k: NoteWriterKind) -> some View {
        if let url = Bundle.main.url(forResource: k.logo, withExtension: "png", subdirectory: "Brand"), let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 9).fill(DF.wash)
        }
    }
}
