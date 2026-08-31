import Foundation

enum DownloadQuality: Int, Codable, CaseIterable, Identifiable, Sendable {
    case saver480 = 480
    case standard720 = 720
    case high1080 = 1080

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .saver480: "480p Saver"
        case .standard720: "720p Standard"
        case .high1080: "1080p High"
        }
    }

    var formatSelector: String {
        "bestvideo[height<=\(rawValue)][ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=\(rawValue)][ext=mp4]/18"
    }
}

struct DownloadSettings: Codable, Equatable, Sendable {
    static let storageLimitBytes: Int64 = 8 * 1_024 * 1_024 * 1_024
    var quality: DownloadQuality = .high1080
    var maximumStorageBytes: Int64 = Self.storageLimitBytes
}

enum DownloadRetention: Codable, Equatable, Sendable {
    case untilCompleted
    case automatic(expiresAt: Date)
    case manual

    var expirationDate: Date? {
        if case .automatic(let date) = self { return date }
        return nil
    }
}

struct DownloadRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String { videoID }
    var videoID: String
    var fileName: String
    var byteCount: Int64
    var resolutionHeight: Int?
    var downloadedAt: Date
    var retention: DownloadRetention
}

enum EpisodeDownloadState: Equatable, Sendable {
    case notDownloaded
    case queued
    case downloading
    case downloaded(DownloadRecord)
    case failed(String)

    var label: String {
        switch self {
        case .notDownloaded: "Not Downloaded"
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .downloaded(let record):
            if let date = record.retention.expirationDate {
                "Expires \(date.formatted(date: .abbreviated, time: .omitted))"
            } else {
                "Downloaded"
            }
        case .failed: "Failed"
        }
    }
}
