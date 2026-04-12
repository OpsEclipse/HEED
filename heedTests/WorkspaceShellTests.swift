import Testing
@testable import heed

struct WorkspaceShellTests {
    @Test func taskAnalysisControllerIsObservedByTheShell() async {
        let recordingController = await MainActor.run {
            RecordingController(demoMode: true)
        }
        let taskAnalysisController = await MainActor.run {
            TaskAnalysisController()
        }
        let taskContextController = await MainActor.run {
            TaskContextController(compiler: TaskContextFixtureCompiler())
        }
        let apiKeySettingsViewModel = await MainActor.run {
            APIKeySettingsViewModel(store: InMemoryAPIKeyStore())
        }
        let shell = WorkspaceShell(
            controller: recordingController,
            taskAnalysisController: taskAnalysisController,
            taskContextController: taskContextController,
            apiKeySettingsViewModel: apiKeySettingsViewModel
        )

        let mirrorLabels = Mirror(reflecting: shell).children.compactMap(\.label)

        #expect(mirrorLabels.contains("_taskAnalysisController"))
        #expect(mirrorLabels.contains("_taskContextController"))
        #expect(!mirrorLabels.contains("taskAnalysisController"))
    }
}
