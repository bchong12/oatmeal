import SwiftUI

/// Settings › Models › Speech to text: pick, download and delete models.
struct SpeechModelsCard: View {
    @ObservedObject private var dictation = DictationService.shared

    var body: some View {
        let models = SpeechModel.supported
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(models.enumerated()), id: \.element) { i, m in
                if i > 0 { Divider().overlay(DF.line) }
                row(m)
            }
        }
        .dfCard()
        .onAppear { dictation.refreshSizes() }
    }

    private func isSelected(_ m: SpeechModel) -> Bool { dictation.model == m }

    private func progress(_ m: SpeechModel) -> Double? {
        if let p = dictation.downloads[m] { return p }
        if isSelected(m), case .downloading(let p) = dictation.modelState { return p }
        return nil
    }

    private func status(_ m: SpeechModel) -> String {
        var parts = [m.languages]
        let size = dictation.sizes[m] ?? 0
        switch m {
        case .apple:
            parts.append(SpeechEngine.shared.isDownloaded(m) ? "Installed" : "Downloads language files once")
        default:
            parts.append(size > 0 && SpeechEngine.shared.isDownloaded(m)
                         ? "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) on disk"
                         : "About \(ByteCountFormatter.string(fromByteCount: m.approxBytes, countStyle: .file))")
        }
        if isSelected(m), case .failed(let e) = dictation.modelState { parts.append(e) }
        else if let e = dictation.downloadError[m] { parts.append(e) }
        return parts.joined(separator: " · ")
    }

    private func row(_ m: SpeechModel) -> some View {
        let selected = isSelected(m)
        let locked = false
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 16)).foregroundStyle(selected ? DF.ink : DF.checkbox).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(m.name).font(DF.font(14, .semibold))
                    Text("Free").font(DF.font(11, .bold)).foregroundStyle(DF.muted)
                        .padding(.horizontal, 7).frame(height: 20).background(DF.wash, in: Capsule())
                }
                Text(m.summary).font(DF.font(13)).foregroundStyle(DF.muted).fixedSize(horizontal: false, vertical: true)
                Text(status(m)).font(DF.font(12)).foregroundStyle(DF.faint).padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
                if m == .whisper {
                    DFSegmented(items: WhisperVariant.allCases.map { ($0, $0.title) },
                                selection: Binding<WhisperVariant>(get: { dictation.whisperVariant },
                                                                  set: { v in Task { @MainActor in await dictation.selectWhisperVariant(v) } }))
                        .fixedSize().padding(.top, 6)
                    .disabled(progress(.whisper) != nil)
                }
            }
            .opacity(locked ? 0.5 : 1)
            Spacer(minLength: 12)
            trailing(m, locked: locked)
        }
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !locked, !selected else { return }
            Task { await dictation.select(m) }
        }
    }

    @ViewBuilder
    private func trailing(_ m: SpeechModel, locked: Bool) -> some View {
        if let p = progress(m) {
            HStack(spacing: 8) {
                DFProgressBar(value: p).frame(width: 80)
                Text("\(Int(p * 100))%").font(DF.font(12, .semibold)).foregroundStyle(DF.muted).monospacedDigit()
            }
            .frame(height: 30)
        } else if !SpeechEngine.shared.isDownloaded(m) {
            PrimaryButton(title: "Download", symbol: "arrow.down.circle") { Task { await dictation.download(m) } }
        } else {
            HStack(spacing: 8) {
                if isSelected(m) { ModelBadge(state: dictation.modelState) }
                if m != .apple {
                    SecondaryButton(title: "Delete", symbol: "trash") { Task { await dictation.delete(m) } }
                }
            }
        }
    }
}
