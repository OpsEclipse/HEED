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

    @Test @MainActor
    func utilityRailUsesFullscreenOnTheLeftAndPrimaryActionsOnTheRight() {
        let recordingController = RecordingController(demoMode: true)
        let taskAnalysisController = TaskAnalysisController()
        let taskContextController = TaskContextController(compiler: TaskContextFixtureCompiler())
        let apiKeySettingsViewModel = APIKeySettingsViewModel(store: InMemoryAPIKeyStore())
        let shell = WorkspaceShell(
            controller: recordingController,
            taskAnalysisController: taskAnalysisController,
            taskContextController: taskContextController,
            apiKeySettingsViewModel: apiKeySettingsViewModel
        )

        #expect(shell.utilityPrimaryStatus == "Ready to record")
        #expect(shell.utilitySecondaryStatus == nil)
        #expect(shell.utilityDetails.isEmpty)
        #expect(shell.leadingUtilityActions.map(\.title) == ["Full screen"])
        #expect(shell.trailingUtilityActions.map(\.title) == ["Set API key", "Copy text"])
    }
}
