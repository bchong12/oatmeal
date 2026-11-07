import AVFoundation

/// Small sample-wrangling helpers shared by dictation and meetings.
/// Everything downstream of capture works in 16 kHz mono Float32, which is
/// what Parakeet wants.
enum AudioSamples {

    static let targetRate: Double = 16_000

    /// Resample + mono-sum a captured AVAudioPCMBuffer down to 16 kHz mono Float32.
    /// Linear interpolation; quality is fine for speech transcription.
    static func mono16k(_ buffer: AVAudioPCMBuffer, sourceRate: Double) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frameCount > 0 else { return [] }

        // Mono-sum first. Interleaved buffers (Core Audio process taps hand
        // us interleaved stereo) keep every channel in channelData[0] with
        // a stride of `channels`.
        let interleaved = buffer.format.isInterleaved && channels > 1
        var mono = [Float](repeating: 0, count: frameCount)
        if channels == 1 {
            _ = mono.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress, channelData[0], frameCount * MemoryLayout<Float>.size)
            }
        } else if interleaved {
            let data = channelData[0]
            for i in 0..<frameCount {
                var sum: Float = 0
                for c in 0..<channels { sum += data[i * channels + c] }
                mono[i] = sum / Float(channels)
            }
        } else {
            for c in 0..<channels {
                let chan = channelData[c]
                for i in 0..<frameCount { mono[i] += chan[i] }
            }
            let inv = 1.0 / Float(channels)
            for i in 0..<frameCount { mono[i] *= inv }
        }

        return resample(mono, from: sourceRate)
    }

    /// Linear-interpolation resample of mono samples to 16 kHz.
    static func resample(_ mono: [Float], from sourceRate: Double) -> [Float] {
        let frameCount = mono.count
        guard frameCount > 0, sourceRate > 0 else { return [] }
        if abs(sourceRate - targetRate) < 1 { return mono }
        let ratio = sourceRate / targetRate
        let outputCount = Int(Double(frameCount) / ratio)
        var resampled = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIdx = Double(i) * ratio
            let lo = Int(srcIdx)
            let frac = Float(srcIdx - Double(lo))
            let hi = min(lo + 1, frameCount - 1)
            resampled[i] = mono[lo] * (1 - frac) + mono[hi] * frac
        }
        return resampled
    }

    /// Mono-sums a Float32 AudioBufferList straight from Core Audio, reading each buffer's own
    /// channel count and byte size rather than a format captured earlier (which goes stale when
    /// the output device changes rate or layout mid-call).
    static func monoFloats(_ list: UnsafePointer<AudioBufferList>) -> [Float] {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, first.mNumberChannels > 0 else { return [] }
        if buffers.count == 1 {
            // Interleaved (process taps hand us interleaved stereo).
            let channels = Int(first.mNumberChannels)
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            guard frames > 0, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return [] }
            var mono = [Float](repeating: 0, count: frames)
            let inv = 1 / Float(channels)
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += data[i * channels + c] }
                mono[i] = sum * inv
            }
            return mono
        }
        // Non-interleaved: one buffer per channel.
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard frames > 0 else { return [] }
        var mono = [Float](repeating: 0, count: frames)
        var used = 0
        for b in buffers {
            guard let data = b.mData?.assumingMemoryBound(to: Float.self), Int(b.mDataByteSize) / MemoryLayout<Float>.size >= frames else { continue }
            for i in 0..<frames { mono[i] += data[i] }
            used += 1
        }
        guard used > 0 else { return [] }
        let inv = 1 / Float(used)
        for i in 0..<frames { mono[i] *= inv }
        return mono
    }
}

/// Works out the rate audio really arrives at by counting frames against the clock, and snaps it
/// to a standard rate. Bluetooth headphones drop from 44.1/48 kHz to 16 kHz the moment their mic
/// opens; trusting the rate read at start-up then plays the call back ~3x too fast to the speech
/// model, which turns it into made-up words with timestamps a third of the real time.
final class RateCalibrator: @unchecked Sendable {
    static let standardRates: [Double] = [8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000, 88_200, 96_000]

    private let lock = NSLock()
    private let window: Double
    private var windowStart: Double?
    private var frames = 0
    private var measured: Double?
    private var windowsDone = 0

    init(window: Double = 3) { self.window = window }

    /// Nearest standard rate within 6%, or nil when the measurement fits none.
    static func snap(_ rate: Double) -> Double? {
        guard let best = standardRates.min(by: { abs($0 - rate) < abs($1 - rate) }), abs(best - rate) / best < 0.06 else { return nil }
        return best
    }

    /// Feed every callback: frames delivered and the time (seconds, any monotonic clock).
    /// Returns the rate to use: the measured one once it disagrees with `reported`, else `reported`.
    func rate(frames n: Int, at time: Double, reported: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        if let start = windowStart {
            let elapsed = time - start
            if elapsed >= window {
                if let r = Self.snap(Double(frames) / elapsed) { measured = r }
                windowStart = time; frames = 0; windowsDone += 1
            }
        } else {
            windowStart = time
        }
        frames += n
        guard let m = measured, abs(m - reported) / reported > 0.05 else { return reported }
        return m
    }

    private var held: [Float] = []
    private var calibrated = false

    /// Mono frames in, 16 kHz out. The opening window is held back until the rate has been measured
    /// once, then released at that rate, so the first words of a call aren't lost to a stale rate.
    func process(_ mono: [Float], at time: Double, reported: Double) -> [Float] {
        let r = rate(frames: mono.count, at: time, reported: reported)
        lock.lock()
        if !calibrated {
            held += mono
            // One full window has passed (whether or not it snapped to a standard rate).
            if windowsDone > 0 {
                calibrated = true
                let out = held; held = []
                lock.unlock()
                return AudioSamples.resample(out, from: r)
            }
            lock.unlock()
            return []
        }
        lock.unlock()
        return AudioSamples.resample(mono, from: r)
    }
}

/// A value shared between Core Audio's queue and property listeners.
final class LockedValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
}

extension AudioSamples {
    /// Speech models fill silence and noise with a word on repeat ("Wait, wait, wait, wait.").
    /// A chunk that's almost one word over and over is dropped.
    static func looksInvented(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }
        guard words.count >= 4 else { return false }
        return Double(Set(words).count) / Double(words.count) <= 0.34
    }

    static func rms<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return sqrt(sum / Float(samples.count))
    }

    /// RMS-energy gate. Threshold sits above mic noise floor; speech
    /// easily clears it. Used to skip ASR on silent chunks (Parakeet
    /// occasionally hallucinates a word or two on pure room tone).
    static func hasEnergy<C: Collection>(_ samples: C, threshold: Float = 0.004) -> Bool where C.Element == Float {
        rms(samples) > threshold
    }

    /// Pick a cut point near the end of `samples` that lands in the quietest
    /// 100 ms window of the last `searchSeconds`, so a chunk boundary
    /// doesn't slice a word in half. Returns an index into `samples`.
    static func quietCutIndex(_ samples: [Float], searchSeconds: Double = 2.0) -> Int {
        let window = Int(targetRate * 0.1)
        let searchLength = Int(targetRate * searchSeconds)
        guard samples.count > searchLength + window else { return samples.count }

        var bestIndex = samples.count
        var bestEnergy = Float.greatestFiniteMagnitude
        var start = samples.count - searchLength
        while start + window <= samples.count {
            let energy = rms(samples[start..<(start + window)])
            if energy < bestEnergy {
                bestEnergy = energy
                bestIndex = start + window / 2
            }
            start += window / 2
        }
        return bestIndex
    }
}

/// Lock-protected sample accumulator. Capture callbacks fire on audio /
/// SCStream queues, so appends are a lock + array append rather than a
/// main-actor hop (Dollop saw hopped appends silently dropped under load).
final class SampleBuffer: @unchecked Sendable {
    private var samples: [Float] = []
    private let lock = NSLock()

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    func append(_ newSamples: [Float]) {
        lock.lock()
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    /// Copy without draining
    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    /// Remove and return the first `count` samples (or everything)
    func drain(upTo count: Int? = nil) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let n = min(count ?? samples.count, samples.count)
        let out = Array(samples.prefix(n))
        samples.removeFirst(n)
        return out
    }

    func removeAll() {
        lock.lock()
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}
