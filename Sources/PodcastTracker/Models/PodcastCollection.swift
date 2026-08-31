import Foundation

struct PodcastCollection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var sourcePlaylistID: String
    var sourceURL: String
    var dateAdded: Date = Date()
    var sortOrder: Int = 0
    var videoIDs: [String] = []
}

struct PlaylistEpisode: Identifiable, Equatable, Sendable {
    var id: String { videoID }
    var videoID: String
    var title: String
    var url: String
    var thumbnailURL: String?
    var playlistIndex: Int
}

struct PlaylistPreview: Equatable, Sendable {
    var playlistID: String
    var title: String
    var sourceURL: String
    var episodes: [PlaylistEpisode]
    var unavailableCount: Int
}

struct PlaylistImportResult: Equatable, Sendable {
    var added: Int
    var reused: Int
    var skipped: Int
}
