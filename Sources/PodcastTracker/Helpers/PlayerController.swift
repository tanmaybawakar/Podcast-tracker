import AVFoundation
import Foundation
import WebKit

@MainActor
final class PlayerController: ObservableObject {
    enum Backend {
        case native
        case embed
    }

    @Published private(set) var isPlaybackStartPending = false
    @Published private(set) var isEmbedPlayerReady = false
    private(set) var backend: Backend = .native

    private weak var webView: WKWebView?
    private weak var player: AVPlayer?
    private var playbackStartRequested = false
    private var pendingIndicatorTask: Task<Void, Never>?

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        switch backend {
        case .native:
            player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        case .embed:
            webView?.evaluateJavaScript("window.podTrackioSeek(\(clamped));", completionHandler: nil)
        }
    }

    func requestPlaybackStart() {
        playbackStartRequested = true
        isPlaybackStartPending = true
        issuePlaybackStartIfReady()
        pendingIndicatorTask?.cancel()
        pendingIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.isPlaybackStartPending = false
        }
    }

    func playerStateDidChange(isPlaying: Bool) {
        guard isPlaying else { return }
        playbackStartRequested = false
        isPlaybackStartPending = false
        pendingIndicatorTask?.cancel()
    }

    func attach(player: AVPlayer) {
        backend = .native
        self.player = player
        webView = nil
    }

    func attach(webView: WKWebView) {
        backend = .embed
        self.webView = webView
        player = nil
        isEmbedPlayerReady = false
    }

    func playerDidBecomeReady() {
        isEmbedPlayerReady = true
        issuePlaybackStartIfReady()
    }

    private func issuePlaybackStartIfReady() {
        guard playbackStartRequested else { return }
        switch backend {
        case .native:
            player?.play()
        case .embed:
            guard isEmbedPlayerReady else { return }
            webView?.evaluateJavaScript("window.podTrackioPlay();", completionHandler: nil)
        }
    }
}
