import Foundation
import Network

// MARK: - Local OAuth Callback Server

/// A lightweight local HTTP server that intercepts Supabase's OAuth redirect
/// to `http://localhost:3000`. It serves a minimal HTML page whose JavaScript
/// reads the `#access_token=…` fragment and redirects to `podtrackio://auth-callback#…`,
/// which ASWebAuthenticationSession detects and passes back to the app.
///
/// Why: Supabase validates `redirect_to` against an allowlist. For development /
/// unsigned macOS apps, pointing Supabase's Site URL at localhost:3000 is the
/// standard approach — we run this server so localhost:3000 actually responds.

final class LocalAuthCallbackServer: @unchecked Sendable {

    // MARK: - Properties

    private var listener: NWListener?
    private let port: NWEndpoint.Port = 3000
    private let queue = DispatchQueue(label: "com.podtrackio.auth-server", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() {
        stop() // cancel any previous listener

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: port) else {
            print("⚠️ LocalAuthCallbackServer: could not bind to port \(port)")
            return
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("✅ LocalAuthCallbackServer: listening on port 3000")
            case .failed(let error):
                print("❌ LocalAuthCallbackServer: \(error)")
            default:
                break
            }
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Request Handling

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)

        // Receive the incoming HTTP request (we don't actually need to parse it —
        // we always respond with the redirect HTML).
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            if let error {
                print("⚠️ LocalAuthCallbackServer receive error: \(error)")
                connection.cancel()
                return
            }

            // Parse path + query string from the request line so we can forward
            // query-param style tokens too (some Supabase versions use ?access_token=).
            var queryString = ""
            if let data, let requestText = String(data: data, encoding: .utf8),
               let firstLine = requestText.split(separator: "\r\n", maxSplits: 1).first {
                // e.g.  "GET /?access_token=...  HTTP/1.1"
                let parts = firstLine.split(separator: " ")
                if parts.count >= 2 {
                    let path = String(parts[1])
                    if let q = URLComponents(string: path)?.query, !q.isEmpty {
                        queryString = q
                    }
                }
            }

            self?.sendHTML(queryString: queryString, over: connection)
        }
    }

    private func sendHTML(queryString: String, over connection: NWConnection) {
        // This page runs in the ASWebAuthenticationSession embedded browser.
        // It reads the URL fragment (which is never sent to the server),
        // then performs a client-side redirect to the custom scheme so
        // ASWebAuthenticationSession fires its completion callback.
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>PodTrackio — Signing In</title>
          <style>
            body {
              background: #0b111a;
              color: #fff;
              font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif;
              display: flex; align-items: center; justify-content: center;
              height: 100vh; margin: 0; flex-direction: column; gap: 16px;
            }
            .spinner {
              width: 32px; height: 32px;
              border: 3px solid rgba(0,209,224,.2);
              border-top-color: #00d1e0;
              border-radius: 50%;
              animation: spin .8s linear infinite;
            }
            @keyframes spin { to { transform: rotate(360deg); } }
            p { color: rgba(255,255,255,.6); font-size: 13px; }
          </style>
        </head>
        <body>
          <div class="spinner"></div>
          <p>Returning to PodTrackio&hellip;</p>
          <script>
            (function () {
              // Prefer URL fragment (implicit grant puts tokens here)
              var frag = window.location.hash.replace(/^#/, '');
              if (frag && frag.indexOf('access_token') !== -1) {
                window.location.href = 'podtrackio://auth-callback#' + frag;
                return;
              }
              // Fall back to query string (PKCE code exchange)
              var qs = window.location.search;
              if (qs) {
                window.location.href = 'podtrackio://auth-callback' + qs;
                return;
              }
              // Inject any query string forwarded from the server
              var serverQs = '\(queryString.replacingOccurrences(of: "'", with: "\\'"))';
              if (serverQs) {
                window.location.href = 'podtrackio://auth-callback?' + serverQs;
              }
            })();
          </script>
        </body>
        </html>
        """

        let httpResponse = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(html.utf8.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            html
        ].joined(separator: "\r\n")

        guard let data = httpResponse.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
