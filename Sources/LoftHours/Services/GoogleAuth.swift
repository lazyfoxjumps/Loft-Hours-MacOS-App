import Foundation
import AuthenticationServices
import CryptoKit
import AppKit

/// Google OAuth 2.0 for an installed/desktop app, using PKCE.
///
/// No backend, so the "client secret" of a Desktop OAuth client is NOT actually
/// confidential: PKCE is what secures the exchange. We open the system auth UI
/// with `ASWebAuthenticationSession` (Apple-blessed, App Store friendly), which
/// claims the custom callback scheme transiently and hands us the redirect URL
/// in its completion handler. That means the OAuth bounce works WITHOUT any
/// `CFBundleURLTypes` entry in Info.plist (registering one is optional/harmless).
///
/// Tokens live in the Keychain, never UserDefaults. `accessToken()` returns a
/// valid token, transparently refreshing when expired.
///
/// SETUP: create an OAuth client of type "Desktop app" in Google Cloud Console,
/// put its client ID in `clientID` below, and add yourself as a test user on the
/// consent screen (testing mode = up to 100 users, no Google verification needed).
@MainActor
final class GoogleAuth: NSObject, ObservableObject {

    // MARK: - Configuration (fill these in)

    /// From Google Cloud Console -> Credentials -> OAuth client of type **iOS**
    /// (bundle id com.lazyfox.lofthours). iOS clients support the custom URI
    /// scheme redirect a Desktop client rejects, and auto-register it.
    private let clientID = "167933144566-2b56grkm5j3465bh6tvj1c34bh052fd8.apps.googleusercontent.com"

    /// iOS OAuth clients use PKCE only, no client secret. Leave nil.
    private let clientSecret: String? = nil

    /// iOS clients redirect to the *reversed* client ID scheme, which Google
    /// registers automatically. Derived from `clientID` so there's nothing else
    /// to keep in sync: `xxxx.apps.googleusercontent.com` ->
    /// `com.googleusercontent.apps.xxxx`.
    private var callbackScheme: String {
        let prefix = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }
    private var redirectURI: String { "\(callbackScheme):/oauth2redirect" }

    /// Scope to create/edit events on the user's existing calendars (including
    /// `primary`). NOTE: `calendar.app.created` is narrower but only reaches
    /// calendars the app itself creates, so it cannot write to `primary` — that
    /// was the silent-no-event bug. `calendar.events` is the right scope here.
    /// `openid email` (non-sensitive) let us show "Connected as ...".
    private let scopes = [
        "https://www.googleapis.com/auth/calendar.events",
        "openid",
        "email",
    ]

    // MARK: - Endpoints

    private let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    // MARK: - State

    /// Display mirror for the Settings UI. The source of truth is the Keychain.
    @Published private(set) var connectedEmail: String?

    private let store = TokenStore(service: "com.lazyfox.lofthours.google")
    private var authSession: ASWebAuthenticationSession?

    /// In-memory cache of the token set. We read the Keychain only once at launch
    /// (and write on save/delete), never on every SwiftUI redraw or block start.
    /// Each Keychain *read* can trigger a macOS password prompt when the app's
    /// code signature changed (e.g. an ad-hoc dev rebuild), so minimizing reads
    /// keeps prompts down to at most one per launch.
    private var cached: TokenSet?

    var isConnected: Bool { cached != nil }

    override init() {
        super.init()
        cached = store.load()
        connectedEmail = cached?.email
    }

    /// Write tokens to the Keychain and update the in-memory cache together.
    private func persist(_ tokens: TokenSet) {
        store.save(tokens)
        cached = tokens
    }

    // MARK: - Connect

    enum AuthError: Error { case cancelled, badCallback, tokenExchangeFailed(String), notConnected }

    /// Run the full interactive consent flow. Returns the connected email on
    /// success. Throws `AuthError.cancelled` if the user dismisses the sheet.
    @discardableResult
    func connect() async throws -> String? {
        let verifier = Self.pkceVerifier()
        let challenge = Self.pkceChallenge(for: verifier)

        var comps = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            // Force a refresh token even on re-consent.
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        let authURL = comps.url!

        let callbackURL = try await presentAuth(url: authURL)
        guard let code = Self.queryValue("code", from: callbackURL) else {
            throw AuthError.badCallback
        }

        let tokens = try await exchangeCode(code, verifier: verifier)
        persist(tokens)
        connectedEmail = tokens.email
        return tokens.email
    }

    /// Bridge the completion-handler API into async/await.
    ///
    /// The completion handler is declared `@Sendable` on purpose: AuthenticationServices
    /// invokes it on a background XPC queue, not the main actor. Without the explicit
    /// `@Sendable` annotation the compiler would infer this closure as `@MainActor`
    /// (it's defined inside a `@MainActor` type), and the Swift 6 runtime would trap
    /// with `_dispatch_assert_queue_fail` when it runs off-main. Resuming a continuation
    /// is safe from any thread, so a non-isolated closure is correct here.
    private func presentAuth(url: URL) async throws -> URL {
        let scheme = callbackScheme
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let completion: @Sendable (URL?, (any Error)?) -> Void = { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error,
                          (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.badCallback)
                }
            }
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme,
                completionHandler: completion
            )
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    // MARK: - Access token (auto-refresh)

    /// A currently-valid access token, refreshing if needed. Returns nil when
    /// not connected or the refresh fails (callers treat nil as "skip sync").
    func accessToken() async -> String? {
        guard var tokens = cached else { return nil }
        // 60s skew buffer.
        if tokens.expiry.timeIntervalSinceNow > 60 {
            return tokens.accessToken
        }
        guard let refreshed = try? await refresh(tokens.refreshToken) else {
            // Refresh failed: likely revoked server-side. Reflect "disconnected".
            connectedEmail = nil
            return nil
        }
        tokens.accessToken = refreshed.accessToken
        tokens.expiry = refreshed.expiry
        // Google often omits a new refresh token on refresh; keep the old one.
        if let newRefresh = refreshed.refreshToken { tokens.refreshToken = newRefresh }
        persist(tokens)
        return tokens.accessToken
    }

    // MARK: - Disconnect

    /// Revoke the grant with Google, then wipe the local Keychain copy.
    func disconnect() async {
        if let tokens = cached {
            var req = URLRequest(url: revokeEndpoint)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = "token=\(tokens.refreshToken)".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: req)
        }
        store.delete()
        cached = nil
        connectedEmail = nil
    }

    // MARK: - Token exchange / refresh

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
        let id_token: String?
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> TokenSet {
        var form: [String: String] = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        if let clientSecret { form["client_secret"] = clientSecret }

        let resp = try await postForm(form)
        return TokenSet(
            accessToken: resp.access_token,
            refreshToken: resp.refresh_token ?? "",
            expiry: Date().addingTimeInterval(resp.expires_in),
            email: resp.id_token.flatMap(Self.email(fromIDToken:))
        )
    }

    private struct Refreshed { let accessToken: String; let expiry: Date; let refreshToken: String? }

    private func refresh(_ refreshToken: String) async throws -> Refreshed {
        var form: [String: String] = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        if let clientSecret { form["client_secret"] = clientSecret }

        let resp = try await postForm(form)
        return Refreshed(
            accessToken: resp.access_token,
            expiry: Date().addingTimeInterval(resp.expires_in),
            refreshToken: resp.refresh_token
        )
    }

    private func postForm(_ fields: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AuthError.tokenExchangeFailed(body)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - PKCE + small helpers

    /// 43-128 char high-entropy code verifier (unreserved chars only).
    private static func pkceVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func pkceChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func queryValue(_ name: String, from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    /// Pull the email claim out of the id_token JWT payload (no signature check
    /// needed: it came straight from Google's token endpoint over TLS).
    private static func email(fromIDToken jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }
}

// MARK: - Presentation anchor

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Token model + Keychain store

/// What we persist. One JSON blob, one Keychain item.
struct TokenSet: Codable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date
    var email: String?
}

/// Minimal Keychain-backed store for a single token blob. Generic password,
/// keyed by `service`. Survives app restarts; tied to the user's login keychain.
struct TokenStore {
    let service: String
    private let account = "tokens"

    func save(_ tokens: TokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    func load() -> TokenSet? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let tokens = try? JSONDecoder().decode(TokenSet.self, from: data)
        else { return nil }
        return tokens
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
