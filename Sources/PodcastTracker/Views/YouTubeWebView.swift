import AppKit
import SwiftUI
import WebKit

struct YouTubeWebView: NSViewRepresentable {
    let videoId: String
    let startPosition: Double
    @ObservedObject var controller: PlayerController
    let onTimeUpdate: (Double) -> Void
    let onDurationReady: (Double) -> Void
    let onPlayStateChange: (Bool) -> Void
    let onError: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        let preferences = WKPreferences()
        preferences.isElementFullscreenEnabled = true
        configuration.preferences = preferences

        let contentController = WKUserContentController()
        for name in Coordinator.messageNames {
            contentController.add(context.coordinator, name: name)
        }
        contentController.addUserScript(
            WKUserScript(
                source: Self.playerBridgeSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        controller.attach(webView: webView)
        loadVideo(in: webView, videoId: videoId, start: Int(startPosition))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentVideoId != videoId else { return }
        context.coordinator.currentVideoId = videoId
        controller.attach(webView: webView)
        loadVideo(in: webView, videoId: videoId, start: Int(startPosition))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        for name in Coordinator.messageNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            videoId: videoId,
            controller: controller,
            onTimeUpdate: onTimeUpdate,
            onDurationReady: onDurationReady,
            onPlayStateChange: onPlayStateChange,
            onError: onError
        )
    }

    private func loadVideo(in webView: WKWebView, videoId: String, start: Int) {
        var components = URLComponents(string: "https://www.youtube.com/embed/\(videoId)")!
        components.queryItems = [
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: "https://www.youtube.com"),
            URLQueryItem(name: "widget_referrer", value: "https://www.youtube.com/"),
            URLQueryItem(name: "start", value: String(max(0, start))),
            URLQueryItem(name: "controls", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "iv_load_policy", value: "3"),
            URLQueryItem(name: "fs", value: "1")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        webView.load(request)
    }

    private static let playerBridgeSource = #"""
    (function() {
      if (window.__podTrackioBridgeInstalled) return;
      window.__podTrackioBridgeInstalled = true;

      var observedVideo = null;
      var reportedReady = false;
      var lastPlaying = null;
      var reportedError = false;

      function post(name, value) {
        try {
          var handler = window.webkit && window.webkit.messageHandlers[name];
          if (handler) handler.postMessage(value);
        } catch (_) {}
      }

      function reportError() {
        if (reportedError) return;
        reportedError = true;
        post('playerError', 'playback-failed');
      }

      function reportState(video) {
        if (!video) return;

        if (!reportedReady && video.readyState >= 1) {
          reportedReady = true;
          post('playerReady', 'ready');
        }

        if (Number.isFinite(video.duration) && video.duration > 0) {
          post('durationReady', video.duration);
        }
        if (Number.isFinite(video.currentTime)) {
          post('timeUpdate', video.currentTime);
        }

        var playing = !video.paused && !video.ended;
        if (playing !== lastPlaying) {
          lastPlaying = playing;
          post('playStateChange', playing ? 'playing' : 'paused');
        }
      }

      function attachToVideo(video) {
        if (!video || observedVideo === video) return;
        observedVideo = video;
        reportedReady = false;
        lastPlaying = null;
        video.addEventListener('loadedmetadata', function() { reportState(video); });
        video.addEventListener('durationchange', function() { reportState(video); });
        video.addEventListener('play', function() { reportState(video); });
        video.addEventListener('pause', function() { reportState(video); });
        video.addEventListener('ended', function() { reportState(video); });
        video.addEventListener('error', reportError);
        reportState(video);
      }

      window.podTrackioSeek = function(seconds) {
        var video = observedVideo || document.querySelector('video');
        if (video && Number.isFinite(seconds)) video.currentTime = Math.max(0, seconds);
      };

      window.podTrackioPlay = function() {
        var video = observedVideo || document.querySelector('video');
        if (video) video.play().catch(function() {});
      };

      function poll() {
        var video = document.querySelector('video');
        attachToVideo(video);
        reportState(video);

        if (!reportedError && document.body) {
          var text = document.body.innerText || '';
          if (text.indexOf('Error code:') !== -1 ||
              text.indexOf('Video player configuration error') !== -1 ||
              text.indexOf('This video is unavailable') !== -1 ||
              text.indexOf('Playback on other websites has been disabled') !== -1) {
            reportError();
          }
        }
      }

      setInterval(poll, 750);
      document.addEventListener('DOMContentLoaded', poll);
      poll();
    })();
    """#

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageNames = [
            "timeUpdate", "durationReady", "playStateChange", "playerReady", "playerError"
        ]

        var currentVideoId: String
        weak var controller: PlayerController?
        let onTimeUpdate: (Double) -> Void
        let onDurationReady: (Double) -> Void
        let onPlayStateChange: (Bool) -> Void
        let onError: () -> Void

        init(
            videoId: String,
            controller: PlayerController,
            onTimeUpdate: @escaping (Double) -> Void,
            onDurationReady: @escaping (Double) -> Void,
            onPlayStateChange: @escaping (Bool) -> Void,
            onError: @escaping () -> Void
        ) {
            currentVideoId = videoId
            self.controller = controller
            self.onTimeUpdate = onTimeUpdate
            self.onDurationReady = onDurationReady
            self.onPlayStateChange = onPlayStateChange
            self.onError = onError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                switch message.name {
                case "timeUpdate":
                    if let value = message.body as? Double { onTimeUpdate(value) }
                case "durationReady":
                    if let value = message.body as? Double { onDurationReady(value) }
                case "playStateChange":
                    onPlayStateChange((message.body as? String) == "playing")
                case "playerReady":
                    controller?.playerDidBecomeReady()
                case "playerError":
                    onError()
                default:
                    break
                }
            }
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
                return .cancel
            }
            return .allow
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in onError() }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in onError() }
        }
    }
}
