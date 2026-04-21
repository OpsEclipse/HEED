import Combine
import Foundation

@MainActor
final class TaskPrepController: ObservableObject {
    @Published private(set) var viewState = TaskPrepViewState()

    private let service: any TaskPrepConversationServicing
    private var activeSession: TranscriptSession?
    private var activeTask: CompiledTask?
    private var activeTurnTask: Task<Void, Never>?
    private var activeTurnID = UUID()
    private var spawnApprovalGranted = false

    init(service: any TaskPrepConversationServicing) {
        self.service = service
    }

    func start(task: CompiledTask, in session: TranscriptSession) {
        activeTask = task
        activeSession = session
        spawnApprovalGranted = false

        beginTurn(
            with: service.beginTurn(input: TaskPrepTurnInput(task: task, session: session)),
            resetConversation: true,
            userMessage: nil
        )
    }

    func sendUserMessage(_ message: String) {
        guard activeTask != nil, activeSession != nil else {
            return
        }

        beginTurn(
            with: service.sendUserMessage(message),
            resetConversation: false,
            userMessage: message
        )
    }

    func approveSpawn() {
        spawnApprovalGranted = true
    }

    func reset() {
        cancelActiveTurn()
        activeTask = nil
        activeSession = nil
        spawnApprovalGranted = false
        viewState = TaskPrepViewState()
    }

    private func beginTurn(
        with stream: AsyncThrowingStream<TaskPrepConversationEvent, Error>,
        resetConversation: Bool,
        userMessage: String?
    ) {
        cancelActiveTurn()

        if resetConversation {
            viewState = TaskPrepViewState(
                messages: [TaskPrepMessage(role: .assistant, text: "")],
                turnState: .streaming
            )
        } else {
            if let userMessage {
                viewState.messages.append(TaskPrepMessage(role: .user, text: userMessage))
            }

            viewState.messages.append(TaskPrepMessage(role: .assistant, text: ""))
            viewState.turnState = .streaming
            viewState.pendingContextDraft = nil
            viewState.spawnStatus = .idle
            viewState.pendingSpawnRequest = nil
        }

        let turnID = UUID()
        activeTurnID = turnID
        activeTurnTask = Task { [weak self] in
            do {
                for try await event in stream {
                    await MainActor.run {
                        self?.handle(event, forTurnID: turnID)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.markTurnFailed(error, forTurnID: turnID)
                }
            }
        }
    }

    private func handle(_ event: TaskPrepConversationEvent, forTurnID turnID: UUID) {
        guard activeTurnID == turnID else {
            return
        }

        switch event {
        case let .assistantTextDelta(delta):
            appendAssistantText(delta)
        case let .contextDraft(draft):
            viewState.pendingContextDraft = draft
        case let .transcriptToolRequest(scope):
            guard let activeSession else {
                return
            }

            service.submitTranscript(scope: scope, session: activeSession)
        case let .spawnAgentRequest(request):
            viewState.pendingSpawnRequest = request
            if spawnApprovalGranted {
                viewState.spawnStatus = .readyToSpawn
                spawnApprovalGranted = false
            } else {
                viewState.spawnStatus = .blockedWaitingForApproval
            }
        case .completed:
            if let pendingContextDraft = viewState.pendingContextDraft {
                viewState.stableContextDraft = pendingContextDraft
                viewState.pendingContextDraft = nil
            }

            viewState.turnState = .completed
            clearActiveTurnIfNeeded(turnID)
        }
    }

    private func markTurnFailed(_ error: Error, forTurnID turnID: UUID) {
        guard activeTurnID == turnID else {
            return
        }

        if let assistantIndex = viewState.messages.lastIndex(where: { $0.role == .assistant }) {
            viewState.messages[assistantIndex].isInterrupted = true
        }

        viewState.pendingContextDraft = nil
        viewState.turnState = .failed(error.localizedDescription)
        clearActiveTurnIfNeeded(turnID)
    }

    private func appendAssistantText(_ delta: String) {
        guard let assistantIndex = viewState.messages.lastIndex(where: { $0.role == .assistant }) else {
            viewState.messages.append(TaskPrepMessage(role: .assistant, text: delta))
            return
        }

        viewState.messages[assistantIndex].text.append(delta)
    }

    private func cancelActiveTurn() {
        activeTurnID = UUID()
        activeTurnTask?.cancel()
        activeTurnTask = nil
    }

    private func clearActiveTurnIfNeeded(_ turnID: UUID) {
        guard activeTurnID == turnID else {
            return
        }

        activeTurnTask = nil
    }
}
