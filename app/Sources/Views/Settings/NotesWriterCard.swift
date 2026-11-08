import SwiftUI
import AppKit

/// Settings › General: which AI writes your meeting notes. The CLIs run on this Mac on the user's own
/// plan; Oatmeal AI shows once the app is connected to a site, and works on Pro.
struct NotesWriterCard: View {
    @ObservedObject private var writers = NoteWriters.shared
    @ObservedObject private var account = OatmealAccount.shared

    private var kinds: [NoteWriterKind] { account.site == nil ? NoteWriterKind.clis : NoteWriterKind.allCases }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHO WRITES YOUR NOTES").font(DF.font(12, .bold)).tracking(1).foregroundStyle(DF.faint).padding(.top, 4)
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
                if k == .oatmeal {
                    Text(installed ? "Included with your plan \u{00B7} nothing to install"
                         : account.isPaid ? "Not switched on for \(account.brand) yet"
                         : account.signedIn ? "Part of Pro" : "Sign in above to use it with Pro")
                        .font(DF.font(13)).foregroundStyle(installed ? DF.thrivingInk : DF.muted)
                } else if !writers.lookedUp {
                    Text("Looking on this Mac\u{2026}").font(DF.font(13)).foregroundStyle(DF.faint)
                } else if installed {
                    Text("Found on this Mac \u{00B7} \(k.plan)").font(DF.font(13)).foregroundStyle(DF.thrivingInk)
                } else {
                    Text("Not installed \u{00B7} \(k.installHint)").font(DF.font(13)).foregroundStyle(DF.muted)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if k == .oatmeal && !installed && account.signedIn && !account.isPaid {
                Button("Upgrade") { account.openPricing() }.buttonStyle(.df(.honey, height: 30))
            } else {
                DFRadio(on: on).opacity(installed ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(on ? DF.honey.opacity(0.18) : .clear)
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
