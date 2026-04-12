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
        let viewModel = await MainActor.run {
            APIKeySettingsViewModel(store: store)
        }

        await MainActor.run {
            viewModel.loadStoredAPIKey()
        }

        let loadedAPIKey = await MainActor.run { viewModel.apiKey }
        let statusMessage = await MainActor.run { viewModel.statusMessage }

        #expect(loadedAPIKey == "sk-existing")
        #expect(statusMessage == "Loaded saved API key.")
    }
}
