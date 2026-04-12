import Combine
import Foundation
import SwiftUI

@MainActor
final class APIKeySettingsViewModel: ObservableObject {
    @Published var apiKey: String
    @Published private(set) var statusMessage: String

    private let store: APIKeyStoring

    init(store: APIKeyStoring? = nil) {
        self.store = store ?? KeychainAPIKeyStore()
        self.apiKey = ""
        self.statusMessage = "No API key saved."
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
}
