import XCTest
import AVFoundation
@testable import Dayform

final class SpeechModelTests: XCTestCase {
    private var saved: [String: Any?] = [:]
    private let keys = [SpeechModel.defaultsKey, WhisperVariant.defaultsKey, CloudSpeechModel.defaultsKey]

    override func setUp() {
        super.setUp()
        for k in keys { saved[k] = UserDefaults.standard.object(forKey: k) }
    }

    override func tearDown() {
        for k in keys {
            if let v = saved[k] ?? nil { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) }
        }
        super.tearDown()
    }

    // MARK: Metadata + persistence

    func testMetadata() {
        XCTAssertEqual(SpeechModel.allCases.count, 6)
        for m in SpeechModel.allCases {
            XCTAssertFalse(m.name.isEmpty); XCTAssertFalse(m.maker.isEmpty)
            XCTAssertFalse(m.languages.isEmpty); XCTAssertFalse(m.summary.isEmpty)
        }
        XCTAssertTrue(SpeechModel.cloud.needsPro)
        XCTAssertFalse(SpeechModel.cloud.onDevice)
        XCTAssertEqual(SpeechModel.allCases.filter(\.needsPro), [.cloud])
        XCTAssertEqual(SpeechModel.parakeetV2.languages, "English")
        XCTAssertTrue(SpeechModel.supported.contains(.parakeetV3))
        XCTAssertGreaterThan(SpeechModel.parakeetV2.approxBytes, 0)
    }

    func testSelectionPersists() {
        UserDefaults.standard.removeObject(forKey: SpeechModel.defaultsKey)
        XCTAssertEqual(SpeechModel.selected, .parakeetV3)
        SpeechModel.selected = .whisper
        XCTAssertEqual(UserDefaults.standard.string(forKey: "speech.model"), "whisper")
        XCTAssertEqual(SpeechModel.selected, .whisper)
        UserDefaults.standard.set("nonsense", forKey: SpeechModel.defaultsKey)
        XCTAssertEqual(SpeechModel.selected, .parakeetV3)

        UserDefaults.standard.removeObject(forKey: WhisperVariant.defaultsKey)
        XCTAssertEqual(WhisperVariant.selected, .largeV3Turbo)
        WhisperVariant.selected = .small
        XCTAssertEqual(UserDefaults.standard.string(forKey: "speech.whisperVariant"), "openai_whisper-small")

        UserDefaults.standard.removeObject(forKey: CloudSpeechModel.defaultsKey)
        XCTAssertEqual(CloudSpeechModel.selected.rawValue, "deepgram/nova-3")
        CloudSpeechModel.selected = .scribe
        XCTAssertEqual(CloudSpeechModel.selected, .scribe)
    }

    // MARK: Dispatch

    func testDispatchPicksBackend() async {
        let engine = SpeechEngine.shared
        let v3 = await engine.backend(for: .parakeetV3)
        XCTAssertTrue(v3 is ParakeetBackend)
        XCTAssertEqual((v3 as? ParakeetBackend)?.version, .v3)
        let v2 = await engine.backend(for: .parakeetV2)
        XCTAssertEqual((v2 as? ParakeetBackend)?.version, .v2)
        XCTAssertEqual(v2.model, .parakeetV2)

        WhisperVariant.selected = .tiny
        let tiny = await engine.backend(for: .whisper)
        XCTAssertEqual((tiny as? WhisperBackend)?.variant, .tiny)
        WhisperVariant.selected = .base
        let base = await engine.backend(for: .whisper)
        XCTAssertEqual((base as? WhisperBackend)?.variant, .base)
        XCTAssertNotEqual(tiny.key, base.key)

        let apple = await engine.backend(for: .apple)
        XCTAssertTrue(apple is AppleSpeechBackend)
        let cloud = await engine.backend(for: .cloud)
        XCTAssertTrue(cloud is CloudSpeechBackend)
        XCTAssertEqual((cloud as? CloudSpeechBackend)?.fallback.model, .parakeetV3)
        if #available(macOS 15, *) {
            let q = await engine.backend(for: .qwen3)
            XCTAssertTrue(q is Qwen3Backend)
        }
        // Same instance on repeat lookups
        let again = await engine.backend(for: .parakeetV2)
        XCTAssertTrue(again === v2)
    }

    func testDiskInfo() {
        XCTAssertEqual(SpeechEngine.directory(.parakeetV2)?.lastPathComponent, "parakeet-tdt-0.6b-v2")
        XCTAssertNil(SpeechEngine.directory(.cloud))
        XCTAssertTrue(SpeechEngine.shared.isDownloaded(.cloud))
        WhisperVariant.selected = .small
        XCTAssertEqual(SpeechEngine.directory(.whisper)?.lastPathComponent, "openai_whisper-small")
    }

    func testWavEncoding() {
        let wav = CloudSpeechBackend.wav([0, 0.5, -0.5, 1], sampleRate: 16_000)
        XCTAssertEqual(wav.count, 44 + 8)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        let rate = wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: rate), 16_000)
    }

    // MARK: Round trips (real models, say → 16 kHz)

    private func speak(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dayform-say-\(UUID().uuidString).wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "Samantha", "-o", url.path, "--data-format=LEF32@16000", text]
        try p.run(); p.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    }

    private func roundTrip(_ m: SpeechModel) async throws -> String {
        SpeechModel.selected = m
        defer { SpeechModel.selected = .parakeetV3 }
        let engine = SpeechEngine.shared
        try await engine.load()
        let loaded = await engine.loadedModel
        XCTAssertEqual(loaded, m)
        let out = try await engine.transcribe(try speak("Send the revised quote to Priya by Friday."))
        print("[SpeechModelTest] \(m.rawValue): \(out)")
        await engine.unload()
        return out
    }

    func testParakeetV2RoundTrip() async throws {
        let out = try await roundTrip(.parakeetV2).lowercased()
        XCTAssertTrue(out.contains("revised quote"), out)
        XCTAssertTrue(out.contains("friday"), out)
    }

    /// Only when Qwen3-ASR is already on disk (it's a ~4 GB download).
    func testQwen3RoundTrip() async throws {
        guard #available(macOS 15, *), SpeechEngine.shared.isDownloaded(.qwen3) else { throw XCTSkip("Qwen3-ASR not downloaded") }
        let out = try await roundTrip(.qwen3).lowercased()
        XCTAssertTrue(out.contains("quote"), out)
        XCTAssertTrue(out.contains("friday"), out)
    }

    /// Opt in with TEST_RUNNER_DAYFORM_SPEECH_E2E=1 (downloads Whisper tiny).
    func testWhisperTinyRoundTrip() async throws {
        guard ProcessInfo.processInfo.environment["DAYFORM_SPEECH_E2E"] == "1" else { throw XCTSkip("Set DAYFORM_SPEECH_E2E=1") }
        WhisperVariant.selected = .tiny
        let out = try await roundTrip(.whisper).lowercased()
        XCTAssertTrue(out.contains("friday"), out)
    }

    /// Opt in with TEST_RUNNER_DAYFORM_SPEECH_E2E=1 (needs the speech recognition plist key or macOS 26).
    func testAppleRoundTrip() async throws {
        guard ProcessInfo.processInfo.environment["DAYFORM_SPEECH_E2E"] == "1", SpeechModel.apple.isSupported
        else { throw XCTSkip("Set DAYFORM_SPEECH_E2E=1") }
        let out = try await roundTrip(.apple).lowercased()
        XCTAssertTrue(out.contains("friday"), out)
    }
}
