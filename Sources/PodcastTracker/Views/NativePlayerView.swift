import AVKit
import OSLog
import SwiftUI

enum PlaybackResumePosition {
    static func target(requested: Double, duration: Double?) -> Double {
        guard requested.isFinite, requested > 1 else { return 0 }
        guard let duration, duration.isFinite, duration > 1 else { return requested }
        return min(requested, max(0, duration - 1))
    }
}

struct NativePlayerView: View {
    let videoId: String
    let startPosition: Double
    let reloadID: UUID
    let source: NativePlaybackSource
    @ObservedObject var controller: PlayerController
    let onTimeUpdate: (Double) -> Void
    let onDurationReady: (Double) -> Void
    let onPlayStateChange: (Bool) -> Void
    let onFailure: () -> Void

    @State private var player: AVPlayer?
    private let logger = Logger(subsystem: "com.tangenix.podtrackio", category: "Playback")

    var body: some View {
        ZStack {
            Color.black
            if let player {
                AVPlayerViewRepresentable(
                    player: player,
                    onTimeUpdate: onTimeUpdate,
                    onPlayStateChange: onPlayStateChange,
                    onFailure: onFailure
                )
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(source == .local ? "Opening downloaded episode…" : "Opening stream…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(source == .local ? "Offline playback · your saved position will be restored." : "Streaming does not save the video to this Mac.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task(id: reloadID) { await loadPlayer() }
        .onDisappear { player?.pause() }
    }

    private func loadPlayer() async {
        let previousPlayer = player
        player = nil
        previousPlayer?.pause()
        do {
            let item = try await YouTubeStreamResolver.playableItem(videoId: videoId, source: source)
            guard !Task.isCancelled else { return }
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            controller.attach(player: newPlayer)
            player = newPlayer

            let duration = try? await item.asset.load(.duration)
            let durationSeconds = duration.flatMap { value in
                value.isValid && !value.isIndefinite && value.seconds > 0 ? value.seconds : nil
            }
            if let durationSeconds { onDurationReady(durationSeconds) }

            let resumePosition = PlaybackResumePosition.target(
                requested: startPosition,
                duration: durationSeconds
            )
            if resumePosition > 0 {
                await newPlayer.seek(
                    to: CMTime(seconds: resumePosition, preferredTimescale: 600),
                    toleranceBefore: CMTime(seconds: 1, preferredTimescale: 600),
                    toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
                )
            }
            guard !Task.isCancelled else {
                newPlayer.pause()
                return
            }
            controller.playerDidBecomeReady()
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Native playback preparation failed: \(error.localizedDescription, privacy: .public)")
            onFailure()
        }
    }
}

private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer
    let onTimeUpdate: (Double) -> Void
    let onPlayStateChange: (Bool) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTimeUpdate: onTimeUpdate, onPlayStateChange: onPlayStateChange, onFailure: onFailure)
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.updatesNowPlayingInfoCenter = true
        view.videoGravity = .resizeAspect
        view.player = player
        context.coordinator.startObserving(player: player)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        guard nsView.player !== player else { return }
        context.coordinator.stopObserving()
        nsView.player = player
        context.coordinator.startObserving(player: player)
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.stopObserving()
        nsView.player = nil
    }

    @MainActor
    final class Coordinator {
        private let onTimeUpdate: (Double) -> Void
        private let onPlayStateChange: (Bool) -> Void
        private let onFailure: () -> Void

        private var timeObserver: Any?
        private var rateObservation: NSKeyValueObservation?
        private var itemStatusObservation: NSKeyValueObservation?
        private var endObserver: NSObjectProtocol?
        private var failureObserver: NSObjectProtocol?
        private weak var observedPlayer: AVPlayer?

        init(
            onTimeUpdate: @escaping (Double) -> Void,
            onPlayStateChange: @escaping (Bool) -> Void,
            onFailure: @escaping () -> Void
        ) {
            self.onTimeUpdate = onTimeUpdate
            self.onPlayStateChange = onPlayStateChange
            self.onFailure = onFailure
        }

        func startObserving(player: AVPlayer) {
            observedPlayer = player
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                MainActor.assumeIsolated {
                    self?.onTimeUpdate(time.seconds)
                }
            }
            rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
                Task { @MainActor [weak self] in
                    self?.onPlayStateChange(player.rate != 0)
                }
            }
            itemStatusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in
                    self?.onFailure()
                }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onPlayStateChange(false)
                }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onFailure()
                }
            }
        }

        func stopObserving() {
            if let timeObserver, let observedPlayer {
                observedPlayer.removeTimeObserver(timeObserver)
            }
            rateObservation?.invalidate()
            itemStatusObservation?.invalidate()
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
            timeObserver = nil
            rateObservation = nil
            itemStatusObservation = nil
            endObserver = nil
            failureObserver = nil
            observedPlayer = nil
        }
    }
}
