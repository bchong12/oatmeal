import Foundation
import FluidAudio

/// Transcription engine shared by dictation and meetings. Dispatches to the
/// model picked in Settings (`SpeechModel.selected`), so only one model is
/// downloaded + loaded for both.
///
/// An actor so concurrent `load()` calls collapse into one download, and so
/// dictation partials and meeting chunks never race model setup. Calls are
/// chained per `AudioSource`, so the mic ("You") and system ("Them") streams
/// each run in order (Parakeet keeps separate decoder state per source).
actor SpeechEngine {
    static let shared = SpeechEngine()

    private var backends: [String: any SpeechBackend] = [:]
    private var active: (any SpeechBackend)?
    private var loadTask: (key: String, task: Task<Void, Error>)?
    /// Last queued transcription per source; chained so calls never interleave.
    private var micTail: Task<Void, Never>?
    private var systemTail: Task<Void, Never>?

    static let sampleRate: Double = 16_000

    var isLoaded: Bool { active != nil }
    /// The model currently in memory, if any.
    var loadedModel: SpeechModel? { active?.model }

    // MARK: Disk (nonisolated, for the UI)

    /// Is the selected model on disk (without loading)?
    nonisolated var isDownloaded: Bool { isDownloaded(SpeechModel.selected) }

    nonisolated func isDownloaded(_ m: SpeechModel) -> Bool { Self.isDownloaded(m) }

    nonisolated static func isDownloaded(_ m: SpeechModel) -> Bool {
        switch m {
        case .parakeetV3: return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
        case .parakeetV2: return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v2), version: .v2)
        case .whisper: return WhisperBackend.isDownloaded(WhisperVariant.selected)
        case .qwen3:
            if #available(macOS 15, *) { return Qwen3AsrModels.modelsExist(at: Qwen3AsrModels.defaultCacheDirectory()) }
            return false
        case .apple: return AppleSpeechBackend.isSupported && AppleSpeechBackend.assetsInstalled
        }
    }

    /// Where a model lives on disk; nil for Apple Speech and Cloud.
    nonisolated static func directory(_ m: SpeechModel) -> URL? {
        switch m {
        case .parakeetV3: return AsrModels.defaultCacheDirectory(for: .v3)
        case .parakeetV2: return AsrModels.defaultCacheDirectory(for: .v2)
        case .whisper: return WhisperBackend.folder(WhisperVariant.selected)
        case .qwen3:
            if #available(macOS 15, *) { return Qwen3AsrModels.defaultCacheDirectory() }
            return nil
        case .apple: return nil
        }
    }

    nonisolated static func modelSize(_ m: SpeechModel) -> Int64 { SpeechDisk.size(of: directory(m)) }
    nonisolated func modelSize(_ m: SpeechModel) -> Int64 { Self.modelSize(m) }

    /// Selected model's folder, for Settings › Models.
    nonisolated static var modelDirectory: URL { directory(SpeechModel.selected) ?? SpeechDisk.oatmealModels }
    nonisolated static var modelSizeOnDisk: Int64 { modelSize(SpeechModel.selected) }

    // MARK: Backends

    nonisolated static func backendKey(_ m: SpeechModel) -> String {
        m == .whisper ? "whisper:\(WhisperVariant.selected.rawValue)" : m.rawValue
    }

    /// The backend that runs `m` (one instance per model, and per Whisper size).
    func backend(for m: SpeechModel) -> any SpeechBackend {
        let key = Self.backendKey(m)
        if let b = backends[key] { return b }
        let b: any SpeechBackend
        switch m {
        case .parakeetV3, .parakeetV2: b = ParakeetBackend(m)
        case .whisper: b = WhisperBackend(variant: WhisperVariant.selected)
        case .qwen3:
            if #available(macOS 15, *) { b = Qwen3Backend() } else { b = ParakeetBackend(.parakeetV3) }
        case .apple: b = AppleSpeechBackend()
        }
        backends[key] = b
        return b
    }

    // MARK: Lifecycle

    /// Download (if needed) and load the selected model, unloading whatever
    /// was loaded before. Safe to call repeatedly; callers that arrive
    /// mid-load await the same task.
    func load(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let m = SpeechModel.selected
        let key = Self.backendKey(m)
        if let active, active.key == key, await active.isLoaded { return }
        if let loadTask, loadTask.key == key {
            try await loadTask.task.value
            return
        }
        if let old = active, old.key != key {
            active = nil
            await old.unload()
        }
        let b = backend(for: m)
        let task = Task<Void, Error> { try await b.load(progress: progress) }
        loadTask = (key, task)
        do {
            try await task.value
            if loadTask?.key == key { loadTask = nil }
            // The user switched while this loaded and the new model is up: drop this one.
            if let current = active, current.key != key, Self.backendKey(SpeechModel.selected) == current.key {
                await b.unload()
                return
            }
            if let old = active, old.key != key { await old.unload() }
            active = b
        } catch {
            if loadTask?.key == key { loadTask = nil }
            throw error
        }
    }

    /// Fetch a model's files without switching to it.
    func download(_ m: SpeechModel, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await backend(for: m).download(progress: progress)
    }

    /// Free the loaded model's memory.
    func unload() async {
        let old = active
        active = nil
        loadTask?.task.cancel(); loadTask = nil
        await old?.unload()
    }

    /// Unload and remove a model. It downloads again on next use.
    func delete(_ m: SpeechModel) async throws {
        let b = backend(for: m)
        if active?.key == b.key { active = nil }
        if loadTask?.key == b.key { loadTask?.task.cancel(); loadTask = nil }
        try await b.delete()
    }

    /// Unload and remove the selected model.
    func deleteModel() async throws { try await delete(SpeechModel.selected) }

    // MARK: Transcribe

    /// Transcribe 16 kHz mono Float32 samples with the selected model.
    /// Returns "" for clips too short to hold a word. If the selection
    /// changed and the new model is already on disk, it's loaded first.
    func transcribe(_ samples: [Float], source: AudioSource = .microphone) async throws -> String {
        let minWordSamples = Int(Self.sampleRate * 0.3)
        let selected = SpeechModel.selected
        let key = Self.backendKey(selected)
        if active?.key != key {
            guard loadTask?.key == key || isDownloaded(selected) else { throw SpeechEngineError.notLoaded }
            try await load()
        }
        guard let backend = active else { throw SpeechEngineError.notLoaded }
        guard samples.count >= minWordSamples else { return "" }

        let isMic = source == .microphone
        let prior = isMic ? micTail : systemTail
        let task = Task<String, Error> {
            _ = await prior?.value
            return try await backend.transcribe(samples, source: source)
        }
        let tail = Task<Void, Never> { _ = try? await task.value }
        if isMic { micTail = tail } else { systemTail = tail }
        return Self.clean(try await task.value)
    }

    /// Strip bracketed non-speech tags ("[music]", "(laughs)", Whisper's
    /// "<|en|>") and collapse whitespace
    static func clean(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum SpeechEngineError: Error, LocalizedError {
        case notLoaded
        var errorDescription: String? {
            switch self {
            case .notLoaded: return "The speech model isn't loaded yet."
            }
        }
    }
}
