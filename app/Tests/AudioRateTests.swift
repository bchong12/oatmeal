import XCTest
import AVFoundation
@testable import Dayform

final class AudioRateTests: XCTestCase {
    func testSnapsToStandardRates() {
        XCTAssertEqual(RateCalibrator.snap(15_870), 16_000)
        XCTAssertEqual(RateCalibrator.snap(44_020), 44_100)
        XCTAssertEqual(RateCalibrator.snap(47_700), 48_000)
        XCTAssertNil(RateCalibrator.snap(30_000))
    }

    /// Headphones switched to 16 kHz but the tap still says 48 kHz: after one window the measured rate wins.
    func testMeasuredRateOverridesStaleReportedRate() {
        let c = RateCalibrator(window: 1)
        var t = 0.0, last = 0.0
        for _ in 0..<300 {                       // 3 s of 10 ms callbacks at 16 kHz
            last = c.rate(frames: 160, at: t, reported: 48_000)
            t += 0.01
        }
        XCTAssertEqual(last, 16_000)
    }

    func testKeepsReportedRateWhenItIsRight() {
        let c = RateCalibrator(window: 1)
        var t = 0.0, last = 0.0
        for _ in 0..<300 { last = c.rate(frames: 480, at: t, reported: 48_000); t += 0.01 }
        XCTAssertEqual(last, 48_000)
    }

    func testMonoFromInterleavedStereoBufferList() {
        var samples: [Float] = [1, 3, 2, 4, -1, -3]   // L R L R L R
        let mono: [Float] = samples.withUnsafeMutableBytes { raw in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
            return AudioSamples.monoFloats(&list)
        }
        XCTAssertEqual(mono, [2, 3, -2])
    }

    func testFlagsRepeatedFiller() {
        XCTAssertTrue(AudioSamples.looksInvented("Wait, wait, wait, wait, wait, wait."))
        XCTAssertTrue(AudioSamples.looksInvented("Oh, wait, wait, wait, wait, wait, wait."))
        XCTAssertFalse(AudioSamples.looksInvented("Yeah, I'll send it over tomorrow."))
        XCTAssertFalse(AudioSamples.looksInvented("Wait, what?"))
    }
}

/// The real failure, end to end: call audio arriving at 16 kHz (Bluetooth headset mode) while the
/// tap still reports 48 kHz. Before the fix this came out as "What's up with the floor?".
final class BluetoothRateTranscriptionTests: XCTestCase {
    func testTranscribesCallAudioAfterHeadsetRateDrop() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dayform-rate-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000",
                         "Thanks for jumping on. We could do a recurring affiliate share instead of paying up front."]
        try say.run(); say.waitUntilExit()
        guard say.terminationStatus == 0 else { throw XCTSkip("say couldn't render audio") }
        guard SpeechEngine.isDownloaded(SpeechModel.selected) else { throw XCTSkip("speech model not downloaded") }

        let file = try AVAudioFile(forReading: url)
        let buf = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buf)
        let raw = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))

        let calibrator = RateCalibrator(window: 1)
        var out: [Float] = [], t = 0.0
        for start in stride(from: 0, to: raw.count, by: 160) {      // 10 ms callbacks in real time
            out += calibrator.process(Array(raw[start..<min(start + 160, raw.count)]), at: t, reported: 48_000)
            t += 0.01
        }
        XCTAssertEqual(out.count, raw.count, "16 kHz in, 16 kHz out: nothing squashed or dropped")
        await DictationService.shared.prepareModel()
        let text = try await SpeechEngine.shared.transcribe(out, source: .system).lowercased()
        XCTAssertTrue(text.contains("thanks"), text)
        XCTAssertTrue(text.contains("affiliate"), text)
    }
}
