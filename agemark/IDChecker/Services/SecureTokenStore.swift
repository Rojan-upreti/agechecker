import Foundation
import Security

@MainActor
protocol TokenStoring: AnyObject {
    func load() async throws -> OAuthTokenSet?
    func save(_ tokens: OAuthTokenSet) async throws
    func delete() async throws
}

@MainActor
final class KeychainTokenStore: TokenStoring {
    private let service = "net.taxcurb.idchecker.authentication"
    private let account = "cognito-token-set"

    func load() throws -> OAuthTokenSet? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AuthenticationError.secureStorage
        }
        do {
            return try JSONDecoder().decode(OAuthTokenSet.self, from: data)
        } catch {
            try? delete()
            throw AuthenticationError.secureStorage
        }
    }

    func save(_ tokens: OAuthTokenSet) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(tokens)
        } catch {
            throw AuthenticationError.secureStorage
        }

        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw AuthenticationError.secureStorage
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw AuthenticationError.secureStorage
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationError.secureStorage
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
