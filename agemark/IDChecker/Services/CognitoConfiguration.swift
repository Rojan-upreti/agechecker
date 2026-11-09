import Foundation

struct CognitoConfiguration: Equatable, Sendable {
    static let region = "us-east-1"
    static let userPoolID = "us-east-1_0n9rozv7l"
    static let appClientID = "82b6mm0ubntd4jamil0rngo76"
    static let callbackURI = URL(string: "dealerid://auth/callback")!
    static let apiBaseURL = URL(string: "https://8vzloouayi.execute-api.us-east-1.amazonaws.com/dev")!

    static let production = CognitoConfiguration(
        managedLoginDomain: "us-east-10n9rozv7l.auth.us-east-1.amazoncognito.com",
        scopes: ["openid"]
    )

    let managedLoginDomain: String
    let scopes: [String]

    var authorizationEndpoint: URL {
        endpoint(path: "/oauth2/authorize")
    }

    var signUpEndpoint: URL {
        endpoint(path: "/signup")
    }

    var tokenEndpoint: URL {
        endpoint(path: "/oauth2/token")
    }

    var revocationEndpoint: URL {
        endpoint(path: "/oauth2/revoke")
    }

    private func endpoint(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = managedLoginDomain
        components.path = path
        return components.url!
    }

    private static func isValidDomain(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.contains("://"),
              !value.contains("/"),
              !value.contains("?"),
              !value.contains("#"),
              value.contains(".") else { return false }
        var components = URLComponents()
        components.scheme = "https"
        components.host = value
        return components.url?.host == value
    }
}

struct OAuthTokenSet: Codable, Equatable, Sendable {
    let accessToken: String
    let idToken: String?
    let refreshToken: String?
    let tokenType: String
    let expiresAt: Date

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow <= 60
    }

    func replacing(
        accessToken: String,
        idToken: String?,
        refreshToken: String?,
        tokenType: String,
        expiresIn: TimeInterval
    ) -> OAuthTokenSet {
        OAuthTokenSet(
            accessToken: accessToken,
            idToken: idToken ?? self.idToken,
            refreshToken: refreshToken ?? self.refreshToken,
            tokenType: tokenType,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }
}

struct AuthorizedUser: Equatable, Sendable {
    let subject: String?
    let displayName: String
    let email: String?
}

enum AuthenticationStatus: Equatable {
    case restoring
    case signedOut
    case signingIn
    case authenticated(AuthorizedUser)
}

enum AuthenticationError: LocalizedError, Equatable {
    case configuration(String)
    case cancelled
    case invalidCallback
    case invalidState
    case missingAuthorizationCode
    case networkUnavailable
    case serverRejected
    case invalidTokenResponse
    case sessionExpired
    case secureStorage
    case requestDenied
    case serviceBusy
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .configuration(let message): message
        case .cancelled: "Sign in was cancelled."
        case .invalidCallback: "The sign-in response was invalid."
        case .invalidState: "The sign-in response could not be verified."
        case .missingAuthorizationCode: "The sign-in response did not include an authorization code."
        case .networkUnavailable: "The network is unavailable. Check your connection and try again."
        case .serverRejected: "Sign in was not accepted. Please try again."
        case .invalidTokenResponse: "The authentication service returned an invalid response."
        case .sessionExpired: "Your session expired. Please sign in again."
        case .secureStorage: "Secure session storage is unavailable."
        case .requestDenied: "Your organization does not currently allow this action."
        case .serviceBusy: "Too many requests were made. Please wait and try again."
        case .serviceUnavailable: "The verification service is temporarily unavailable."
        }
    }
}
