import XCTest
import AVFoundation
@testable import Dayform

/// End to end without a microphone: macOS `say` speaks a sentence into a file,
/// Parakeet (on this Mac) transcribes it, and the clean-up runs on the result.
final class VoicePipelineTests: XCTestCase {
    private func speak(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dayform-say-\(UUID().uuidString).wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "Samantha", "-o", url.path, "--data-format=LEF32@16000", text]
        try p.run(); p.waitUntilExit()
        let file = try AVAudioFile(forReading: url)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    }

    private func transcribe(_ text: String) async throws -> String {
        try await SpeechEngine.shared.load()
        return try await SpeechEngine.shared.transcribe(try speak(text))
    }

    func testDictationRoundTrip() async throws {
        let raw = try await transcribe("Send the revised quote to Priya by Friday and book a review next week.")
        let out = TextFormatter.format(raw, options: .init())
        print("[VoiceTest] raw: \(raw) → \(out)")
        let l = out.lowercased()
        XCTAssertTrue(l.contains("revised quote"), out)
        XCTAssertTrue(l.contains("friday"), out)
        XCTAssertTrue(out.first?.isUppercase ?? false, out)
    }

    func testSpokenPunctuationRoundTrip() async throws {
        let raw = try await transcribe("Hey comma can you check this question mark")
        let out = TextFormatter.format(raw, options: .init())
        print("[VoiceTest] raw: \(raw) → \(out)")
        XCTAssertFalse(out.lowercased().contains("question mark"), out)
        XCTAssertTrue(out.hasSuffix("?") && !out.hasSuffix("??"), out)
    }

    func testTaskFromSpeech() async throws {
        let raw = try await transcribe("Call mum tomorrow at 5 pm for half an hour")
        let p = QuickAddParser.parse(TextFormatter.format(raw, options: .init()))
        print("[VoiceTest] raw: \(raw) → \(p.title) day:\(String(describing: p.day)) min:\(p.startMinute) dur:\(String(describing: p.minutes))")
        XCTAssertTrue(["call mum", "call mom"].contains(p.title.lowercased()), p.title)
        XCTAssertEqual(p.startMinute, 17 * 60)
        XCTAssertEqual(p.minutes, 30)
        XCTAssertNotNil(p.day)
    }
}
