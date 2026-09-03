import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

// MARK: - Presentation Context Provider

/// Provides the presentation anchor for ASWebAuthenticationSession on macOS.
private final class AuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }
}

// MARK: - AuthManager

/// Manages user authentication via Supabase (Google & Apple OAuth).
/// Uses ASWebAuthenticationSession for the OAuth flow and persists sessions in UserDefaults.
@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    // MARK: - Published Properties

    @Published var isAuthenticated: Bool = false
    @Published var userId: UUID?
    @Published var email: String?
    @Published var displayName: String?
    @Published var avatarURL: String?
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published private(set) var isSigningIn = false
    @Published private(set) var authErrorMessage: String?

    // MARK: - Constants

    private let supabaseURL = URL(string: "https://flioaadbuwrpzmoyqypo.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZsaW9hYWRidXdycHptb3lxeXBvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5ODM4NTgsImV4cCI6MjEwMjU1OTg1OH0.ixV2gCaGGMA_ZU6UgS4AaD_Ifn3GyoZaK9rKgIxAM1A"
    // NOTE: We do NOT send redirect_to — Supabase falls back to its Site URL (localhost:3000).
    // A LocalAuthCallbackServer runs on port 3000 and serves a page that redirects
    // the browser to podtrackio://auth-callback, which ASWebAuthenticationSession intercepts.

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let accessToken = "podtrackio_accessToken"
        static let refreshToken = "podtrackio_refreshToken"
        static let userId = "podtrackio_userId"
        static let email = "podtrackio_email"
        static let displayName = "podtrackio_displayName"
        static let avatarURL = "podtrackio_avatarURL"
    }

    // MARK: - Private Properties

    /// Strong reference to the presentation context provider so it isn't deallocated during the session.
    private let presentationContextProvider: AuthPresentationContextProvider
    /// Local HTTP server that captures Supabase's localhost:3000 redirect.
    private let localAuthServer: LocalAuthCallbackServer
    /// Keep the browser session alive until Google OAuth completes.
    private var webAuthSession: ASWebAuthenticationSession?
    /// The unhashed nonce sent to Supabase after Apple returns its identity token.
    private var appleRawNonce: String?

    // MARK: - Initializer

    private init() {
        self.presentationContextProvider = AuthPresentationContextProvider()
        self.localAuthServer = LocalAuthCallbackServer()
        restoreSession()
        if refreshToken != nil {
            Task { await refreshAccessToken() }
        } else if accessToken != nil {
            Task { await fetchUser() }
        }
    }

    // MARK: - OAuth Sign-In

    /// Initiates Google OAuth sign-in via Supabase.
    func signInWithGoogle() {
        authErrorMessage = nil
        isSigningIn = true
        startOAuthFlow(provider: "google")
    }

    /// Configures the native Sign in with Apple request with a one-time nonce.
    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        authErrorMessage = nil
        isSigningIn = true

        let rawNonce = Self.randomNonce()
        appleRawNonce = rawNonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)
    }

    /// Exchanges Apple's native identity token for a Supabase session.
    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  let rawNonce = appleRawNonce else {
                appleRawNonce = nil
                isSigningIn = false
                authErrorMessage = "Apple did not return a valid sign-in credential. Please try again."
                return
            }

            appleRawNonce = nil
            let fullName = credential.fullName
            Task {
                await exchangeAppleIdentityToken(identityToken, nonce: rawNonce, fullName: fullName)
            }

        case .failure(let error):
            appleRawNonce = nil
            isSigningIn = false
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            authErrorMessage = Self.friendlyAppleError(error)
        }
    }

    func clearAuthError() {
        authErrorMessage = nil
    }

    /// Opens an ASWebAuthenticationSession for the given OAuth provider.
    private func startOAuthFlow(provider: String) {
        guard var components = URLComponents(
            url: supabaseURL.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: true
        ) else {
            print("❌ AuthManager: Failed to construct OAuth URL")
            return
        }

        // Do NOT include redirect_to — Supabase will use its configured Site URL
        // (http://localhost:3000) which our LocalAuthCallbackServer intercepts.
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider)
        ]

        guard let authURL = components.url else {
            print("❌ AuthManager: Invalid OAuth URL")
            return
        }

        // Start local server BEFORE opening the browser so port 3000 is ready.
        localAuthServer.start()

        let localServer = self.localAuthServer
        let completion: @Sendable (URL?, (any Error)?) -> Void = { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                // Always stop the local server after the flow completes.
                localServer.stop()
                self?.webAuthSession = nil

                if let error {
                    // User cancellation is not a real error — swallow it silently.
                    let nsErr = error as NSError
                    if nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        print("ℹ️ AuthManager: OAuth cancelled by user")
                    } else {
                        print("❌ AuthManager: OAuth error - \(error.localizedDescription)")
                        self?.authErrorMessage = "Google sign-in failed. \(error.localizedDescription)"
                    }
                    self?.isSigningIn = false
                    return
                }

                guard let callbackURL else {
                    print("❌ AuthManager: No callback URL received")
                    self?.isSigningIn = false
                    self?.authErrorMessage = "Google sign-in did not return a response. Please try again."
                    return
                }

                guard let self else { return }
                self.parseTokensFromFragment(url: callbackURL)
                await self.fetchUser()
                self.isSigningIn = false
            }
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "podtrackio",
            completionHandler: completion
        )

        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        if !session.start() {
            webAuthSession = nil
            localAuthServer.stop()
            isSigningIn = false
            authErrorMessage = "The sign-in window could not be opened. Please try again."
        }
    }

    // MARK: - Native Sign in with Apple

    private func exchangeAppleIdentityToken(
        _ identityToken: String,
        nonce: String,
        fullName: PersonNameComponents?
    ) async {
        defer { isSigningIn = false }

        var components = URLComponents(
            url: supabaseURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: true
        )!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "provider": "apple",
            "id_token": identityToken,
            "nonce": nonce
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let message = Self.authErrorMessage(from: data)
                authErrorMessage = Self.friendlyServerAuthError(message)
                return
            }

            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = payload["access_token"] as? String,
                  let newRefreshToken = payload["refresh_token"] as? String else {
                authErrorMessage = "Supabase returned an invalid Apple sign-in session. Please try again."
                return
            }

            accessToken = newAccessToken
            refreshToken = newRefreshToken
            persistSession()

            if let fullName, let name = Self.formattedName(fullName) {
                await updateUserName(name, components: fullName)
            }
            await fetchUser()
        } catch {
            authErrorMessage = "Apple sign-in could not reach the server. \(error.localizedDescription)"
        }
    }

    /// Apple only supplies the person's name on the first authorization, so save it immediately.
    private func updateUserName(_ fullName: String, components: PersonNameComponents) async {
        guard let accessToken else { return }

        var metadata: [String: String] = ["full_name": fullName]
        if let givenName = components.givenName { metadata["given_name"] = givenName }
        if let familyName = components.familyName { metadata["family_name"] = familyName }

        var request = URLRequest(url: supabaseURL.appendingPathComponent("auth/v1/user"))
        request.httpMethod = "PUT"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["data": metadata])
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func formattedName(_ components: PersonNameComponents) -> String? {
        let name = PersonNameComponentsFormatter.localizedString(
            from: components,
            style: .default,
            options: []
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var random: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            if random < characters.count {
                result.append(characters[Int(random)])
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func authErrorMessage(from data: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (payload["msg"] as? String)
            ?? (payload["message"] as? String)
            ?? (payload["error_description"] as? String)
            ?? (payload["error"] as? String)
    }

    private static func friendlyAppleError(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == ASAuthorizationError.errorDomain else {
            return "Apple sign-in could not start. Please try again."
        }

        guard let code = ASAuthorizationError.Code(rawValue: nsError.code) else {
            return "Apple sign-in could not be completed. Please try again."
        }

        switch code {
        case .unknown:
            return "Apple sign-in is unavailable in this copy of PodTrackio. Reopen the signed app and try again."
        case .failed:
            return "Apple could not complete sign-in. Check your Apple Account in System Settings and try again."
        case .invalidResponse:
            return "Apple returned an invalid sign-in response. Please try again."
        case .notHandled:
            return "Apple sign-in was not completed. Please try again."
        case .notInteractive:
            return "Apple sign-in needs your confirmation. Please try again while PodTrackio is active."
        case .matchedExcludedCredential:
            return "This Apple Account credential cannot be used for PodTrackio."
        case .credentialImport:
            return "Apple could not import this credential. Please sign in normally instead."
        case .canceled:
            return ""
        default:
            return "Apple sign-in could not be completed. Please try again."
        }
    }

    private static func friendlyServerAuthError(_ message: String?) -> String {
        guard let message else {
            return "Apple sign-in is temporarily unavailable. Please try again shortly."
        }

        if message.localizedCaseInsensitiveContains("provider") &&
            message.localizedCaseInsensitiveContains("not enabled") {
            return "Sign in with Apple is temporarily unavailable. Please try again shortly."
        }
        return message
    }

    // MARK: - Handle Deep-Link Callback

    /// Called from `.onOpenURL` to handle the `podtrackio://auth-callback` redirect.
    func handleCallback(url: URL) {
        parseTokensFromFragment(url: url)
        Task { await fetchUser() }
    }

    // MARK: - Token Parsing

    /// Extracts `access_token` and `refresh_token` from the URL fragment.
    private func parseTokensFromFragment(url: URL) {
        // The fragment comes after '#' and is formatted like query parameters:
        // access_token=...&refresh_token=...&...
        guard let fragment = url.fragment else {
            print("⚠️ AuthManager: No fragment in callback URL")
            return
        }

        let params = fragment
            .split(separator: "&")
            .reduce(into: [String: String]()) { result, pair in
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    result[String(parts[0])] = String(parts[1])
                }
            }

        if let token = params["access_token"] {
            self.accessToken = token
        }
        if let refresh = params["refresh_token"] {
            self.refreshToken = refresh
        }

        persistSession()
    }

    // MARK: - Token Refresh

    /// Uses the stored refresh token to obtain a new access token from Supabase.
    /// On success, updates stored tokens and fetches the user profile.
    @discardableResult
    func refreshAccessToken() async -> Bool {
        guard let refresh = refreshToken else {
            print("⚠️ AuthManager: No refresh token available")
            return false
        }

        let url = supabaseURL.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refresh])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("❌ AuthManager: Token refresh failed with status \(status)")
                if status == 400 || status == 401 {
                    // Refresh token is invalid/expired – force sign out
                    signOut()
                }
                return false
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ AuthManager: Failed to parse refresh response")
                return false
            }

            if let newAccess = json["access_token"] as? String {
                self.accessToken = newAccess
            }
            if let newRefresh = json["refresh_token"] as? String {
                self.refreshToken = newRefresh
            }

            persistSession()
            print("✅ AuthManager: Token refreshed successfully")
            await fetchUser()
            return true
        } catch {
            print("❌ AuthManager: Token refresh error - \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Fetch User Profile

    /// Fetches the authenticated user's profile from Supabase and updates published properties.
    func fetchUser() async {
        guard let token = accessToken else {
            print("⚠️ AuthManager: No access token available for fetchUser")
            return
        }

        let url = supabaseURL.appendingPathComponent("auth/v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("❌ AuthManager: fetchUser failed with status \(statusCode)")
                // Token expired – attempt a refresh instead of signing out
                if statusCode == 401 {
                    await refreshAccessToken()
                }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ AuthManager: Failed to parse user JSON")
                return
            }

            if let idString = json["id"] as? String, let uuid = UUID(uuidString: idString) {
                self.userId = uuid
            }

            self.email = json["email"] as? String

            if let metadata = json["user_metadata"] as? [String: Any] {
                self.displayName = metadata["full_name"] as? String
                self.avatarURL = metadata["avatar_url"] as? String
            }

            self.isAuthenticated = true
            self.authErrorMessage = nil
            persistSession()
        } catch {
            print("❌ AuthManager: fetchUser error - \(error.localizedDescription)")
        }
    }

    // MARK: - Sign Out

    /// Clears all local auth state and tells Supabase to invalidate the session.
    func signOut() {
        let token = accessToken

        // Clear published properties
        isAuthenticated = false
        userId = nil
        email = nil
        displayName = nil
        avatarURL = nil
        accessToken = nil
        refreshToken = nil
        authErrorMessage = nil
        isSigningIn = false
        appleRawNonce = nil

        // Clear persisted session
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.accessToken)
        defaults.removeObject(forKey: Keys.refreshToken)
        defaults.removeObject(forKey: Keys.userId)
        defaults.removeObject(forKey: Keys.email)
        defaults.removeObject(forKey: Keys.displayName)
        defaults.removeObject(forKey: Keys.avatarURL)

        // Notify Supabase (fire-and-forget)
        if let token {
            Task {
                let url = supabaseURL.appendingPathComponent("auth/v1/logout")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(anonKey, forHTTPHeaderField: "apikey")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }

    // MARK: - Session Persistence

    /// Saves the current session to UserDefaults.
    func persistSession() {
        let defaults = UserDefaults.standard
        defaults.set(accessToken, forKey: Keys.accessToken)
        defaults.set(refreshToken, forKey: Keys.refreshToken)
        defaults.set(userId?.uuidString, forKey: Keys.userId)
        defaults.set(email, forKey: Keys.email)
        defaults.set(displayName, forKey: Keys.displayName)
        defaults.set(avatarURL, forKey: Keys.avatarURL)
    }

    /// Restores a previously saved session from UserDefaults.
    func restoreSession() {
        let defaults = UserDefaults.standard
        accessToken = defaults.string(forKey: Keys.accessToken)
        refreshToken = defaults.string(forKey: Keys.refreshToken)
        email = defaults.string(forKey: Keys.email)
        displayName = defaults.string(forKey: Keys.displayName)
        avatarURL = defaults.string(forKey: Keys.avatarURL)

        if let idString = defaults.string(forKey: Keys.userId) {
            userId = UUID(uuidString: idString)
        }

        if accessToken != nil {
            isAuthenticated = true
        }
    }
}
