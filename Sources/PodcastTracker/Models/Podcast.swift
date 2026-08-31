import Foundation

/// Represents a single podcast entry with YouTube link, notes, and tracking data
struct Podcast: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var url: String
    var youtubeVideoId: String
    var thumbnailURL: String?
    var dateAdded: Date = Date()
    var notes: String = ""
    var totalWatchedSeconds: Double = 0
    var lastWatchedDate: Date?
    var lastPlaybackPosition: Double = 0 // seconds - for continue watching
    var isCompleted: Bool = false
    var categoryID: String = LearningCategory.generalID
    var duration: Double? = nil // total video duration in seconds if known

    var formattedWatchTime: String {
        let hours = Int(totalWatchedSeconds) / 3600
        let minutes = (Int(totalWatchedSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var hasProgress: Bool {
        lastPlaybackPosition > 0 && !isCompleted
    }

    var progressPercentage: Double {
        guard let duration = duration, duration > 0 else { return 0 }
        return min(lastPlaybackPosition / duration, 1.0)
    }

    /// Extract YouTube video ID from various URL formats
    static func extractVideoId(from url: String) -> String? {
        // Handle youtu.be short links
        if url.contains("youtu.be/") {
            let components = url.components(separatedBy: "youtu.be/")
            if components.count > 1 {
                return components[1].components(separatedBy: "?").first?
                    .components(separatedBy: "&").first
            }
        }
        // Handle youtube.com/watch?v= links
        if url.contains("youtube.com") {
            if let urlComponents = URLComponents(string: url),
               let videoId = urlComponents.queryItems?.first(where: { $0.name == "v" })?.value {
                return videoId
            }
        }
        // Handle youtube.com/embed/ links
        if url.contains("youtube.com/embed/") {
            let components = url.components(separatedBy: "/embed/")
            if components.count > 1 {
                return components[1].components(separatedBy: "?").first
            }
        }
        // If it looks like a plain video ID (11 chars)
        if url.count == 11, !url.contains("/"), !url.contains(".") {
            return url
        }
        return nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Podcast, rhs: Podcast) -> Bool {
        lhs.id == rhs.id
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, url, youtubeVideoId, thumbnailURL, dateAdded, notes
        case totalWatchedSeconds, lastWatchedDate, lastPlaybackPosition
        case isCompleted, categoryID, category, duration
    }

    init(
        id: UUID = UUID(), title: String, url: String, youtubeVideoId: String,
        thumbnailURL: String? = nil, dateAdded: Date = Date(), notes: String = "",
        totalWatchedSeconds: Double = 0, lastWatchedDate: Date? = nil,
        lastPlaybackPosition: Double = 0, isCompleted: Bool = false,
        categoryID: String = LearningCategory.generalID, duration: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.youtubeVideoId = youtubeVideoId
        self.thumbnailURL = thumbnailURL
        self.dateAdded = dateAdded
        self.notes = notes
        self.totalWatchedSeconds = totalWatchedSeconds
        self.lastWatchedDate = lastWatchedDate
        self.lastPlaybackPosition = lastPlaybackPosition
        self.isCompleted = isCompleted
        self.categoryID = categoryID
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        youtubeVideoId = try container.decode(String.self, forKey: .youtubeVideoId)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
        dateAdded = try container.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        totalWatchedSeconds = try container.decodeIfPresent(Double.self, forKey: .totalWatchedSeconds) ?? 0
        lastWatchedDate = try container.decodeIfPresent(Date.self, forKey: .lastWatchedDate)
        lastPlaybackPosition = try container.decodeIfPresent(Double.self, forKey: .lastPlaybackPosition) ?? 0
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)

        if let storedID = try container.decodeIfPresent(String.self, forKey: .categoryID), !storedID.isEmpty {
            categoryID = storedID
        } else if let legacyName = try container.decodeIfPresent(String.self, forKey: .category) {
            categoryID = LearningCategory.stableID(forLegacyName: legacyName)
        } else {
            categoryID = LearningCategory.generalID
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encode(youtubeVideoId, forKey: .youtubeVideoId)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(notes, forKey: .notes)
        try container.encode(totalWatchedSeconds, forKey: .totalWatchedSeconds)
        try container.encodeIfPresent(lastWatchedDate, forKey: .lastWatchedDate)
        try container.encode(lastPlaybackPosition, forKey: .lastPlaybackPosition)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}
