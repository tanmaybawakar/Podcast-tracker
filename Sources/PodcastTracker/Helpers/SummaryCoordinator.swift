import AVFoundation
import Foundation
import YouTubeKit
import YouTubeTranscript

enum SummaryGenerationState: Equatable {
    case idle
    case fetchingTranscript
    case fetchingCaptions
    case needsAudioConsent
    case downloadingAudio(progress: Double)
    case transcribing(current: Int, total: Int)
    case synthesizing
    case needsTranscriptImport(String)
    case completed
    case failed(String)
}

enum SummaryPipelineError: LocalizedError {
    case audioConsentRequired
    case transcriptImportRequired(String)
    case noAudioStream
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .audioConsentRequired: "Public captions are unavailable. Confirm audio transcription to continue; it downloads media and uses your Groq credits."
        case .transcriptImportRequired(let reason): "Automatic transcript extraction failed: \(reason) Import or paste a transcript instead."
        case .noAudioStream: "YouTube did not expose a compatible audio-only stream."
        case .emptyTranscript: "The transcript did not contain readable text."
        }
    }
}

@MainActor
final class SummaryCoordinator {
    static let shared = SummaryCoordinator()
    private var generationTask: Task<PodcastSummary, Error>?

    func cancel() { generationTask?.cancel(); generationTask = nil }

    func generate(
        for podcast: Podcast,
        importedTranscript: TranscriptDocument?,
        allowAudioTranscription: Bool = false,
        progress: @escaping @Sendable (SummaryGenerationState) -> Void
    ) async throws -> PodcastSummary {
        guard let key = KeychainStore.groqAPIKey() else { throw GroqError.missingKey }
        generationTask?.cancel()
        let task = Task<PodcastSummary, Error> {
            let transcript: TranscriptDocument
            if let importedTranscript {
                transcript = importedTranscript
            } else if let cached = DataManager.shared.loadTranscript(for: podcast.id),
                      [.transcriptAPI, .imported, .pasted].contains(cached.source) {
                transcript = cached
            } else {
                progress(.fetchingTranscript)
                do {
                    transcript = try await fetchTranscript(for: podcast)
                } catch {
                    progress(.fetchingCaptions)
                    do {
                        transcript = try await fetchCaptions(for: podcast)
                    } catch {
                        guard allowAudioTranscription else { throw SummaryPipelineError.audioConsentRequired }
                        do {
                            transcript = try await transcribeAudio(for: podcast, apiKey: key, progress: progress)
                        } catch is CancellationError { throw CancellationError() }
                        catch { throw SummaryPipelineError.transcriptImportRequired(error.localizedDescription) }
                    }
                }
            }
            try Task.checkCancellation()
            guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryPipelineError.emptyTranscript }
            DataManager.shared.saveTranscript(transcript)
            progress(.synthesizing)
            let payload = try await summarizeLongTranscript(transcript.text, title: podcast.title, apiKey: key)
            return PodcastSummary(
                podcastID: podcast.id,
                brief: payload.brief,
                keyTopics: payload.keyTopics.map { .init(title: $0.title, explanation: $0.explanation, timestampSeconds: $0.timestampSeconds) },
                majorTakeaways: payload.majorTakeaways.map { .init(title: $0.title, explanation: $0.explanation) },
                actionPlan: payload.actionPlan.map { .init(title: $0.title, detail: $0.detail) },
                sections: (payload.sections ?? []).map { section in
                    .init(title: section.title, introduction: section.introduction, points: section.points.map { .init(title: $0.title, explanation: $0.explanation, timestampSeconds: $0.timestampSeconds) })
                },
                generatedAt: Date(), transcriptSource: transcript.source, model: "openai/gpt-oss-120b"
            )
        }
        generationTask = task
        defer { generationTask = nil }
        return try await task.value
    }

    private func fetchTranscript(for podcast: Podcast) async throws -> TranscriptDocument {
        guard let apiKey = KeychainStore.transcriptAPIKey() else { throw TranscriptAPIError.missingKey }
        let segments = try await TranscriptAPIClient.shared.fetchTranscript(videoID: podcast.youtubeVideoId, apiKey: apiKey)
        return TranscriptDocument(
            podcastID: podcast.id,
            source: .transcriptAPI,
            text: segments.map(\.text).joined(separator: "\n"),
            segments: segments
        )
    }

    private func fetchCaptions(for podcast: Podcast) async throws -> TranscriptDocument {
        let result = try await YouTubeTranscript.fetch(podcast.youtubeVideoId, languages: ["en"])
        return TranscriptDocument(
            podcastID: podcast.id, source: .captions, text: result.plainText,
            segments: result.segments.map { .init(text: $0.text, startSeconds: $0.start, durationSeconds: $0.duration) }
        )
    }

    private func transcribeAudio(
        for podcast: Podcast,
        apiKey: String,
        progress: @escaping @Sendable (SummaryGenerationState) -> Void
    ) async throws -> TranscriptDocument {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("PodTrackio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        progress(.downloadingAudio(progress: 0))
        let video = YTVideo(videoId: podcast.youtubeVideoId)
        let response = try await video.fetchStreamingInfosWithDownloadFormatsThrowing(youtubeModel: YouTubeModel(), useCookies: false)
        let audio = response.downloadFormats
            .filter { $0 is AudioOnlyFormat && $0.mimeType?.hasPrefix("audio/mp4") == true && $0.url != nil }
            .sorted { ($0.averageBitrate ?? $0.bitrate ?? .max) < ($1.averageBitrate ?? $1.bitrate ?? .max) }
            .first
        guard let streamURL = audio?.url else { throw SummaryPipelineError.noAudioStream }
        let (downloaded, _) = try await URLSession.shared.download(from: streamURL)
        try Task.checkCancellation()
        let sourceURL = temporaryRoot.appendingPathComponent("source.m4a")
        try FileManager.default.moveItem(at: downloaded, to: sourceURL)
        progress(.downloadingAudio(progress: 1))

        let chunks = try await AudioChunker.splitIfNeeded(sourceURL, outputDirectory: temporaryRoot)
        var allText: [String] = []
        var segments: [TranscriptSegment] = []
        var offset: Double = 0
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            progress(.transcribing(current: index + 1, total: chunks.count))
            let result = try await GroqClient.shared.transcribe(fileURL: chunk.url, apiKey: apiKey)
            allText.append(result.text)
            for item in result.segments ?? [] {
                segments.append(.init(text: item.text, startSeconds: item.start + offset, durationSeconds: item.end.map { $0 - item.start }))
            }
            offset += chunk.duration
        }
        return TranscriptDocument(podcastID: podcast.id, source: .groqWhisper, text: allText.joined(separator: "\n"), segments: segments)
    }

    private func summarizeLongTranscript(_ transcript: String, title: String, apiKey: String) async throws -> GroqSummaryPayload {
        let chunks = transcript.chunked(maxCharacters: 42_000)
        guard chunks.count > 1 else { return try await GroqClient.shared.summarize(transcript: transcript, title: title, apiKey: apiKey) }
        var notes: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let payload = try await GroqClient.shared.summarize(transcript: chunk, title: "\(title) — section \(index + 1) of \(chunks.count)", apiKey: apiKey)
            notes.append("Section \(index + 1):\n\(payload.brief)\n\(payload.majorTakeaways.map { "- \($0.title): \($0.explanation)" }.joined(separator: "\n"))")
        }
        return try await GroqClient.shared.summarize(
            transcript: notes.joined(separator: "\n\n"), title: "\(title) — final synthesis", apiKey: apiKey
        )
    }
}

enum AudioChunker {
    struct Chunk { var url: URL; var duration: Double }
    private static let uploadLimit = 24 * 1_024 * 1_024
    private static let chunkDuration: Double = 8 * 60

    static func splitIfNeeded(_ source: URL, outputDirectory: URL) async throws -> [Chunk] {
        let bytes = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard bytes > uploadLimit else { return [Chunk(url: source, duration: duration)] }

        var chunks: [Chunk] = []
        var start: Double = 0
        while start < duration {
            try Task.checkCancellation()
            let length = min(chunkDuration, duration - start)
            let output = outputDirectory.appendingPathComponent("chunk-\(chunks.count).m4a")
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw SummaryPipelineError.transcriptImportRequired("Audio could not be prepared for transcription.")
            }
            exporter.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: length, preferredTimescale: 600))
            try await exporter.export(to: output, as: .m4a)
            chunks.append(.init(url: output, duration: length))
            start += length
        }
        return chunks
    }
}

enum TranscriptImporter {
    static func document(data: Data, fileExtension: String, podcastID: UUID) throws -> TranscriptDocument {
        guard let raw = String(data: data, encoding: .utf8) else { throw SummaryPipelineError.emptyTranscript }
        return document(text: raw, format: fileExtension, podcastID: podcastID, source: .imported)
    }

    static func document(text: String, format: String = "txt", podcastID: UUID, source: TranscriptSource = .pasted) -> TranscriptDocument {
        let lines = text.components(separatedBy: .newlines)
        let isTimed = ["srt", "vtt"].contains(format.lowercased()) || text.contains("-->")
        guard isTimed else { return .init(podcastID: podcastID, source: source, text: text, segments: []) }
        var segments: [TranscriptSegment] = []
        var index = 0
        while index < lines.count {
            if lines[index].contains("-->") {
                let times = lines[index].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
                let start = times.first.flatMap(parseTimestamp) ?? 0
                let end = times.dropFirst().first.flatMap(parseTimestamp)
                index += 1
                var copy: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    copy.append(lines[index]); index += 1
                }
                if !copy.isEmpty { segments.append(.init(text: copy.joined(separator: " "), startSeconds: start, durationSeconds: end.map { $0 - start })) }
            }
            index += 1
        }
        return .init(podcastID: podcastID, source: source, text: segments.map(\.text).joined(separator: " "), segments: segments)
    }

    private static func parseTimestamp(_ value: String) -> Double? {
        let clean = value.replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        return parts.reversed().enumerated().reduce(0) { $0 + $1.element * pow(60, Double($1.offset)) }
    }
}

private extension String {
    func chunked(maxCharacters: Int) -> [String] {
        guard count > maxCharacters else { return [self] }
        var result: [String] = []
        var current = ""
        for paragraph in components(separatedBy: "\n") {
            if current.count + paragraph.count + 1 > maxCharacters, !current.isEmpty {
                result.append(current); current = ""
            }
            current += (current.isEmpty ? "" : "\n") + paragraph
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
