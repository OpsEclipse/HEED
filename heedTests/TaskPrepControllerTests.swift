import Foundation
import Testing
@testable import heed

struct TaskPrepControllerTests {
    @Test func firstPrepareContextRequestStartsStreamingAssistantTurn() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        #expect(await service.pendingTurnCount() == 1)

        let state = await MainActor.run { controller.viewState }
        #expect(state.messages.count == 1)
        #expect(state.messages[0].role == .assistant)
        #expect(state.messages[0].text.isEmpty)
        #expect(state.turnState == .streaming)
    }
}

private actor ControlledTaskPrepConversationService: TaskPrepConversationServicing {
    private var pendingTurns: [AsyncThrowingStream<TaskPrepConversationEvent, Error>.Continuation] = []

    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        AsyncThrowingStream { continuation in
            pendingTurns.append(continuation)
        }
    }

    func pendingTurnCount() -> Int {
        pendingTurns.count
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
        details: "Use the right-side panel to build task context.",
        type: .feature,
        assigneeHint: "Product engineer",
        evidenceSegmentIDs: [],
        evidenceExcerpt: "The side panel should stay visible."
    )
}
