import Foundation

/// One timestamped line of a meeting transcript. `speaker` is "You" for the
/// mic side and "Them" for system audio (whoever is on the call).
struct TranscriptSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var speaker: String
    var text: String
    /// Seconds of recorded (non-paused) audio before this line started.
    var offset: TimeInterval

    init(id: UUID = UUID(), speaker: String, text: String, offset: TimeInterval) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.offset = offset
    }
}

extension Array where Element == TranscriptSegment {
    /// The transcript as plain text for copying: "[03:41] Them: ..." one line each.
    var plainText: String {
        map { "[\(Duration.seconds($0.offset).formatted(.time(pattern: .minuteSecond)))] \($0.speaker): \($0.text)" }
            .joined(separator: "\n")
    }
}

/// Everything a finished meeting hands back to the UI.
struct MeetingRecording: Codable {
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    var segments: [TranscriptSegment]
    var audioURL: URL?
}

/// Lifecycle of the local Parakeet model.
enum VoiceModelState: Equatable {
    case notLoaded
    case downloading(Double)
    case ready
    case failed(String)
}
