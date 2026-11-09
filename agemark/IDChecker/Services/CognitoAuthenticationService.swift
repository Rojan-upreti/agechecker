import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct PKCEPair: Equatable, Sendable {
    let verifier: String
    let challenge: String

    static func generate() throws -> PKCEPair {
        let verifier = try SecureOAuthRandom.base64URL(byteCount: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCEPair(verifier: verifier, challenge: Data(digest).base64URLEncoded)
    }
}

enum SecureOAuthRandom {
    static func base64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AuthenticationError.configuration("Secure sign-in could not be initialized.")
        }
        return Data(bytes).base64URLEncoded
    }
}

enum OAuthCallbackValidator {
    static func authorizationCode(
        from callbackURL: URL,
        expectedCallback: URL,
        expectedState: String
    ) throws -> String {
        guard callbackURL.scheme?.lowercased() == expectedCallback.scheme?.lowercased(),
              callbackURL.host?.lowercased() == expectedCallback.host?.lowercased(),
              callbackURL.path == expectedCallback.path,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AuthenticationError.invalidCallback
        }

        let values = Dictionary(
            components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        guard values["state"] == expectedState else {
            throw AuthenticationError.invalidState
        }
        if values["error"] != nil {
            throw AuthenticationError.serverRejected
        }
        guard let code = values["code"], !code.isEmpty else {
            throw AuthenticationError.missingAuthorizationCode
        }
        return code
    }
}

enum AuthenticationIntent: Equatable, Sendable {
    case signIn
    case createAccount
}

@MainActor
protocol CognitoAuthenticating: AnyObject {
    func signIn(intent: AuthenticationIntent) async throws -> OAuthTokenSet
    func refresh(refreshToken: String) async throws -> OAuthTokenSet
    func revoke(refreshToken: String) async
    func cancel()
}

@MainActor
final class CognitoAuthenticationService: NSObject, CognitoAuthenticating {
    private let configuration: CognitoConfiguration
    private let session: URLSession
    private var browserSession: ASWebAuthenticationSession?

    override convenience init() {
        self.init(configuration: .production, session: Self.makeSession())
    }

    init(configuration: CognitoConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
        super.init()
    }

    func signIn(intent: AuthenticationIntent) async throws -> OAuthTokenSet {
        let pkce = try PKCEPair.generate()
        let state = try SecureOAuthRandom.base64URL(byteCount: 32)
        let authorizationURL = try makeAuthorizationURL(intent: intent, pkce: pkce, state: state)
        let callbackURL = try await authenticate(url: authorizationURL)
        let code = try OAuthCallbackValidator.authorizationCode(
            from: callbackURL,
            expectedCallback: CognitoConfiguration.callbackURI,
            expectedState: state
        )
        return try await exchange([
            "grant_type": "authorization_code",
            "client_id": CognitoConfiguration.appClientID,
            "code": code,
            "redirect_uri": CognitoConfiguration.callbackURI.absoluteString,
            "code_verifier": pkce.verifier
        ])
    }

    func refresh(refreshToken: String) async throws -> OAuthTokenSet {
        try await exchange([
            "grant_type": "refresh_token",
            "client_id": CognitoConfiguration.appClientID,
            "refresh_token": refreshToken
        ])
    }

    func revoke(refreshToken: String) async {
        var request = URLRequest(url: configuration.revocationEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formData([
            "token": refreshToken,
            "client_id": CognitoConfiguration.appClientID
        ])
        _ = try? await session.data(for: request)
    }

    func cancel() {
        browserSession?.cancel()
        browserSession = nil
    }

    private func makeAuthorizationURL(
        intent: AuthenticationIntent,
        pkce: PKCEPair,
        state: String
    ) throws -> URL {
        let endpoint = intent == .createAccount
            ? configuration.signUpEndpoint
            : configuration.authorizationEndpoint
        var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: CognitoConfiguration.appClientID),
            URLQueryItem(name: "redirect_uri", value: CognitoConfiguration.callbackURI.absoluteString),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else {
            throw AuthenticationError.configuration("Sign-in configuration is invalid.")
        }
        return url
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: CognitoConfiguration.callbackURI.scheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.browserSession = nil
                    if let authenticationError = error as? ASWebAuthenticationSessionError,
                       authenticationError.code == .canceledLogin {
                        continuation.resume(throwing: AuthenticationError.cancelled)
                    } else if error != nil {
                        continuation.resume(throwing: AuthenticationError.networkUnavailable)
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: AuthenticationError.invalidCallback)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            browserSession = session
            if !session.start() {
                browserSession = nil
                continuation.resume(throwing: AuthenticationError.configuration("Sign-in could not be started."))
            }
        }
    }

    private func exchange(_ parameters: [String: String]) async throws -> OAuthTokenSet {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formData(parameters)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthenticationError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthenticationError.serverRejected
        }

        let payload: TokenResponse
        do {
            payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthenticationError.invalidTokenResponse
        }
        guard !payload.accessToken.isEmpty, payload.expiresIn > 0 else {
            throw AuthenticationError.invalidTokenResponse
        }
        return OAuthTokenSet(
            accessToken: payload.accessToken,
            idToken: payload.idToken,
            refreshToken: payload.refreshToken,
            tokenType: payload.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        )
    }

    private func formData(_ values: [String: String]) -> Data? {
        values
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key.formEncoded)=\(value.formEncoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    nonisolated private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}

extension CognitoAuthenticationService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let idToken: String?
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .formValueAllowed) ?? ""
    }
}

private extension CharacterSet {
    static let formValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
