import Foundation

@MainActor
final class AuthenticatedAPIClient {
    private let authentication: AuthenticationManager
    private let session: URLSession

    init(
        authentication: AuthenticationManager,
        session: URLSession = AuthenticatedAPIClient.makeSession()
    ) {
        self.authentication = authentication
        self.session = session
    }

    func createVerificationSession(body: Data = Data("{}".utf8)) async throws -> Data {
        try await performVerificationRequest(body: body, mayRefresh: true)
    }

    private func performVerificationRequest(body: Data, mayRefresh: Bool) async throws -> Data {
        let token = try await authentication.validAccessToken(forceRefresh: false)
        let url = CognitoConfiguration.apiBaseURL.appending(path: "verification/session")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthenticationError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuthenticationError.serviceUnavailable
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401 where mayRefresh:
            _ = try await authentication.validAccessToken(forceRefresh: true)
            return try await performVerificationRequest(body: body, mayRefresh: false)
        case 401:
            await authentication.expireSession()
            throw AuthenticationError.sessionExpired
        case 403:
            throw AuthenticationError.requestDenied
        case 429:
            throw AuthenticationError.serviceBusy
        case 500...599:
            throw AuthenticationError.serviceUnavailable
        default:
            throw AuthenticationError.serverRejected
        }
    }

    nonisolated private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}
