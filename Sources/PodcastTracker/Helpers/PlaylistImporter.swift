import Foundation

enum PlaylistImporter {
    enum ImportError: LocalizedError {
        case invalidPlaylistURL
        case ytDLPUnavailable
        case extractionFailed(String)
        case emptyPlaylist

        var errorDescription: String? {
            switch self {
            case .invalidPlaylistURL: "Enter a valid public YouTube playlist URL."
            case .ytDLPUnavailable: "yt-dlp is unavailable on this Mac."
            case .extractionFailed(let detail): detail
            case .emptyPlaylist: "No available videos were found in this playlist."
            }
        }
    }

    private struct Payload: Decodable {
        var id: String?
        var title: String?
        var entries: [Entry?]
    }

    private struct Entry: Decodable {
        var id: String?
        var title: String?
        var url: String?
        var webpageURL: String?
        var thumbnail: String?

        enum CodingKeys: String, CodingKey {
            case id, title, url, thumbnail
            case webpageURL = "webpage_url"
        }
    }

    static func preview(url input: String) async throws -> PlaylistPreview {
        #if APP_STORE
        throw ImportError.ytDLPUnavailable
        #else
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.host?.contains("youtube.com") == true,
              components.queryItems?.first(where: { $0.name == "list" })?.value?.isEmpty == false else {
            throw ImportError.invalidPlaylistURL
        }
        guard let executable = ytDLPURL() else { throw ImportError.ytDLPUnavailable }

        let task = Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = executable
            process.arguments = [
                "--flat-playlist", "--dump-single-json", "--no-warnings", "--no-download",
                "--extractor-args", "youtube:player_client=web_safari", trimmed
            ]
            process.standardOutput = output
            process.standardError = error
            try process.run()
            async let capturedOutput = output.fileHandleForReading.readToEnd()
            async let capturedError = error.fileHandleForReading.readToEnd()
            while process.isRunning, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            if Task.isCancelled { throw CancellationError() }
            let data = try await capturedOutput ?? Data()
            let errorData = try await capturedError ?? Data()
            let detail = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw ImportError.extractionFailed(detail.isEmpty ? "The playlist could not be loaded." : detail)
            }
            return try JSONDecoder().decode(Payload.self, from: data)
        }

        let payload = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }

        var unavailable = 0
        let episodes = payload.entries.enumerated().compactMap { offset, entry -> PlaylistEpisode? in
            guard let entry,
                  let videoID = entry.id,
                  videoID.count == 11,
                  let title = entry.title,
                  !title.localizedCaseInsensitiveContains("private video"),
                  !title.localizedCaseInsensitiveContains("deleted video") else {
                unavailable += 1
                return nil
            }
            return PlaylistEpisode(
                videoID: videoID,
                title: title,
                url: entry.webpageURL ?? entry.url ?? "https://www.youtube.com/watch?v=\(videoID)",
                thumbnailURL: entry.thumbnail ?? "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg",
                playlistIndex: offset
            )
        }
        guard !episodes.isEmpty else { throw ImportError.emptyPlaylist }
        let playlistID = payload.id ?? components.queryItems?.first(where: { $0.name == "list" })?.value ?? UUID().uuidString
        return PlaylistPreview(
            playlistID: playlistID,
            title: payload.title ?? "YouTube Playlist",
            sourceURL: trimmed,
            episodes: episodes,
            unavailableCount: unavailable
        )
        #endif
    }

    private static func ytDLPURL() -> URL? {
        let manager = FileManager.default
        return ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/opt/local/bin/yt-dlp"]
            .first(where: manager.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }
}
