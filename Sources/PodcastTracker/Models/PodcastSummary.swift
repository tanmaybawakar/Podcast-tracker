import Foundation

struct PodcastSummary: Identifiable, Codable, Hashable, Sendable {
    struct Section: Identifiable, Codable, Hashable, Sendable {
        struct Point: Identifiable, Codable, Hashable, Sendable {
            var id = UUID()
            var title: String
            var explanation: String
            var timestampSeconds: Double?
        }

        var id = UUID()
        var title: String
        var introduction: String?
        var points: [Point]
    }

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
    /// Transcript-specific sections. Empty only for summaries created before the dynamic format.
    var sections: [Section] = []
    var generatedAt: Date
    var transcriptSource: TranscriptSource
    var model: String
    var actionPlanXPGranted = false

    var id: UUID { podcastID }

    init(podcastID: UUID, brief: String, keyTopics: [Topic], majorTakeaways: [Takeaway], actionPlan: [ActionStep], sections: [Section] = [], generatedAt: Date, transcriptSource: TranscriptSource, model: String, actionPlanXPGranted: Bool = false) {
        self.podcastID = podcastID; self.brief = brief; self.keyTopics = keyTopics
        self.majorTakeaways = majorTakeaways; self.actionPlan = actionPlan; self.sections = sections
        self.generatedAt = generatedAt; self.transcriptSource = transcriptSource; self.model = model
        self.actionPlanXPGranted = actionPlanXPGranted
    }

    enum CodingKeys: String, CodingKey { case podcastID, brief, keyTopics, majorTakeaways, actionPlan, sections, generatedAt, transcriptSource, model, actionPlanXPGranted }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        podcastID = try c.decode(UUID.self, forKey: .podcastID); brief = try c.decode(String.self, forKey: .brief)
        keyTopics = try c.decode([Topic].self, forKey: .keyTopics); majorTakeaways = try c.decode([Takeaway].self, forKey: .majorTakeaways)
        actionPlan = try c.decode([ActionStep].self, forKey: .actionPlan); sections = try c.decodeIfPresent([Section].self, forKey: .sections) ?? []
        generatedAt = try c.decode(Date.self, forKey: .generatedAt); transcriptSource = try c.decode(TranscriptSource.self, forKey: .transcriptSource)
        model = try c.decode(String.self, forKey: .model); actionPlanXPGranted = try c.decodeIfPresent(Bool.self, forKey: .actionPlanXPGranted) ?? false
    }
}

enum TranscriptSource: String, Codable, Sendable {
    case transcriptAPI
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
