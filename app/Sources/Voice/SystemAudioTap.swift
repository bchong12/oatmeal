import AVFoundation
import CoreAudio

/// System audio via a Core Audio process tap (macOS 14.2+).
///
/// Taps every process's output except our own, wraps the tap in a private
/// aggregate device, and reads it with an IOProc. Unlike ScreenCaptureKit
/// this only needs the "audio capture" grant (NSAudioCaptureUsageDescription),
/// not Screen Recording, and never touches video.
///
/// Setup order matters: tap → aggregate device (with the tap in its tap
/// list) → IOProc → start. Teardown runs in reverse and is safe to call
/// after a partial setup.
@available(macOS 14.2, *)
final class SystemAudioTap: @unchecked Sendable {

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// The tap's sample rate right now. Re-read whenever Core Audio says the tap's format or the
    /// device's rate changed (Bluetooth headphones switch to 16 kHz once their mic opens).
    private let reportedRate = LockedValue<Double>(48_000)
    private let calibrator = RateCalibrator()
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let queue = DispatchQueue(label: "com.oatmeal.meeting.tap", qos: .userInitiated)

    /// Begin tapping. `onSamples` gets mono 16 kHz Float32 on the tap queue.
    func start(onSamples: @escaping ([Float]) -> Void) throws {
        do {
            try setUp(onSamples: onSamples)
            print("[SystemTap] system audio running via process tap")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
        listeners = []
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Setup

    private func setUp(onSamples: @escaping ([Float]) -> Void) throws {
        // 1. Tap everything except our own process (no feedback from our sounds).
        let exclude = CoreAudioProps.processObject(for: getpid()).map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
        description.uuid = UUID()
        description.name = "Oatmeal meeting tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "create process tap")

        // 2. Read the tap's stream format so we can wrap IOProc buffers.
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd), "read tap format")
        guard AVAudioFormat(streamDescription: &asbd) != nil else {
            throw TapError.failed("unsupported tap format")
        }
        guard asbd.mFormatID == kAudioFormatLinearPCM, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32 else {
            throw TapError.failed("tap isn't Float32 PCM")
        }
        reportedRate.value = asbd.mSampleRate

        // 3. Private aggregate device: default output as the clock source,
        //    our tap as its input.
        guard let outputUID = CoreAudioProps.defaultOutputDeviceUID() else {
            throw TapError.failed("no default output device")
        }
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Oatmeal Meeting Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID),
                  "create aggregate device")

        // 4. Follow rate changes: the tap's own format, and the aggregate (clocked by the output device).
        watch(tapID, kAudioTapPropertyFormat)
        watch(aggregateID, kAudioDevicePropertyNominalSampleRate)

        // 5. IOProc: read the buffers as they actually are (channels and size from the buffer list),
        //    at the rate they actually arrive, and downmix to 16 kHz mono.
        let reported = reportedRate, calibrator = calibrator
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let secondsPerTick = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inputData, inputTime, _, _ in
            let mono = AudioSamples.monoFloats(inputData)
            guard !mono.isEmpty else { return }
            let host = inputTime.pointee.mFlags.contains(.hostTimeValid) ? inputTime.pointee.mHostTime : mach_absolute_time()
            let samples = calibrator.process(mono, at: Double(host) * secondsPerTick, reported: reported.value)
            if !samples.isEmpty { onSamples(samples) }
        }, "create IOProc")

        // 6. Go. The first start shows the system "capture audio" prompt.
        try check(AudioDeviceStart(aggregateID, procID), "start aggregate device")
    }

    /// Re-reads the tap's rate when `selector` changes on `object`.
    private func watch(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let tap = tapID, reported = reportedRate
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            var asbd = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var a = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(tap, &a, 0, nil, &size, &asbd) == noErr, asbd.mSampleRate > 0 else { return }
            if asbd.mSampleRate != reported.value {
                print("[SystemTap] rate changed \(Int(reported.value)) → \(Int(asbd.mSampleRate)) Hz")
                reported.value = asbd.mSampleRate
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw TapError.failed("\(step) (OSStatus \(status))") }
    }

    enum TapError: Error, LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .failed(let why): return "System audio tap failed: \(why)"
            }
        }
    }
}

/// Small Core Audio property readers shared by the tap and meeting detection.
enum CoreAudioProps {

    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr, object != kAudioObjectUnknown else { return nil }
        return object
    }

    static func defaultOutputDeviceUID() -> String? {
        guard let device = defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice) else { return nil }
        return string(device, kAudioDevicePropertyDeviceUID)
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}
