import CryptoKit
import Foundation
import Testing
@testable import IDChecker

struct CognitoAuthenticationTests {
    @Test
    func pkceUsesSecureS256Challenge() throws {
        let pair = try PKCEPair.generate()

        #expect(pair.verifier.count >= 43)
        #expect(pair.verifier.allSatisfy { character in
            character.isLetter || character.isNumber || "-._~".contains(character)
        })

        let digest = SHA256.hash(data: Data(pair.verifier.utf8))
        let expected = Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(pair.challenge == expected)
    }

    @Test
    func callbackRequiresExactStateAndRedirect() throws {
        let callback = try #require(URL(string: "dealerid://auth/callback?code=secure-code&state=expected"))
        let code = try OAuthCallbackValidator.authorizationCode(
            from: callback,
            expectedCallback: CognitoConfiguration.callbackURI,
            expectedState: "expected"
        )
        #expect(code == "secure-code")

        #expect(throws: AuthenticationError.invalidState) {
            try OAuthCallbackValidator.authorizationCode(
                from: callback,
                expectedCallback: CognitoConfiguration.callbackURI,
                expectedState: "different"
            )
        }

        let wrongPath = try #require(URL(string: "dealerid://auth/other?code=secure-code&state=expected"))
        #expect(throws: AuthenticationError.invalidCallback) {
            try OAuthCallbackValidator.authorizationCode(
                from: wrongPath,
                expectedCallback: CognitoConfiguration.callbackURI,
                expectedState: "expected"
            )
        }
    }

    @Test
    func refreshRotationPreservesExistingRefreshTokenWhenOmitted() {
        let current = OAuthTokenSet(
            accessToken: "old-access",
            idToken: "old-id",
            refreshToken: "existing-refresh",
            tokenType: "Bearer",
            expiresAt: .distantPast
        )
        let updated = current.replacing(
            accessToken: "new-access",
            idToken: nil,
            refreshToken: nil,
            tokenType: "Bearer",
            expiresIn: 3600
        )

        #expect(updated.accessToken == "new-access")
        #expect(updated.idToken == "old-id")
        #expect(updated.refreshToken == "existing-refresh")
        #expect(!updated.needsRefresh)
    }

    @Test
    func confirmedConfigurationUsesHttpsAndMinimalScope() {
        let configuration = CognitoConfiguration.production

        #expect(configuration.authorizationEndpoint.scheme == "https")
        #expect(configuration.authorizationEndpoint.host == "us-east-10n9rozv7l.auth.us-east-1.amazoncognito.com")
        #expect(configuration.scopes == ["openid"])
        #expect(CognitoConfiguration.callbackURI.absoluteString == "dealerid://auth/callback")
    }
}
