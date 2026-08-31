import AVFoundation
import Foundation
import YouTubeKit

enum YouTubeStreamResolver {
    enum ResolverError: LocalizedError {
        case noPlayableStream
        case assetNotReady
        case invalidVideoID
        case ytDLPUnavailable
        case ytDLPFailed(String)

        var errorDescription: String? {
            switch self {
            case .noPlayableStream: "YouTube did not expose a playable stream for this video."
            case .assetNotReady: "The stream could not be prepared for playback."
            case .invalidVideoID: "The YouTube video ID is invalid."
            case .ytDLPUnavailable: "yt-dlp is not available on this Mac."
            case .ytDLPFailed(let detail): detail
            }
        }
    }

    private struct YTDLPInvocation: Sendable {
        let executableURL: URL
        let argumentPrefix: [String]
    }

    /// Resolves a directly playable item for native AVKit playback.
    /// Preference order favors reliable playback: a muxed progressive MP4,
    /// then adaptive H.264 video + m4a audio, then the HLS manifest.
    static func playableItem(videoId: String) async throws -> AVPlayerItem {
        if let url = try? await ytDLPStreamURL(videoId: videoId) {
            return AVPlayerItem(url: url)
        }

        let response = try await YTVideo(videoId: videoId)
            .fetchStreamingInfosWithDownloadFormatsThrowing(youtubeModel: YouTubeModel(), useCookies: false)

        let muxed = response.defaultFormats
            .filter { $0.url != nil && $0.mimeType?.hasPrefix("video/mp4") == true }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        if let url = muxed.first?.url {
            return AVPlayerItem(url: url)
        }

        if let item = try? await adaptiveCompositionItem(from: response.downloadFormats) {
            return item
        }

        if let hls = response.videoInfos.streamingURL {
            return AVPlayerItem(url: hls)
        }

        throw ResolverError.noPlayableStream
    }

    private static func ytDLPStreamURL(videoId: String) async throws -> URL {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard videoId.count == 11, videoId.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw ResolverError.invalidVideoID
        }
        guard let invocation = ytDLPInvocation() else {
            throw ResolverError.ytDLPUnavailable
        }

        let resolutionTask = Task.detached(priority: .userInitiated) {
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.argumentPrefix + [
                "--no-warnings",
                "--no-playlist",
                "--format", "best[ext=mp4][vcodec^=avc1]/best[ext=mp4]/best",
                "--get-url",
                "https://www.youtube.com/watch?v=\(videoId)"
            ]
            process.standardOutput = standardOutput
            process.standardError = standardError

            try process.run()
            let deadline = Date().addingTimeInterval(25)
            while process.isRunning, Date() < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }

            let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let detail = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ResolverError.ytDLPFailed(
                    detail?.isEmpty == false ? detail! : "yt-dlp could not resolve this video."
                )
            }

            let output = String(decoding: outputData, as: UTF8.self)
            guard let firstLine = output.split(whereSeparator: \.isNewline).first,
                  let url = URL(string: String(firstLine)) else {
                throw ResolverError.ytDLPFailed("yt-dlp returned an invalid stream URL.")
            }
            return url
        }
        return try await withTaskCancellationHandler {
            try await resolutionTask.value
        } onCancel: {
            resolutionTask.cancel()
        }
    }

    private static func ytDLPInvocation() -> YTDLPInvocation? {
        let fileManager = FileManager.default
        let directCandidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/opt/local/bin/yt-dlp"
        ]
        if let path = directCandidates.first(where: fileManager.isExecutableFile(atPath:)) {
            return YTDLPInvocation(executableURL: URL(fileURLWithPath: path), argumentPrefix: [])
        }

        let localYTDLP = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".local/bin/yt-dlp")
        let modernPythonCandidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/opt/local/bin/python3"
        ]
        guard fileManager.isReadableFile(atPath: localYTDLP.path),
              let pythonPath = modernPythonCandidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            return nil
        }
        return YTDLPInvocation(
            executableURL: URL(fileURLWithPath: pythonPath),
            argumentPrefix: [localYTDLP.path]
        )
    }

    private static func adaptiveCompositionItem(from formats: [any AdaptiveDownloadFormat]) async throws -> AVPlayerItem {
        let videos = formats.filter {
            $0 is VideoDownloadFormat
                && $0.url != nil
                && $0.mimeType?.hasPrefix("video/mp4") == true
                && ($0.codec?.hasPrefix("avc1") ?? false)
        }
        let audios = formats.filter {
            $0 is AudioOnlyFormat
                && $0.url != nil
                && $0.mimeType?.hasPrefix("audio/mp4") == true
        }
        guard
            let video = videos.sorted(by: { ($0.height ?? 0) > ($1.height ?? 0) }).first, let videoURL = video.url,
            let audio = audios.sorted(by: { ($0.averageBitrate ?? 0) > ($1.averageBitrate ?? 0) }).first, let audioURL = audio.url
        else { throw ResolverError.noPlayableStream }

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        let composition = AVMutableComposition()
        guard
            let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ResolverError.assetNotReady }

        guard
            let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
            let sourceAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first
        else { throw ResolverError.assetNotReady }

        let duration = CMTimeMinimum(try await videoAsset.load(.duration), try await audioAsset.load(.duration))
        guard duration.isValid, duration.seconds > 0 else { throw ResolverError.assetNotReady }

        let range = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(range, of: sourceVideoTrack, at: .zero)
        try compositionAudioTrack.insertTimeRange(range, of: sourceAudioTrack, at: .zero)
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        return await MainActor.run { AVPlayerItem(asset: composition) }
    }
}
