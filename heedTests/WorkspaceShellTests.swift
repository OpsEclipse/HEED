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
        let shell = WorkspaceShell(
            controller: recordingController,
            taskAnalysisController: taskAnalysisController
        )

        let mirrorLabels = Mirror(reflecting: shell).children.compactMap(\.label)

        #expect(mirrorLabels.contains("_taskAnalysisController"))
        #expect(!mirrorLabels.contains("taskAnalysisController"))
    }
}
