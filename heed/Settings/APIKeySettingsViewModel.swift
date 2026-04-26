import Combine
import Foundation
import SwiftUI

@MainActor
final class APIKeySettingsViewModel: ObservableObject {
    @Published var apiKey: String
    @Published var composioAPIKey: String
    @Published private(set) var statusMessage: String
    @Published private(set) var composioStatusMessage: String

    private let store: APIKeyStoring
    private let composioStore: APIKeyStoring

    init(store: APIKeyStoring? = nil, composioStore: APIKeyStoring? = nil) {
        self.store = store ?? KeychainAPIKeyStore()
        self.composioStore = composioStore ?? KeychainAPIKeyStore(service: KeychainAPIKeyStore.composioService)
        self.apiKey = ""
        self.composioAPIKey = ""
        self.statusMessage = "No API key saved."
        self.composioStatusMessage = "No Composio API key saved."
    }

    func loadStoredAPIKey() {
        do {
            let storedKey = try store.readAPIKey()
            apiKey = storedKey ?? ""
            statusMessage = storedKey == nil ? "No API key saved." : "Loaded saved API key."
        } catch {
            apiKey = ""
            statusMessage = error.localizedDescription
        }

        loadStoredComposioAPIKey()
    }

    func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            guard !trimmedKey.isEmpty else {
                try store.clearAPIKey()
                apiKey = ""
                statusMessage = "API key cleared."
                return
            }

            try store.saveAPIKey(trimmedKey)
            apiKey = trimmedKey
            statusMessage = "API key saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearAPIKey() {
        do {
            try store.clearAPIKey()
            apiKey = ""
            statusMessage = "API key cleared."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveComposioAPIKey() {
        let trimmedKey = composioAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            guard !trimmedKey.isEmpty else {
                try composioStore.clearAPIKey()
                composioAPIKey = ""
                composioStatusMessage = "Composio API key cleared."
                return
            }

            try composioStore.saveAPIKey(trimmedKey)
            composioAPIKey = trimmedKey
            composioStatusMessage = "Composio API key saved."
        } catch {
            composioStatusMessage = error.localizedDescription
        }
    }

    func clearComposioAPIKey() {
        do {
            try composioStore.clearAPIKey()
            composioAPIKey = ""
            composioStatusMessage = "Composio API key cleared."
        } catch {
            composioStatusMessage = error.localizedDescription
        }
    }

    private func loadStoredComposioAPIKey() {
        do {
            let storedKey = try composioStore.readAPIKey()
            composioAPIKey = storedKey ?? ""
            composioStatusMessage = storedKey == nil ? "No Composio API key saved." : "Loaded saved Composio API key."
        } catch {
            composioAPIKey = ""
            composioStatusMessage = error.localizedDescription
        }
    }
}
