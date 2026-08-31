import Foundation

enum DistractionCue: String, Codable, CaseIterable, Identifiable, Sendable {
    case scrolling
    case streaming
    case anime
    case gaming
    case other
    case notification
    case today
    case momentum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scrolling: "Scrolling"
        case .streaming: "OTT / Streaming"
        case .anime: "Anime"
        case .gaming: "Gaming"
        case .other: "Something else"
        case .notification: "Notification"
        case .today: "Today"
        case .momentum: "Keep going"
        }
    }

    var symbolName: String {
        switch self {
        case .scrolling: "rectangle.stack.badge.play"
        case .streaming: "tv"
        case .anime: "sparkles.tv"
        case .gaming: "gamecontroller"
        case .other: "ellipsis.circle"
        case .notification: "bell"
        case .today: "sun.max"
        case .momentum: "arrow.up.right.circle"
        }
    }

    var isDistraction: Bool {
        switch self {
        case .scrolling, .streaming, .anime, .gaming, .other: true
        case .notification, .today, .momentum: false
        }
    }

    static var rescueChoices: [DistractionCue] { [.scrolling, .streaming, .anime, .gaming, .other] }
}

enum CommitmentLaunchIntent: Equatable, Sendable {
    case explicitUserAction
    case notificationDeepLink
    case alreadyPlaying

    var requestsPlaybackStart: Bool {
        self == .explicitUserAction
    }
}

struct PlaybackStartRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let podcastID: UUID

    func targets(_ podcastID: UUID) -> Bool {
        self.podcastID == podcastID
    }
}

struct FocusCommitment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var podcastID: UUID
    var cue: DistractionCue
    var targetSeconds: Double
    var watchedSeconds: Double = 0
    var createdAt = Date()
    var completedAt: Date?
    var cancelledAt: Date?

    var isActive: Bool { completedAt == nil && cancelledAt == nil }
    var isCompleted: Bool { completedAt != nil }
    var remainingSeconds: Double { max(0, targetSeconds - watchedSeconds) }
    var progress: Double { min(watchedSeconds / max(targetSeconds, 1), 1) }
    var targetMinutes: Int { Int(targetSeconds / 60) }

    /// Returns true only on the transition from active to completed.
    mutating func recordWatchedSecond(now: Date = Date()) -> Bool {
        guard isActive else { return false }
        watchedSeconds = min(watchedSeconds + 1, targetSeconds)
        guard watchedSeconds >= targetSeconds else { return false }
        completedAt = now
        return true
    }

    mutating func cancel(now: Date = Date()) {
        guard isActive else { return }
        cancelledAt = now
    }
}
