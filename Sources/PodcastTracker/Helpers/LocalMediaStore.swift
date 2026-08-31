import AVFoundation
import Foundation
import OSLog

@MainActor
final class LocalMediaStore: ObservableObject {
    static let shared = LocalMediaStore()

    enum MediaError: LocalizedError, Equatable {
        case invalidVideoID
        case ytDLPUnavailable
        case ffmpegUnavailable
        case storageLimitReached
        case downloadFailed(String)
        case missingDownloadedFile

        var errorDescription: String? {
            switch self {
            case .invalidVideoID: "The YouTube video ID is invalid."
            case .ytDLPUnavailable: "yt-dlp is unavailable on this Mac."
            case .ffmpegUnavailable: "ffmpeg is required for this download quality."
            case .storageLimitReached: "The 8 GB download limit has been reached. Delete a download before trying again."
            case .downloadFailed(let detail): detail
            case .missingDownloadedFile: "The download finished without creating a playable media file."
            }
        }
    }

    private struct Invocation: Sendable {
        let executableURL: URL
        let argumentPrefix: [String]
    }

    private struct PendingDownload: Sendable {
        let videoID: String
        let quality: DownloadQuality
        let retention: DownloadRetention
    }

    private struct PreparedMedia: Sendable {
        let url: URL
        let byteCount: Int64
        let resolutionHeight: Int?
    }

    @Published private(set) var records: [String: DownloadRecord]
    @Published private(set) var transientStates: [String: EpisodeDownloadState] = [:]
    @Published private(set) var activeDownloadedBytes: [String: Int64] = [:]
    @Published var settings: DownloadSettings {
        didSet { if persistsMetadata { dataManager.saveDownloadSettings(settings) } }
    }

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let dataManager: DataManager
    private let persistsMetadata: Bool
    private let logger = Logger(subsystem: "com.tangenix.podtrackio", category: "LocalMedia")
    private var queue: [PendingDownload] = []
    private var waiters: [String: [CheckedContinuation<URL, Error>]] = [:]
    private var activeVideoID: String?
    private var activeTask: Task<Void, Never>?

    init(rootURL: URL? = nil, dataManager: DataManager = .shared) {
        self.dataManager = dataManager
        self.persistsMetadata = rootURL == nil
        self.rootURL = rootURL ?? dataManager.mediaCacheURL
        let loadedSettings = rootURL == nil ? dataManager.loadDownloadSettings() : DownloadSettings()
        self.settings = DownloadSettings(
            quality: loadedSettings.quality,
            maximumStorageBytes: DownloadSettings.storageLimitBytes
        )
        self.records = rootURL == nil
            ? Dictionary(uniqueKeysWithValues: dataManager.loadDownloadRecords().map { ($0.videoID, $0) })
            : [:]
        repairRecordsFromDisk()
    }

    var storageUsedBytes: Int64 { records.values.reduce(0) { $0 + $1.byteCount } }
    var remainingStorageBytes: Int64 { max(0, settings.maximumStorageBytes - storageUsedBytes) }

    func state(for videoID: String) -> EpisodeDownloadState {
        if let transient = transientStates[videoID] { return transient }
        if let record = records[videoID] { return .downloaded(record) }
        return .notDownloaded
    }

    func cachedPlayableURL(videoId: String) -> URL? {
        guard let record = records[videoId] else { return nil }
        let url = rootURL.appending(path: record.fileName)
        guard Self.isCompleteMediaFile(url, fileManager: fileManager) else {
            records[videoId] = nil
            persistRecords()
            return nil
        }
        return url
    }

    func download(videoID: String, completedAt: Date?) async throws -> URL {
        guard Self.isValid(videoID: videoID) else { throw MediaError.invalidVideoID }
        if let existing = cachedPlayableURL(videoId: videoID) { return existing }
        guard remainingStorageBytes > 1_000_000 else { throw MediaError.storageLimitReached }

        return try await withCheckedThrowingContinuation { continuation in
            waiters[videoID, default: []].append(continuation)
            guard activeVideoID != videoID, !queue.contains(where: { $0.videoID == videoID }) else { return }
            let retention = Self.retentionForNewDownload(completedAt: completedAt)
            queue.append(.init(videoID: videoID, quality: settings.quality, retention: retention))
            transientStates[videoID] = .queued
            startNextIfNeeded()
        }
    }

    func cancel(videoID: String) {
        if activeVideoID == videoID {
            activeTask?.cancel()
            return
        }
        queue.removeAll { $0.videoID == videoID }
        transientStates[videoID] = nil
        finishWaiters(for: videoID, result: .failure(CancellationError()))
    }

    func deleteDownload(videoID: String) {
        cancel(videoID: videoID)
        if let record = records.removeValue(forKey: videoID) {
            try? fileManager.removeItem(at: rootURL.appending(path: record.fileName))
        }
        removeIncompleteFiles(videoID: videoID)
        transientStates[videoID] = nil
        persistRecords()
    }

    func markCompleted(videoID: String, completedAt: Date) {
        guard var record = records[videoID], record.retention == .untilCompleted else { return }
        record.retention = .automatic(expiresAt: completedAt.addingTimeInterval(7 * 24 * 60 * 60))
        records[videoID] = record
        persistRecords()
    }

    func reconcile(with podcasts: [Podcast], migrationDate: Date = Date()) {
        repairRecordsFromDisk()
        let byVideoID = Dictionary(grouping: podcasts, by: \.youtubeVideoId)
        for (videoID, var record) in records {
            let matching = byVideoID[videoID] ?? []
            guard matching.contains(where: \.isCompleted), record.retention == .untilCompleted else { continue }
            let completedAt = matching.compactMap(\.completedAt).min() ?? migrationDate
            record.retention = .automatic(expiresAt: completedAt.addingTimeInterval(7 * 24 * 60 * 60))
            records[videoID] = record
        }
        cleanupExpired(now: migrationDate)
        persistRecords()
    }

    func cleanupExpired(now: Date = Date()) {
        let expired = records.values.compactMap { record -> String? in
            guard let date = record.retention.expirationDate, date <= now else { return nil }
            return record.videoID
        }
        for videoID in expired { deleteDownload(videoID: videoID) }
    }

    func deleteCompletedDownloads(podcasts: [Podcast]) {
        let completedIDs = Set(podcasts.filter(\.isCompleted).map(\.youtubeVideoId))
        for videoID in completedIDs where records[videoID] != nil { deleteDownload(videoID: videoID) }
    }

    private func startNextIfNeeded() {
        guard activeVideoID == nil, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        activeVideoID = request.videoID
        transientStates[request.videoID] = .downloading
        let destination = rootURL.appending(path: "\(request.videoID).mp4")
        let maximumBytes = remainingStorageBytes

        activeTask = Task { [weak self] in
            guard let self else { return }
            let progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.activeDownloadedBytes[request.videoID] = self.measuredPartialBytes(videoID: request.videoID)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            defer {
                progressTask.cancel()
                self.activeDownloadedBytes[request.videoID] = nil
            }
            do {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
                guard let invocation = Self.ytDLPInvocation(fileManager: fileManager) else {
                    throw MediaError.ytDLPUnavailable
                }
                if request.quality != .saver480,
                   !fileManager.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg"),
                   !fileManager.isExecutableFile(atPath: "/usr/local/bin/ffmpeg") {
                    throw MediaError.ffmpegUnavailable
                }
                let prepared = try await Self.prepareDownload(
                    videoID: request.videoID,
                    destination: destination,
                    quality: request.quality,
                    maximumBytes: maximumBytes,
                    invocation: invocation
                )
                guard prepared.byteCount <= remainingStorageBytes else {
                    try? fileManager.removeItem(at: prepared.url)
                    throw MediaError.storageLimitReached
                }
                let record = DownloadRecord(
                    videoID: request.videoID,
                    fileName: prepared.url.lastPathComponent,
                    byteCount: prepared.byteCount,
                    resolutionHeight: prepared.resolutionHeight,
                    downloadedAt: Date(),
                    retention: request.retention
                )
                records[request.videoID] = record
                transientStates[request.videoID] = nil
                persistRecords()
                logger.info("Download completed for video \(request.videoID, privacy: .private)")
                finishWaiters(for: request.videoID, result: .success(prepared.url))
            } catch {
                removeIncompleteFiles(videoID: request.videoID)
                if error is CancellationError {
                    transientStates[request.videoID] = nil
                } else {
                    transientStates[request.videoID] = .failed(error.localizedDescription)
                    logger.error("Download failed: \(error.localizedDescription, privacy: .public)")
                }
                finishWaiters(for: request.videoID, result: .failure(error))
            }
            activeVideoID = nil
            activeTask = nil
            startNextIfNeeded()
        }
    }

    private func finishWaiters(for videoID: String, result: Result<URL, Error>) {
        let continuations = waiters.removeValue(forKey: videoID) ?? []
        for continuation in continuations { continuation.resume(with: result) }
    }

    private func repairRecordsFromDisk() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        records = records.filter { _, record in
            Self.isCompleteMediaFile(rootURL.appending(path: record.fileName), fileManager: fileManager)
        }
        let files = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for url in files where url.pathExtension == "mp4" && Self.isCompleteMediaFile(url, fileManager: fileManager) {
            let videoID = url.deletingPathExtension().lastPathComponent
            guard Self.isValid(videoID: videoID), records[videoID] == nil else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            records[videoID] = DownloadRecord(
                videoID: videoID,
                fileName: url.lastPathComponent,
                byteCount: size,
                resolutionHeight: nil,
                downloadedAt: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(),
                retention: .untilCompleted
            )
        }
        persistRecords()
    }

    private func removeIncompleteFiles(videoID: String) {
        let files = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix(videoID) && url.lastPathComponent != "\(videoID).mp4" {
            try? fileManager.removeItem(at: url)
        }
        let destination = rootURL.appending(path: "\(videoID).mp4")
        if !Self.isCompleteMediaFile(destination, fileManager: fileManager) { try? fileManager.removeItem(at: destination) }
    }

    private func measuredPartialBytes(videoID: String) -> Int64 {
        let files = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(videoID) }.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func persistRecords() {
        guard persistsMetadata else { return }
        dataManager.saveDownloadRecords(records.values.sorted { $0.downloadedAt > $1.downloadedAt })
    }

    private nonisolated static func prepareDownload(
        videoID: String,
        destination: URL,
        quality: DownloadQuality,
        maximumBytes: Int64,
        invocation: Invocation
    ) async throws -> PreparedMedia {
        let processTask = Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let clientArguments = [
                ["--extractor-args", "youtube:player_client=web_embedded"],
                []
            ]
            var successfulOutput: String?
            var lastError = "The episode could not be downloaded."

            for clientArgument in clientArguments {
                let process = Process()
                let standardOutput = Pipe()
                let standardError = Pipe()
                process.executableURL = invocation.executableURL
                var arguments = invocation.argumentPrefix + [
                    "--no-playlist", "--no-warnings", "--no-progress", "--no-mtime", "--force-overwrites",
                    "--no-continue",
                    "--format", quality.formatSelector,
                    "--max-filesize", "\(maximumBytes)",
                    "--merge-output-format", "mp4",
                    "--output", destination.path,
                    "--print", "after_move:filepath"
                ]
                arguments.insert(contentsOf: clientArgument, at: invocation.argumentPrefix.count)
                if let runtimeArguments = javaScriptRuntimeArguments(fileManager: fileManager) {
                    arguments.insert(contentsOf: runtimeArguments, at: invocation.argumentPrefix.count)
                }
                for ffmpeg in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
                where fileManager.isExecutableFile(atPath: ffmpeg) {
                    arguments += ["--ffmpeg-location", ffmpeg]
                    break
                }
                arguments.append("https://www.youtube.com/watch?v=\(videoID)")
                process.arguments = arguments
                process.standardOutput = standardOutput
                process.standardError = standardError
                try process.run()

                let deadline = Date().addingTimeInterval(4 * 60 * 60)
                while process.isRunning, Date() < deadline, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if process.isRunning { process.terminate(); process.waitUntilExit() }
                if Task.isCancelled { throw CancellationError() }

                let output = String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let errorOutput = String(decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0 {
                    successfulOutput = output
                    break
                }
                if errorOutput.localizedCaseInsensitiveContains("larger than max-filesize") {
                    throw MediaError.storageLimitReached
                }
                if !errorOutput.isEmpty { lastError = errorOutput }
                removeAttemptFiles(destination: destination, fileManager: fileManager)
            }

            guard let output = successfulOutput else { throw MediaError.downloadFailed(lastError) }
            let printedPath = output.split(whereSeparator: \.isNewline).last.map(String.init)
            let finalURL = printedPath.map { URL(fileURLWithPath: $0) } ?? destination
            guard isCompleteMediaFile(finalURL, fileManager: fileManager),
                  let attributes = try? fileManager.attributesOfItem(atPath: finalURL.path),
                  let size = attributes[.size] as? NSNumber else { throw MediaError.missingDownloadedFile }

            let asset = AVURLAsset(url: finalURL)
            let height: Int?
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let naturalSize = try? await track.load(.naturalSize) {
                height = Int(abs(naturalSize.height.rounded()))
            } else {
                height = nil
            }
            return PreparedMedia(url: finalURL, byteCount: size.int64Value, resolutionHeight: height)
        }
        return try await withTaskCancellationHandler {
            try await processTask.value
        } onCancel: {
            processTask.cancel()
        }
    }

    private nonisolated static func removeAttemptFiles(destination: URL, fileManager: FileManager) {
        let directory = destination.deletingLastPathComponent()
        let prefix = destination.deletingPathExtension().lastPathComponent
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: file)
        }
    }

    private nonisolated static func isCompleteMediaFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.int64Value > 1_000_000
    }

    private nonisolated static func isValid(videoID: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return videoID.count == 11 && videoID.unicodeScalars.allSatisfy(allowed.contains)
    }

    nonisolated static func retentionForNewDownload(completedAt: Date?) -> DownloadRetention {
        completedAt == nil ? .untilCompleted : .manual
    }

    private nonisolated static func ytDLPInvocation(fileManager: FileManager) -> Invocation? {
        for path in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/opt/local/bin/yt-dlp"]
        where fileManager.isExecutableFile(atPath: path) {
            return Invocation(executableURL: URL(fileURLWithPath: path), argumentPrefix: [])
        }
        let local = fileManager.homeDirectoryForCurrentUser.appending(path: ".local/bin/yt-dlp")
        guard fileManager.isReadableFile(atPath: local.path) else { return nil }
        for python in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/opt/local/bin/python3"]
        where fileManager.isExecutableFile(atPath: python) {
            return Invocation(executableURL: URL(fileURLWithPath: python), argumentPrefix: [local.path])
        }
        return nil
    }

    private nonisolated static func javaScriptRuntimeArguments(fileManager: FileManager) -> [String]? {
        for path in ["/opt/homebrew/bin/deno", "/usr/local/bin/deno", "/opt/local/bin/deno"]
        where fileManager.isExecutableFile(atPath: path) {
            return ["--js-runtimes", "deno:\(path)"]
        }
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/opt/local/bin/node"]
        where fileManager.isExecutableFile(atPath: path) {
            return ["--js-runtimes", "node:\(path)"]
        }
        return nil
    }
}
