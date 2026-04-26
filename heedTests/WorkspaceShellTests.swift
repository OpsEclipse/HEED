import Foundation
import Testing
@testable import heed

struct WorkspaceShellTests {
    @Test @MainActor
    func prepWorkspaceVisibilityTracksActivePrepTask() {
        let recordingController = RecordingController(demoMode: true)
        let taskAnalysisController = TaskAnalysisController()
        let taskPrepController = TaskPrepController(service: WorkspaceShellTaskPrepServiceStub())
        let apiKeySettingsViewModel = APIKeySettingsViewModel(store: InMemoryAPIKeyStore())
        var shell = WorkspaceShell(
            controller: recordingController,
            taskAnalysisController: taskAnalysisController,
            taskPrepController: taskPrepController,
            apiKeySettingsViewModel: apiKeySettingsViewModel
        )

        #expect(shell.isTaskPrepWorkspaceVisible == false)

        taskPrepController.start(task: sampleTask(), in: sampleSession())

        shell = WorkspaceShell(
            controller: recordingController,
            taskAnalysisController: taskAnalysisController,
            taskPrepController: taskPrepController,
            apiKeySettingsViewModel: apiKeySettingsViewModel
        )

        #expect(shell.isTaskPrepWorkspaceVisible == true)

        taskPrepController.reset()

        shell = WorkspaceShell(
            controller: recordingController,
            taskAnalysisController: taskAnalysisController,
            taskPrepController: taskPrepController,
            apiKeySettingsViewModel: apiKeySettingsViewModel
        )

        #expect(shell.isTaskPrepWorkspaceVisible == false)
    }

    @Test @MainActor
    func utilityRailUsesFullscreenWithPrimaryActionsOnTheRight() {
        let recordingController = RecordingController(demoMode: true)
        let taskAnalysisController = TaskAnalysisController()
        let taskPrepController = TaskPrepController(service: WorkspaceShellTaskPrepServiceStub())
        let apiKeySettingsViewModel = APIKeySettingsViewModel(store: InMemoryAPIKeyStore())
        let shell = WorkspaceShell(
            controller: recordingController,
            taskAnalysisController: taskAnalysisController,
            taskPrepController: taskPrepController,
            apiKeySettingsViewModel: apiKeySettingsViewModel
        )

        #expect(shell.utilityPrimaryStatus == "Ready to record")
        #expect(shell.utilitySecondaryStatus == nil)
        #expect(shell.utilityDetails.isEmpty)
        #expect(shell.leadingUtilityActions.isEmpty)
        #expect(shell.trailingUtilityActions.map { $0.title } == ["Set API key", "Copy text", "Full screen"])
    }

    @Test @MainActor
    func prepWorkspaceUsesSixtyFortySplit() {
        let workspace = TaskPrepWorkspaceView(
            controller: TaskPrepController(service: WorkspaceShellTaskPrepServiceStub()),
            onClose: {}
        )

        #expect(workspace.chatWidthFraction == 0.6)
        #expect(workspace.contextWidthFraction == 0.4)
    }
}

private struct WorkspaceShellTaskPrepServiceStub: TaskPrepConversationServicing {
    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        AsyncThrowingStream { _ in }
    }
}

private func sampleSession() -> TranscriptSession {
    TranscriptSession(
        startedAt: Date(timeIntervalSince1970: 0),
        endedAt: Date(timeIntervalSince1970: 12),
        duration: 12,
        status: .completed,
        modelName: "ggml-base.en",
        appVersion: "1.0",
        segments: [
            TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2, text: "We should prepare a context packet."),
            TranscriptSegment(source: .system, startedAt: 3, endedAt: 4, text: "The side panel should stay visible."),
            TranscriptSegment(source: .mic, startedAt: 5, endedAt: 6, text: "That keeps the transcript easy to review.")
        ]
    )
}

private func sampleTask(id: String = "task-one", title: String = "Prepare the follow-up plan") -> CompiledTask {
    CompiledTask(
        id: id,
        title: title,
        details: "Use the prep workspace to build task context.",
        type: .feature,
        assigneeHint: "Product engineer",
        evidenceSegmentIDs: [],
        evidenceExcerpt: "The side panel should stay visible."
    )
}
