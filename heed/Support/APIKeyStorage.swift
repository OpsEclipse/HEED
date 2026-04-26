import Foundation
import Security

protocol APIKeyStoring {
    func readAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func clearAPIKey() throws
}

final class InMemoryAPIKeyStore: APIKeyStoring {
    private var storedAPIKey: String?

    init(storedAPIKey: String? = nil) {
        self.storedAPIKey = storedAPIKey
    }

    func readAPIKey() throws -> String? {
        storedAPIKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        storedAPIKey = apiKey
    }

    func clearAPIKey() throws {
        storedAPIKey = nil
    }
}

final class KeychainAPIKeyStore: APIKeyStoring {
    static let openAIService = "sprsh.ca.heed.api-key"
    static let composioService = "sprsh.ca.heed.composio-api-key"

    private let service: String
    private let account: String

    init(service: String = KeychainAPIKeyStore.openAIService, account: String = "default") {
        self.service = service
        self.account = account
    }

    func readAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw APIKeyStorageError.invalidStoredValue
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw APIKeyStorageError.keychainFailure(status)
        }
    }

    func saveAPIKey(_ apiKey: String) throws {
        try clearRawItem()

        var query = baseQuery()
        query[kSecValueData as String] = Data(apiKey.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw APIKeyStorageError.keychainFailure(status)
        }
    }

    func clearAPIKey() throws {
        try clearRawItem()
    }

    private func clearRawItem() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStorageError.keychainFailure(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum APIKeyStorageError: LocalizedError, Equatable {
    case invalidStoredValue
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredValue:
            return "The stored API key could not be read."
        case .keychainFailure(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error: \(message)"
            }
            return "Keychain error: \(status)"
        }
    }
}
