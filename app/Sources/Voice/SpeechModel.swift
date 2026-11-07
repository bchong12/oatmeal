import Foundation

/// Speech-to-text models the user can pick in Settings › Models.
/// Persisted in UserDefaults "speech.model"; Parakeet v3 is the default.
enum SpeechModel: String, CaseIterable, Identifiable, Sendable {
    case parakeetV3, parakeetV2, whisper, qwen3, apple

    var id: String { rawValue }

    static let defaultsKey = "speech.model"
    static let defaultModel: SpeechModel = .parakeetV3

    /// The chosen model, or the default if the stored one isn't supported on this Mac.
    static var selected: SpeechModel {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let m = SpeechModel(rawValue: raw), m.isSupported else { return defaultModel }
            return m
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Models that can run on this Mac, in display order.
    static var supported: [SpeechModel] { allCases.filter(\.isSupported) }

    var name: String {
        switch self {
        case .parakeetV3: "Parakeet TDT 0.6B v3"
        case .parakeetV2: "Parakeet TDT 0.6B v2"
        case .whisper: "Whisper"
        case .qwen3: "Qwen3-ASR 0.6B"
        case .apple: "Apple Speech"
        }
    }

    var maker: String {
        switch self {
        case .parakeetV3, .parakeetV2: "NVIDIA"
        case .whisper: "OpenAI"
        case .qwen3: "Alibaba Qwen"
        case .apple: "Apple"
        }
    }

    var languages: String {
        switch self {
        case .parakeetV3: "25 European languages"
        case .parakeetV2: "English"
        case .whisper: "99 languages"
        case .qwen3: "52 languages"
        case .apple: "Your Mac\u{2019}s language"
        }
    }

    /// One line for the Settings row.
    var summary: String {
        switch self {
        case .parakeetV3: "Fast and accurate, run by FluidAudio on the Neural Engine."
        case .parakeetV2: "The most accurate English model, run by FluidAudio."
        case .whisper: "OpenAI\u{2019}s Whisper, run by WhisperKit on the Neural Engine."
        case .qwen3: "Best for Chinese, Japanese, Korean, Arabic and Hindi."
        case .apple: "Built into macOS. Nothing extra to store."
        }
    }

    var onDevice: Bool { true }
    var needsPro: Bool { false }

    /// Rough download size before the model is on disk. 0 when nothing is downloaded by Oatmeal.
    var approxBytes: Int64 {
        switch self {
        case .parakeetV3: 470_000_000
        case .parakeetV2: 470_000_000
        case .whisper: WhisperVariant.selected.approxBytes
        case .qwen3: 3_900_000_000
        case .apple: 0
        }
    }

    var isSupported: Bool {
        switch self {
        case .qwen3:
            if #available(macOS 15, *) { return true }
            return false
        case .apple:
            return AppleSpeechBackend.isSupported
        default:
            return true
        }
    }
}

/// Whisper size, persisted in "speech.whisperVariant". Values are folder
/// names in the argmaxinc/whisperkit-coreml repo.
enum WhisperVariant: String, CaseIterable, Identifiable, Sendable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"

    var id: String { rawValue }
    static let defaultsKey = "speech.whisperVariant"
    static let defaultVariant: WhisperVariant = .largeV3Turbo

    static var selected: WhisperVariant {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(WhisperVariant.init(rawValue:)) ?? defaultVariant }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var title: String {
        switch self {
        case .tiny: "Tiny"
        case .base: "Base"
        case .small: "Small"
        case .largeV3Turbo: "Large v3 Turbo"
        }
    }

    var approxBytes: Int64 {
        switch self {
        case .tiny: 76_000_000
        case .base: 146_000_000
        case .small: 487_000_000
        case .largeV3Turbo: 632_000_000
        }
    }
}
