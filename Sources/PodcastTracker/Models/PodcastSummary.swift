import Foundation

struct PodcastSummary: Identifiable, Codable, Hashable, Sendable {
    struct Topic: Identifiable, Codable, Hashable, Sendable {
        var id = UUID()
        var title: String
        var explanation: String
        var timestampSeconds: Double?
    }

    struct Takeaway: Identifiable, Codable, Hashable, Sendable {
        var id = UUID()
        var title: String
        var explanation: String
    }

    struct ActionStep: Identifiable, Codable, Hashable, Sendable {
        var id = UUID()
        var title: String
        var detail: String
        var isCompleted = false
    }

    var podcastID: UUID
    var brief: String
    var keyTopics: [Topic]
    var majorTakeaways: [Takeaway]
    var actionPlan: [ActionStep]
    var generatedAt: Date
    var transcriptSource: TranscriptSource
    var model: String
    var actionPlanXPGranted = false

    var id: UUID { podcastID }
}

enum TranscriptSource: String, Codable, Sendable {
    case captions
    case groqWhisper
    case imported
    case pasted
}

struct TranscriptSegment: Codable, Hashable, Sendable {
    var text: String
    var startSeconds: Double
    var durationSeconds: Double?
}

struct TranscriptDocument: Codable, Hashable, Sendable {
    var podcastID: UUID
    var source: TranscriptSource
    var text: String
    var segments: [TranscriptSegment]
    var createdAt: Date = Date()
}
