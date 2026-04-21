import Foundation
import Testing
@testable import heed

struct TaskPrepLaunchArgumentsTests {
    @Test func uiTestLaunchArgumentBuildsFixturePrepConversation() async throws {
        let controller = await MainActor.run {
            makeTaskPrepController(
                processInfo: FakeTaskPrepProcessInfo(arguments: ["--heed-ui-test"])
            )
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        let state = try await waitForTaskPrepState(controller) { state in
            state.turnState == .completed && state.stableContextDraft != nil
        }

        #expect(state.stableContextDraft?.summary == "Prepare the transcript review follow-up.")
        #expect(state.pendingSpawnRequest?.reason == "The brief is stable and ready for approval before handoff.")
        #expect(state.spawnStatus == .blockedWaitingForApproval)
    }
}

private final class FakeTaskPrepProcessInfo: ProcessInfo {
    private let fakeArguments: [String]

    init(arguments: [String]) {
        self.fakeArguments = arguments
        super.init()
    }

    override var arguments: [String] {
        fakeArguments
    }
}

private func waitForTaskPrepState(
    _ controller: TaskPrepController,
    matches predicate: @escaping (TaskPrepViewState) -> Bool,
    attempts: Int = 60
) async throws -> TaskPrepViewState {
    for _ in 0..<attempts {
        let state = await MainActor.run { controller.viewState }
        if predicate(state) {
            return state
        }

        try await Task.sleep(for: .milliseconds(25))
    }

    return await MainActor.run { controller.viewState }
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

private func sampleTask() -> CompiledTask {
    CompiledTask(
        id: "task-one",
        title: "Prepare the follow-up plan",
        details: "Use the prep workspace to build task context.",
        type: .feature,
        assigneeHint: "Product engineer",
        evidenceSegmentIDs: [],
        evidenceExcerpt: "The side panel should stay visible."
    )
}
