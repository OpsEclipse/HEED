import Foundation
import Testing
@testable import heed

@MainActor
struct TaskPrepControllerTests {
    @Test func firstPrepareContextRequestStartsStreamingAssistantTurn() async throws {
        let service = ControlledTaskPrepConversationService()
        let task = sampleTask()
        let session = sampleSession()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: task, in: session)
        }

        #expect(await MainActor.run(body: { service.pendingTurnCount }) == 1)
        #expect(await MainActor.run(body: { service.lastTurnInput }) == TaskPrepTurnInput(task: task, session: session))

        let state = await MainActor.run { controller.viewState }
        #expect(state.messages.count == 1)
        #expect(state.messages[0].role == .assistant)
        #expect(state.messages[0].text.isEmpty)
        #expect(state.turnState == .streaming)
    }

    @Test func streamedAssistantTextAssemblesIntoOneMessageAndCompletes() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .assistantTextDelta("First part. "),
            .assistantTextDelta("Second part."),
            .completed
        ])

        let state = try await waitForPrepState(controller) { state in
            state.turnState == .completed
        }

        #expect(state.messages.count == 1)
        #expect(state.messages[0].role == .assistant)
        #expect(state.messages[0].text == "First part. Second part.")
        #expect(state.messages[0].isInterrupted == false)
    }

    @Test func contextDraftPromotesOnlyAfterCompletedEvent() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }
        let draft = sampleDraft(summary: "Pending draft", goal: "Stream the prep summary")

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.yieldToNextTurn(.contextDraft(draft))

        let pendingState = try await waitForPrepState(controller) { state in
            state.pendingContextDraft == draft
        }

        #expect(pendingState.stableContextDraft == nil)
        #expect(pendingState.turnState == .streaming)

        service.completeNextTurn(with: [.completed])

        let completedState = try await waitForPrepState(controller) { state in
            state.turnState == .completed
        }

        #expect(completedState.pendingContextDraft == nil)
        #expect(completedState.stableContextDraft == draft)
    }

    @Test func completedTurnWithoutAssistantTextUsesOpenQuestionAsFallbackMessage() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }
        var draft = sampleDraft(summary: "Pending draft", goal: "Collect the missing pipeline details")
        draft.openQuestions = ["What are the required pipeline inputs and outputs?"]

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .contextDraft(draft),
            .completed
        ])

        let state = try await waitForPrepState(controller) { state in
            state.turnState == .completed
        }

        #expect(state.messages.count == 1)
        #expect(state.messages[0].role == .assistant)
        #expect(state.messages[0].text == "What are the required pipeline inputs and outputs?")
        #expect(state.stableContextDraft == draft)
    }

    @Test func completedTurnWithoutAssistantTextUsesGenericFallbackWhenDraftHasNoQuestion() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }
        var draft = sampleDraft(summary: "Pending draft", goal: "Collect the missing pipeline details")
        draft.openQuestions = []

        await MainActor.run {
            controller.start(task: sampleTask(title: "Implement data pipeline feature"), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .contextDraft(draft),
            .completed
        ])

        let state = try await waitForPrepState(controller) { state in
            state.turnState == .completed
        }

        #expect(state.messages.count == 1)
        #expect(state.messages[0].role == .assistant)
        #expect(state.messages[0].text == "What should I clarify first about \"Implement data pipeline feature\"?")
    }

    @Test func transcriptToolRequestSubmitsTranscriptForActiveSession() async throws {
        let service = ControlledTaskPrepConversationService()
        let session = sampleSession()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: session)
        }

        try await waitForPendingTurnCount(1, service: service)
        service.yieldToNextTurn(.transcriptToolRequest(.init(scope: "next_steps")))

        try await waitForSubmittedTranscriptCount(1, service: service)

        let requests = await MainActor.run(body: { service.submittedTranscripts })
        #expect(requests == [SubmittedTranscript(scope: "next_steps", sessionID: session.id)])
    }

    @Test func spawnRequestIsBlockedBeforeExplicitApproval() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .assistantTextDelta("I can spawn now."),
            .spawnAgentRequest(.init(reason: "ready")),
            .completed
        ])

        let state = try await waitForPrepState(controller) { state in
            state.turnState == .completed
        }

        #expect(state.spawnStatus == .blockedWaitingForApproval)
        #expect(state.pendingSpawnRequest == .init(reason: "ready"))
    }

    @Test func spawnRequestSucceedsAfterApproval() async throws {
        let service = ControlledTaskPrepConversationService()
        let launcher = RecordingTaskPrepTerminalSessionLauncher()
        let controller = await MainActor.run {
            TaskPrepController(service: service, terminalLauncher: launcher)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
            controller.approveSpawn()
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .spawnAgentRequest(.init(reason: "ready")),
            .completed
        ])

        let state = try await waitForPrepState(controller) { state in
            state.turnState == .completed
        }

        #expect(state.spawnStatus == .launched)
        #expect(state.pendingSpawnRequest == nil)
        #expect(state.terminalStatus == .running)
        #expect(await MainActor.run(body: { launcher.prompts.count }) == 1)
    }

    @Test func approveSpawnUpdatesVisibleControllerState() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        _ = try await waitForPrepState(controller) { state in
            state.turnState == .streaming
        }

        await MainActor.run {
            controller.approveSpawn()
        }

        let state = await MainActor.run { controller.viewState }
        #expect(state.spawnStatus == .approvalGranted)
    }

    @Test func approveSpawnLaunchesCodexHandoffImmediatelyWhenRequestIsPending() async throws {
        let service = ControlledTaskPrepConversationService()
        let launcher = RecordingTaskPrepTerminalSessionLauncher()
        let controller = await MainActor.run {
            TaskPrepController(service: service, terminalLauncher: launcher)
        }
        let draft = sampleDraft(summary: "Stable summary", goal: "Launch the agent handoff right away.")

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .assistantTextDelta("The brief looks ready."),
            .contextDraft(draft),
            .spawnAgentRequest(.init(reason: "The implementation brief is ready for Codex.")),
            .completed
        ])

        _ = try await waitForPrepState(controller) { state in
            state.turnState == .completed && state.pendingSpawnRequest != nil
        }

        await MainActor.run {
            controller.approveSpawn()
        }

        let launchedPrompt = try #require(await MainActor.run(body: { launcher.prompts.first }))
        #expect(launchedPrompt.contains("Prepare the follow-up plan"))
        #expect(launchedPrompt.contains("Stable summary"))
        #expect(launchedPrompt.contains("Launch the agent handoff right away."))
        #expect(launchedPrompt.contains("The implementation brief is ready for Codex."))

        let state = await MainActor.run { controller.viewState }
        #expect(state.spawnStatus == .launched)
        #expect(state.pendingSpawnRequest == nil)
        #expect(state.terminalStatus == .running)
    }

    @Test func approveSpawnUsesConversationHistoryInLaunchedBrief() async throws {
        let service = ControlledTaskPrepConversationService()
        let launcher = RecordingTaskPrepTerminalSessionLauncher()
        let controller = await MainActor.run {
            TaskPrepController(service: service, terminalLauncher: launcher)
        }
        let draft = sampleDraft(summary: "Stable summary", goal: "Carry the prep conversation into Codex.")

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .assistantTextDelta("We have enough detail to hand this off."),
            .contextDraft(draft),
            .completed
        ])

        _ = try await waitForPrepState(controller) { state in
            state.turnState == .completed
        }

        await MainActor.run {
            controller.sendUserMessage("Include the transcript evidence and keep it concise.")
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .assistantTextDelta("I updated the brief and I can spawn the agent now."),
            .spawnAgentRequest(.init(reason: "The brief and follow-up are both settled.")),
            .completed
        ])

        _ = try await waitForPrepState(controller) { state in
            state.turnState == .completed && state.pendingSpawnRequest != nil && state.messages.count == 3
        }

        await MainActor.run {
            controller.approveSpawn()
        }

        let launchedPrompt = try #require(await MainActor.run(body: { launcher.prompts.first }))
        #expect(launchedPrompt.contains("Include the transcript evidence and keep it concise."))
        #expect(launchedPrompt.contains("I updated the brief and I can spawn the agent now."))
        #expect(launchedPrompt.contains("Transcript evidence"))
    }

    @Test func approveSpawnFailureKeepsPendingRequestForRetry() async throws {
        let service = ControlledTaskPrepConversationService()
        let launcher = RecordingTaskPrepTerminalSessionLauncher(error: TaskPrepServiceStubError(message: "codex was not found."))
        let controller = await MainActor.run {
            TaskPrepController(service: service, terminalLauncher: launcher)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .spawnAgentRequest(.init(reason: "ready")),
            .completed
        ])

        _ = try await waitForPrepState(controller) { state in
            state.turnState == .completed && state.pendingSpawnRequest != nil
        }

        await MainActor.run {
            controller.approveSpawn()
        }

        let state = await MainActor.run { controller.viewState }
        #expect(state.spawnStatus == .launchFailed("codex was not found."))
        #expect(state.terminalStatus == .failed("codex was not found."))
        #expect(state.pendingSpawnRequest == .init(reason: "ready"))
    }

    @Test func terminalOutputAppendsToViewState() async throws {
        let service = ControlledTaskPrepConversationService()
        let launcher = RecordingTaskPrepTerminalSessionLauncher()
        let controller = await MainActor.run {
            TaskPrepController(service: service, terminalLauncher: launcher)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .spawnAgentRequest(.init(reason: "ready")),
            .completed
        ])

        _ = try await waitForPrepState(controller) { state in
            state.turnState == .completed && state.pendingSpawnRequest != nil
        }

        await MainActor.run {
            controller.approveSpawn()
            launcher.emitOutput("Codex is thinking.\n")
        }

        let state = await MainActor.run { controller.viewState }
        #expect(state.terminalOutput.contains("Codex is thinking."))
    }

    @Test func terminalExitUpdatesViewStateAndStopsHandle() async throws {
        let service = ControlledTaskPrepConversationService()
        let launcher = RecordingTaskPrepTerminalSessionLauncher()
        let controller = await MainActor.run {
            TaskPrepController(service: service, terminalLauncher: launcher)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .spawnAgentRequest(.init(reason: "ready")),
            .completed
        ])

        _ = try await waitForPrepState(controller) { state in
            state.turnState == .completed && state.pendingSpawnRequest != nil
        }

        await MainActor.run {
            controller.approveSpawn()
            launcher.emitExit(0)
        }

        let state = await MainActor.run { controller.viewState }
        let handle = try #require(await MainActor.run(body: { launcher.handles.first }))
        #expect(state.terminalStatus == .ended(0))
        #expect(await MainActor.run(body: { handle.stopCallCount }) == 1)
    }

    @Test func sendUserMessageIsIgnoredWhileTurnIsStillStreaming() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)

        await MainActor.run {
            controller.sendUserMessage("Do this follow-up too")
        }

        let state = await MainActor.run { controller.viewState }
        #expect(state.messages.count == 1)
        #expect(state.messages[0].role == .assistant)
        #expect(state.messages[0].text.isEmpty)
        #expect(state.turnState == .streaming)
        #expect(await MainActor.run(body: { service.pendingTurnCount }) == 1)
        #expect(await MainActor.run(body: { service.sentUserMessages }) == [])
    }

    @Test func sendUserMessageAppendsUserMessageAndStartsNextAssistantTurn() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .assistantTextDelta("What should we focus on next?"),
            .completed
        ])

        _ = try await waitForPrepState(controller) { state in
            state.turnState == .completed
        }

        await MainActor.run {
            controller.sendUserMessage("Focus on the side panel")
        }

        try await waitForPendingTurnCount(1, service: service)

        let streamingState = try await waitForPrepState(controller) { state in
            state.turnState == .streaming && state.messages.count == 3
        }

        #expect(await MainActor.run(body: { service.sentUserMessages }) == ["Focus on the side panel"])
        #expect(streamingState.messages[1].role == .user)
        #expect(streamingState.messages[1].text == "Focus on the side panel")
        #expect(streamingState.messages[2].role == .assistant)
        #expect(streamingState.messages[2].text.isEmpty)

        service.completeNextTurn(with: [
            .assistantTextDelta("Start with the right-side context panel."),
            .completed
        ])

        let completedState = try await waitForPrepState(controller) { state in
            state.turnState == .completed && state.messages.count == 3
        }

        #expect(completedState.messages[2].text == "Start with the right-side context panel.")
    }

    @Test func failedTurnMarksAssistantMessageInterruptedAndSetsFailedState() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.failNextTurn(
            after: [.assistantTextDelta("Partial answer")],
            error: TaskPrepServiceStubError(message: "The streamed response ended before the turn completed.")
        )

        let state = try await waitForPrepState(controller) { state in
            if case .failed = state.turnState {
                return true
            }

            return false
        }

        #expect(state.messages.count == 1)
        #expect(state.messages[0].text == "Partial answer")
        #expect(state.messages[0].isInterrupted == true)
        #expect(state.turnState == .failed("The streamed response ended before the turn completed."))
    }

    @Test func staleFirstTurnDoesNotOverwriteSecondTaskState() async throws {
        let service = ControlledTaskPrepConversationService()
        let firstTask = sampleTask(id: "task-one", title: "First task")
        let secondTask = sampleTask(id: "task-two", title: "Second task")
        let firstSession = sampleSession()
        let secondSession = sampleSession(
            firstText: "Second session detail",
            secondText: "Keep this second session visible."
        )
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }

        await MainActor.run {
            controller.start(task: firstTask, in: firstSession)
            controller.start(task: secondTask, in: secondSession)
        }

        try await waitForPendingTurnCount(2, service: service)

        service.completeTurn(
            at: 0,
            with: [
                .assistantTextDelta("Late first turn text"),
                .contextDraft(sampleDraft(summary: "Late first draft", goal: "Should stay stale")),
                .completed
            ]
        )

        try await Task.sleep(for: .milliseconds(50))
        let staleState = await MainActor.run { controller.viewState }
        #expect(staleState.messages.count == 1)
        #expect(staleState.messages[0].text.isEmpty)
        #expect(staleState.turnState == .streaming)
        #expect(staleState.stableContextDraft == nil)

        service.completeTurn(
            at: 0,
            with: [
                .assistantTextDelta("Second turn text"),
                .contextDraft(sampleDraft(summary: "Second draft", goal: "Use the current task")),
                .completed
            ]
        )

        let finalState = try await waitForPrepState(controller) { state in
            state.turnState == .completed
        }

        #expect(finalState.messages.count == 1)
        #expect(finalState.messages[0].text == "Second turn text")
        #expect(finalState.stableContextDraft?.summary == "Second draft")
    }

    @Test func resetCancelsInFlightTurnAndClearsTemporaryPrepState() async throws {
        let service = ControlledTaskPrepConversationService()
        let controller = await MainActor.run {
            TaskPrepController(service: service)
        }
        let draft = sampleDraft(summary: "Pending draft", goal: "Keep this temporary")

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.yieldToNextTurn(.assistantTextDelta("Streaming"))
        service.yieldToNextTurn(.contextDraft(draft))

        _ = try await waitForPrepState(controller) { state in
            state.pendingContextDraft == draft
        }

        await MainActor.run {
            controller.reset()
        }

        let resetState = await MainActor.run { controller.viewState }
        #expect(resetState == TaskPrepViewState())

        service.completeNextTurn(with: [
            .assistantTextDelta("Late text"),
            .completed
        ])

        try await Task.sleep(for: .milliseconds(50))
        let finalState = await MainActor.run { controller.viewState }
        #expect(finalState == TaskPrepViewState())
    }

    @Test func resetStopsActiveTerminalSession() async throws {
        let service = ControlledTaskPrepConversationService()
        let launcher = RecordingTaskPrepTerminalSessionLauncher()
        let controller = await MainActor.run {
            TaskPrepController(service: service, terminalLauncher: launcher)
        }

        await MainActor.run {
            controller.start(task: sampleTask(), in: sampleSession())
        }

        try await waitForPendingTurnCount(1, service: service)
        service.completeNextTurn(with: [
            .spawnAgentRequest(.init(reason: "ready")),
            .completed
        ])

        _ = try await waitForPrepState(controller) { state in
            state.turnState == .completed && state.pendingSpawnRequest != nil
        }

        await MainActor.run {
            controller.approveSpawn()
            controller.reset()
        }

        let handle = try #require(await MainActor.run(body: { launcher.handles.first }))
        #expect(await MainActor.run(body: { handle.stopCallCount }) == 1)
        #expect(await MainActor.run(body: { controller.viewState }) == TaskPrepViewState())
    }
}

@MainActor
private final class ControlledTaskPrepConversationService: TaskPrepConversationServicing {
    private struct PendingTurn {
        let continuation: AsyncThrowingStream<TaskPrepConversationEvent, Error>.Continuation
    }

    private var pendingTurns: [PendingTurn] = []
    private var lastInput: TaskPrepTurnInput?
    private var sentMessages: [String] = []
    private var submittedRequests: [SubmittedTranscript] = []

    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        lastInput = input
        return AsyncThrowingStream { continuation in
            pendingTurns.append(PendingTurn(continuation: continuation))
        }
    }

    func sendUserMessage(_ message: String) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        sentMessages.append(message)
        return AsyncThrowingStream { continuation in
            pendingTurns.append(PendingTurn(continuation: continuation))
        }
    }

    func submitTranscript(scope: TaskPrepTranscriptRequest, session: TranscriptSession) {
        submittedRequests.append(SubmittedTranscript(scope: scope.scope, sessionID: session.id))
    }

    func yieldToNextTurn(_ event: TaskPrepConversationEvent) {
        guard let continuation = pendingTurns.first?.continuation else {
            return
        }

        continuation.yield(event)
    }

    func completeNextTurn(with events: [TaskPrepConversationEvent]) {
        guard !pendingTurns.isEmpty else {
            return
        }

        let pendingTurn = pendingTurns.removeFirst()
        for event in events {
            pendingTurn.continuation.yield(event)
        }
        pendingTurn.continuation.finish()
    }

    func failNextTurn(
        after events: [TaskPrepConversationEvent] = [],
        error: TaskPrepServiceStubError
    ) {
        guard !pendingTurns.isEmpty else {
            return
        }

        let pendingTurn = pendingTurns.removeFirst()
        for event in events {
            pendingTurn.continuation.yield(event)
        }
        pendingTurn.continuation.finish(throwing: error)
    }

    func completeTurn(at index: Int, with events: [TaskPrepConversationEvent]) {
        guard pendingTurns.indices.contains(index) else {
            return
        }

        let pendingTurn = pendingTurns.remove(at: index)
        for event in events {
            pendingTurn.continuation.yield(event)
        }
        pendingTurn.continuation.finish()
    }

    var pendingTurnCount: Int { pendingTurns.count }
    var lastTurnInput: TaskPrepTurnInput? { lastInput }
    var sentUserMessages: [String] { sentMessages }
    var submittedTranscripts: [SubmittedTranscript] { submittedRequests }
}

private struct WaitForPrepStateError: Error, CustomStringConvertible {
    let attempts: Int
    let state: TaskPrepViewState

    var description: String {
        "Timed out after \(attempts) checks. Last state: \(state)"
    }
}

private struct SubmittedTranscript: Equatable, Sendable {
    let scope: String
    let sessionID: UUID
}

@MainActor
private final class RecordingTaskPrepTerminalSessionLauncher: TaskPrepTerminalSessionLaunching {
    private(set) var prompts: [String] = []
    private(set) var handles: [RecordingTaskPrepTerminalSessionHandle] = []
    private let error: (any Error)?
    private var outputHandler: (@MainActor (String) -> Void)?
    private var exitHandler: (@MainActor (Int32?) -> Void)?

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func launch(
        prompt: String,
        onOutput: @escaping @MainActor (String) -> Void,
        onExit: @escaping @MainActor (Int32?) -> Void
    ) throws -> any TaskPrepTerminalSessionHandle {
        prompts.append(prompt)
        outputHandler = onOutput
        exitHandler = onExit

        if let error {
            throw error
        }

        let handle = RecordingTaskPrepTerminalSessionHandle()
        handles.append(handle)
        return handle
    }

    func emitOutput(_ output: String) {
        outputHandler?(output)
    }

    func emitExit(_ exitCode: Int32?) {
        exitHandler?(exitCode)
    }
}

@MainActor
private final class RecordingTaskPrepTerminalSessionHandle: TaskPrepTerminalSessionHandle {
    private(set) var writtenInputs: [String] = []
    private(set) var stopCallCount = 0

    func write(_ input: String) {
        writtenInputs.append(input)
    }

    func stop() {
        stopCallCount += 1
    }
}

private struct TaskPrepServiceStubError: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

private func waitForPrepState(
    _ controller: TaskPrepController,
    matches predicate: @escaping (TaskPrepViewState) -> Bool,
    attempts: Int = 40
) async throws -> TaskPrepViewState {
    for _ in 0..<attempts {
        let state = await MainActor.run { controller.viewState }
        if predicate(state) {
            return state
        }

        try await Task.sleep(for: .milliseconds(25))
    }

    let state = await MainActor.run { controller.viewState }
    throw WaitForPrepStateError(attempts: attempts, state: state)
}

private func waitForPendingTurnCount(
    _ expectedCount: Int,
    service: ControlledTaskPrepConversationService,
    attempts: Int = 40
) async throws {
    for _ in 0..<attempts {
        if await MainActor.run(body: { service.pendingTurnCount }) >= expectedCount {
            return
        }

        try await Task.sleep(for: .milliseconds(25))
    }

    #expect(await MainActor.run(body: { service.pendingTurnCount }) >= expectedCount)
}

private func waitForSubmittedTranscriptCount(
    _ expectedCount: Int,
    service: ControlledTaskPrepConversationService,
    attempts: Int = 40
) async throws {
    for _ in 0..<attempts {
        if await MainActor.run(body: { service.submittedTranscripts.count }) >= expectedCount {
            return
        }

        try await Task.sleep(for: .milliseconds(25))
    }

    #expect(await MainActor.run(body: { service.submittedTranscripts.count }) >= expectedCount)
}

private func sampleSession(
    firstText: String = "We should prepare a context packet.",
    secondText: String = "The side panel should stay visible.",
    thirdText: String = "That keeps the transcript easy to review."
) -> TranscriptSession {
    TranscriptSession(
        startedAt: Date(timeIntervalSince1970: 0),
        endedAt: Date(timeIntervalSince1970: 12),
        duration: 12,
        status: .completed,
        modelName: "ggml-base.en",
        appVersion: "1.0",
        segments: [
            TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2, text: firstText),
            TranscriptSegment(source: .system, startedAt: 3, endedAt: 4, text: secondText),
            TranscriptSegment(source: .mic, startedAt: 5, endedAt: 6, text: thirdText)
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

private func sampleDraft(summary: String, goal: String) -> TaskPrepContextDraft {
    TaskPrepContextDraft(
        summary: summary,
        goal: goal,
        constraints: ["Keep the transcript visible."],
        acceptanceCriteria: ["The right panel updates after a full turn."],
        risks: ["The panel could squeeze the transcript."],
        openQuestions: ["Should approval persist across turns?"],
        evidence: [
            TaskPrepEvidence(
                id: "evidence-1",
                label: "Transcript evidence",
                excerpt: "The side panel should stay visible.",
                segmentIDs: []
            )
        ],
        readyToSpawn: false
    )
}
