import Testing
@testable import heed

struct APIKeySettingsTests {
    @Test func inMemoryAPIKeyStoreRoundTripsSavedValue() throws {
        let store = InMemoryAPIKeyStore()

        try store.saveAPIKey("sk-test-123")
        #expect(try store.readAPIKey() == "sk-test-123")

        try store.clearAPIKey()
        #expect(try store.readAPIKey() == nil)
    }

    @Test func viewModelLoadsSavedAPIKeyAndShowsStatus() async {
        let store = InMemoryAPIKeyStore(storedAPIKey: "sk-existing")
        let composioStore = InMemoryAPIKeyStore(storedAPIKey: "composio-existing")
        let viewModel = await MainActor.run {
            APIKeySettingsViewModel(store: store, composioStore: composioStore)
        }

        await MainActor.run {
            viewModel.loadStoredAPIKey()
        }

        let loadedAPIKey = await MainActor.run { viewModel.apiKey }
        let loadedComposioAPIKey = await MainActor.run { viewModel.composioAPIKey }
        let statusMessage = await MainActor.run { viewModel.statusMessage }
        let composioStatusMessage = await MainActor.run { viewModel.composioStatusMessage }

        #expect(loadedAPIKey == "sk-existing")
        #expect(loadedComposioAPIKey == "composio-existing")
        #expect(statusMessage == "Loaded saved API key.")
        #expect(composioStatusMessage == "Loaded saved Composio API key.")
    }

    @Test func viewModelSavesComposioAPIKey() async throws {
        let composioStore = InMemoryAPIKeyStore()
        let viewModel = await MainActor.run {
            APIKeySettingsViewModel(store: InMemoryAPIKeyStore(), composioStore: composioStore)
        }

        await MainActor.run {
            viewModel.composioAPIKey = " composio-new "
            viewModel.saveComposioAPIKey()
        }

        #expect(try composioStore.readAPIKey() == "composio-new")
        let statusMessage = await MainActor.run { viewModel.composioStatusMessage }
        #expect(statusMessage == "Composio API key saved.")
    }
}
