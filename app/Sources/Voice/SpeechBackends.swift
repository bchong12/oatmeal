@preconcurrency import AVFoundation
import Foundation
import FluidAudio
import Speech
import WhisperKit

/// One speech-to-text model. `SpeechEngine` owns the instances, makes sure
/// only one is loaded at a time, and serialises calls per audio source.
/// Disk checks are nonisolated so the UI can ask without awaiting.
protocol SpeechBackend: Actor {
    nonisolated var model: SpeechModel { get }
    /// Changes when the on-disk identity changes (the Whisper size).
    nonisolated var key: String { get }
    nonisolated var isDownloaded: Bool { get }
    nonisolated var directory: URL? { get }
    var isLoaded: Bool { get }
    /// Fetch the model files without loading them.
    func download(progress: (@Sendable (Double) -> Void)?) async throws
    /// Download if needed, then load into memory.
    func load(progress: (@Sendable (Double) -> Void)?) async throws
    /// 16 kHz mono Float32 in, raw text out (SpeechEngine cleans it).
    func transcribe(_ samples: [Float], source: AudioSource) async throws -> String
    func unload() async
    func delete() async throws
}

enum SpeechBackendError: Error, LocalizedError {
    case notLoaded, unsupported(String), permissionDenied
    var errorDescription: String? {
        switch self {
        case .notLoaded: "The speech model isn\u{2019}t loaded yet."
        case .unsupported(let why): why
        case .permissionDenied: "Speech recognition isn\u{2019}t allowed for Oatmeal."
        }
    }
}

enum SpeechDisk {
    static func size(of url: URL?) -> Int64 {
        guard let url, let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// ~/Library/Application Support/Oatmeal/Models
    static var oatmealModels: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Oatmeal/Models", isDirectory: true)
    }

    /// Pad clips under 1 s with silence (Parakeet and Qwen3 reject or misread them).
    static func padToOneSecond(_ samples: [Float]) -> [Float] {
        let oneSecond = Int(AudioSamples.targetRate)
        guard samples.count < oneSecond else { return samples }
        return samples + [Float](repeating: 0, count: oneSecond - samples.count + 160)
    }
}

// MARK: - Parakeet (FluidAudio)

actor ParakeetBackend: SpeechBackend {
    nonisolated let model: SpeechModel
    nonisolated let version: AsrModelVersion
    private var manager: AsrManager?

    init(_ model: SpeechModel) {
        self.model = model
        self.version = model == .parakeetV2 ? .v2 : .v3
    }

    nonisolated var key: String { model.rawValue }
    nonisolated var directory: URL? { AsrModels.defaultCacheDirectory(for: version) }
    nonisolated var isDownloaded: Bool { AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version) }
    var isLoaded: Bool { manager != nil }

    func download(progress: (@Sendable (Double) -> Void)?) async throws {
        try await AsrModels.download(version: version, progressHandler: { p in progress?(p.fractionCompleted) })
    }

    func load(progress: (@Sendable (Double) -> Void)?) async throws {
        if manager != nil { return }
        print("[SpeechEngine] Loading \(model.name)…")
        let models = try await AsrModels.downloadAndLoad(version: version, progressHandler: { p in progress?(min(p.fractionCompleted, 0.95)) })
        let m = AsrManager(config: .default)
        try await m.loadModels(models)
        manager = m
        progress?(1)
        print("[SpeechEngine] \(model.name) ready")
    }

    func transcribe(_ samples: [Float], source: AudioSource) async throws -> String {
        guard let manager else { throw SpeechBackendError.notLoaded }
        return try await manager.transcribe(SpeechDisk.padToOneSecond(samples), source: source).text
    }

    func unload() async { manager = nil }

    func delete() async throws {
        manager = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}

// MARK: - Qwen3-ASR (FluidAudio, macOS 15+)

@available(macOS 15, *)
actor Qwen3Backend: SpeechBackend {
    nonisolated let model: SpeechModel = .qwen3
    private var manager: Qwen3AsrManager?
    /// Its KV cache holds ~38 s of audio, so longer clips go in 30 s windows.
    static let windowSamples = 30 * 16_000

    nonisolated var key: String { model.rawValue }
    nonisolated var directory: URL? { Qwen3AsrModels.defaultCacheDirectory() }
    nonisolated var isDownloaded: Bool { Qwen3AsrModels.modelsExist(at: Qwen3AsrModels.defaultCacheDirectory()) }
    var isLoaded: Bool { manager != nil }

    func download(progress: (@Sendable (Double) -> Void)?) async throws {
        try await Qwen3AsrModels.download(progressHandler: { p in progress?(p.fractionCompleted) })
    }

    func load(progress: (@Sendable (Double) -> Void)?) async throws {
        if manager != nil { return }
        print("[SpeechEngine] Loading Qwen3-ASR…")
        let dir = try await Qwen3AsrModels.download(progressHandler: { p in progress?(min(p.fractionCompleted, 0.9)) })
        let m = Qwen3AsrManager()
        try await m.loadModels(from: dir)
        manager = m
        progress?(1)
        print("[SpeechEngine] Qwen3-ASR ready")
    }

    func transcribe(_ samples: [Float], source: AudioSource) async throws -> String {
        guard let manager else { throw SpeechBackendError.notLoaded }
        let input = SpeechDisk.padToOneSecond(samples)
        var parts: [String] = []
        for start in stride(from: 0, to: input.count, by: Self.windowSamples) {
            let window = Array(input[start..<min(start + Self.windowSamples, input.count)])
            guard window.count >= 16_000 / 4 else { continue }
            let text = try await manager.transcribe(audioSamples: window, language: String?.none)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: " ")
    }

    func unload() async { manager = nil }

    func delete() async throws {
        manager = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}

// MARK: - Whisper (WhisperKit)

actor WhisperBackend: SpeechBackend {
    nonisolated let model: SpeechModel = .whisper
    nonisolated let variant: WhisperVariant
    private var kit: WhisperKit?

    init(variant: WhisperVariant) { self.variant = variant }

    static var downloadBase: URL { SpeechDisk.oatmealModels.appendingPathComponent("WhisperKit", isDirectory: true) }
    static let repo = "argmaxinc/whisperkit-coreml"

    static func folder(_ v: WhisperVariant) -> URL {
        downloadBase.appendingPathComponent("models/\(repo)/\(v.rawValue)", isDirectory: true)
    }

    static func isDownloaded(_ v: WhisperVariant) -> Bool {
        let dir = folder(v)
        return ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    nonisolated var key: String { "whisper:\(variant.rawValue)" }
    nonisolated var directory: URL? { Self.folder(variant) }
    nonisolated var isDownloaded: Bool { Self.isDownloaded(variant) }
    var isLoaded: Bool { kit != nil }

    @discardableResult
    private func fetch(_ progress: (@Sendable (Double) -> Void)?, cap: Double = 1) async throws -> URL {
        if Self.isDownloaded(variant) { return Self.folder(variant) }
        try FileManager.default.createDirectory(at: Self.downloadBase, withIntermediateDirectories: true)
        return try await WhisperKit.download(variant: variant.rawValue, downloadBase: Self.downloadBase, from: Self.repo,
                                             progressCallback: { p in progress?(min(p.fractionCompleted, cap)) })
    }

    func download(progress: (@Sendable (Double) -> Void)?) async throws {
        try await fetch(progress)
    }

    func load(progress: (@Sendable (Double) -> Void)?) async throws {
        if kit != nil { return }
        print("[SpeechEngine] Loading Whisper \(variant.title)…")
        let folder = try await fetch(progress, cap: 0.9)
        let config = WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: Self.downloadBase,
                                      verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
        kit = try await WhisperKit(config)
        progress?(1)
        print("[SpeechEngine] Whisper \(variant.title) ready")
    }

    func transcribe(_ samples: [Float], source: AudioSource) async throws -> String {
        guard let kit else { throw SpeechBackendError.notLoaded }
        let options = DecodingOptions(task: .transcribe, language: nil, temperature: 0, detectLanguage: true,
                                      skipSpecialTokens: true, withoutTimestamps: true, noSpeechThreshold: 0.6)
        let results: [TranscriptionResult] = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }

    func unload() async {
        await kit?.unloadModels()
        kit = nil
    }

    func delete() async throws {
        await unload()
        try? FileManager.default.removeItem(at: Self.folder(variant))
    }
}

// MARK: - Apple (SpeechAnalyzer on macOS 26, SFSpeechRecognizer on-device before)

actor AppleSpeechBackend: SpeechBackend {
    nonisolated let model: SpeechModel = .apple
    private var locale: Locale?
    private var loaded = false

    static let usageKey = "NSSpeechRecognitionUsageDescription"
    static var hasUsageKey: Bool { Bundle.main.object(forInfoDictionaryKey: usageKey) != nil }

    static var isSupported: Bool {
        if #available(macOS 26, *) { return SpeechTranscriber.isAvailable }
        // Older macOS: the legacy recognizer needs the plist key, or asking crashes.
        return hasUsageKey && (SFSpeechRecognizer()?.supportsOnDeviceRecognition ?? false)
    }

    /// Whether the speech assets for the current language are installed.
    /// Refreshed in the background because the check is async on macOS 26.
    private static let installed = LockedFlag()

    static func refreshInstalled() async {
        if #available(macOS 26, *) {
            guard let l = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { installed.value = false; return }
            let have = await SpeechTranscriber.installedLocales
            installed.value = have.contains { $0.identifier(.bcp47) == l.identifier(.bcp47) }
        } else {
            installed.value = SFSpeechRecognizer()?.supportsOnDeviceRecognition ?? false
        }
    }

    nonisolated var key: String { model.rawValue }
    nonisolated var directory: URL? { nil }
    static var assetsInstalled: Bool { installed.value }
    nonisolated var isDownloaded: Bool { Self.installed.value }
    var isLoaded: Bool { loaded }

    private func authorize() async throws {
        // Without the Info.plist key, asking would crash; SpeechAnalyzer runs
        // on-device and is tried anyway.
        guard Self.hasUsageKey else {
            if #available(macOS 26, *) { return }
            throw SpeechBackendError.permissionDenied
        }
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        }
        if status != .authorized {
            if #available(macOS 26, *) { return }
            throw SpeechBackendError.permissionDenied
        }
    }

    func download(progress: (@Sendable (Double) -> Void)?) async throws {
        if #available(macOS 26, *) {
            guard let l = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                throw SpeechBackendError.unsupported("Apple Speech doesn\u{2019}t support \(Locale.current.identifier) yet.")
            }
            locale = l
            let module = SpeechTranscriber(locale: l, preset: .transcription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                let p = request.progress
                let ticker = Task { while !Task.isCancelled { progress?(p.fractionCompleted * 0.95); try? await Task.sleep(nanoseconds: 200_000_000) } }
                defer { ticker.cancel() }
                try await request.downloadAndInstall()
            }
            Self.installed.value = true
        } else {
            guard SFSpeechRecognizer()?.supportsOnDeviceRecognition == true else {
                throw SpeechBackendError.unsupported("On-device recognition isn\u{2019}t available for your language.")
            }
            locale = .current
            Self.installed.value = true
        }
        progress?(1)
    }

    func load(progress: (@Sendable (Double) -> Void)?) async throws {
        if loaded { return }
        try await authorize()
        try await download(progress: progress)
        loaded = true
    }

    func transcribe(_ samples: [Float], source: AudioSource) async throws -> String {
        guard loaded, let locale else { throw SpeechBackendError.notLoaded }
        guard let input = Self.buffer(samples) else { return "" }
        if #available(macOS 26, *) {
            return try await Self.analyze(input, locale: locale)
        }
        return try await Self.legacy(input, locale: locale)
    }

    func unload() async { loaded = false }
    func delete() async throws { loaded = false }

    private static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioSamples.targetRate, channels: 1, interleaved: false)!
        guard !samples.isEmpty, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        _ = samples.withUnsafeBufferPointer { memcpy(buf.floatChannelData![0], $0.baseAddress, samples.count * MemoryLayout<Float>.size) }
        return buf
    }

    private static func convert(_ buf: AVAudioPCMBuffer, to fmt: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buf.format == fmt { return buf }
        guard let converter = AVAudioConverter(from: buf.format, to: fmt),
              let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Double(buf.frameLength) * fmt.sampleRate / buf.format.sampleRate) + 1024)
        else { throw SpeechBackendError.unsupported("Couldn\u{2019}t convert audio for Apple Speech.") }
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        if let err { throw err }
        return out
    }

    @available(macOS 26, *)
    private static func analyze(_ buf: AVAudioPCMBuffer, locale: Locale) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) ?? buf.format
        let input = try convert(buf, to: fmt)
        let collector = Task { () -> String in
            var text = ""
            for try await r in transcriber.results { text += String(r.text.characters) }
            return text
        }
        let (stream, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: stream)
        cont.yield(AnalyzerInput(buffer: input))
        cont.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value
    }

    private static func legacy(_ buf: AVAudioPCMBuffer, locale: Locale) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw SpeechBackendError.unsupported("Apple Speech isn\u{2019}t available.")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.append(buf)
        request.endAudio()
        let once = LockedFlag()
        return try await withCheckedThrowingContinuation { c in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard once.setOnce() else { return }
                    // 1110: no speech detected
                    if (error as NSError).code == 1110 { c.resume(returning: "") } else { c.resume(throwing: error) }
                } else if let result, result.isFinal {
                    guard once.setOnce() else { return }
                    c.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}

final class LockedFlag: @unchecked Sendable {
    private var v = false
    private let lock = NSLock()
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
    /// True the first time only.
    func setOnce() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if v { return false }
        v = true
        return true
    }
}

// MARK: - Oatmeal Cloud
