import Foundation
import Observation

@MainActor
@Observable
final class AuthenticationManager {
    private(set) var status: AuthenticationStatus = .restoring
    private(set) var errorMessage: String?

    private let tokenStore: any TokenStoring
    private let service: any CognitoAuthenticating
    private var tokens: OAuthTokenSet?
    private var refreshTask: Task<OAuthTokenSet, Error>?
    private var hasRestored = false

    convenience init() {
        self.init(tokenStore: KeychainTokenStore(), service: CognitoAuthenticationService())
    }

    init(tokenStore: any TokenStoring, service: any CognitoAuthenticating) {
        self.tokenStore = tokenStore
        self.service = service
    }

    var isAuthenticated: Bool {
        if case .authenticated = status { return true }
        return false
    }

    func restoreSession() async {
        guard !hasRestored else { return }
        hasRestored = true
        status = .restoring
        do {
            guard let stored = try await tokenStore.load() else {
                status = .signedOut
                return
            }
            tokens = stored
            if stored.needsRefresh {
                _ = try await validAccessToken(forceRefresh: true)
            } else {
                status = .authenticated(user(from: stored.idToken))
            }
        } catch {
            await clearSession()
            status = .signedOut
        }
    }

    func signIn(intent: AuthenticationIntent = .signIn) async {
        guard status != .signingIn else { return }
        errorMessage = nil
        status = .signingIn
        do {
            let newTokens = try await service.signIn(intent: intent)
            try await tokenStore.save(newTokens)
            tokens = newTokens
            status = .authenticated(user(from: newTokens.idToken))
        } catch AuthenticationError.cancelled {
            status = .signedOut
        } catch {
            status = .signedOut
            errorMessage = safeMessage(for: error)
        }
    }

    func signOut() async {
        service.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        let refreshToken = tokens?.refreshToken
        await clearSession()
        status = .signedOut
        errorMessage = nil
        if let refreshToken {
            await service.revoke(refreshToken: refreshToken)
        }
    }

    func cancelSignIn() {
        service.cancel()
        if status == .signingIn {
            status = .signedOut
        }
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else {
            throw AuthenticationError.sessionExpired
        }
        if !forceRefresh && !current.needsRefresh {
            return current.accessToken
        }
        guard let refreshToken = current.refreshToken else {
            await expireSession()
            throw AuthenticationError.sessionExpired
        }
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }

        let service = self.service
        let task = Task { @MainActor in
            try await service.refresh(refreshToken: refreshToken)
        }
        refreshTask = task
        do {
            let response = try await task.value
            let updated = current.replacing(
                accessToken: response.accessToken,
                idToken: response.idToken,
                refreshToken: response.refreshToken,
                tokenType: response.tokenType,
                expiresIn: response.expiresAt.timeIntervalSinceNow
            )
            try await tokenStore.save(updated)
            tokens = updated
            status = .authenticated(user(from: updated.idToken))
            refreshTask = nil
            return updated.accessToken
        } catch {
            refreshTask = nil
            await expireSession()
            throw AuthenticationError.sessionExpired
        }
    }

    func expireSession() async {
        await clearSession()
        status = .signedOut
        errorMessage = AuthenticationError.sessionExpired.localizedDescription
    }

    private func clearSession() async {
        tokens = nil
        try? await tokenStore.delete()
    }

    private func safeMessage(for error: Error) -> String {
        (error as? AuthenticationError)?.localizedDescription
            ?? AuthenticationError.serverRejected.localizedDescription
    }

    private func user(from idToken: String?) -> AuthorizedUser {
        guard let idToken,
              let claims = JWTClaims.decode(idToken) else {
            return AuthorizedUser(subject: nil, displayName: "Authorized User", email: nil)
        }
        let email = claims["email"] as? String
        let name = (claims["name"] as? String)
            ?? (claims["preferred_username"] as? String)
            ?? (claims["cognito:username"] as? String)
            ?? email
            ?? "Authorized User"
        return AuthorizedUser(
            subject: claims["sub"] as? String,
            displayName: name,
            email: email
        )
    }
}

private enum JWTClaims {
    static func decode(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let value = try? JSONSerialization.jsonObject(with: data),
              let claims = value as? [String: Any] else {
            return nil
        }
        return claims
    }
}
