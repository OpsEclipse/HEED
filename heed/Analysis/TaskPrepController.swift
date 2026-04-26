import Combine
import Foundation

@MainActor
final class TaskPrepController: ObservableObject {
    @Published private(set) var viewState = TaskPrepViewState()

    private let service: any TaskPrepConversationServicing
    private let terminalLauncher: any TaskPrepTerminalSessionLaunching
    private var activeSession: TranscriptSession?
    private var activeTask: CompiledTask?
    private var activeTurnTask: Task<Void, Never>?
    private var activeTurnID = UUID()
    private var activeTerminalHandle: (any TaskPrepTerminalSessionHandle)?

    var activeTaskID: String? {
        activeTask?.id
    }

    var activeTaskTitle: String? {
        activeTask?.title
    }

    convenience init(service: any TaskPrepConversationServicing) {
        self.init(service: service, terminalLauncher: TaskPrepProcessTerminalSessionLauncher())
    }

    convenience init(
        service: any TaskPrepConversationServicing,
        handoffLauncher: any TaskPrepAgentHandoffLaunching
    ) {
        self.init(
            service: service,
            terminalLauncher: TaskPrepAgentHandoffTerminalSessionLauncher(handoffLauncher: handoffLauncher)
        )
    }

    init(
        service: any TaskPrepConversationServicing,
        terminalLauncher: any TaskPrepTerminalSessionLaunching
    ) {
        self.service = service
        self.terminalLauncher = terminalLauncher
    }

    func start(task: CompiledTask, in session: TranscriptSession) {
        activeTask = task
        activeSession = session

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

        guard viewState.turnState != .streaming else {
            return
        }

        beginTurn(
            with: service.sendUserMessage(message),
            resetConversation: false,
            userMessage: message
        )
    }

    func sendTerminalInput(_ input: String) {
        activeTerminalHandle?.write(input)
    }

    func approveSpawn() {
        if viewState.pendingSpawnRequest != nil {
            launchApprovedSpawn()
            return
        }

        viewState.spawnStatus = .approvalGranted
    }

    func reset() {
        cancelActiveTurn()
        activeTerminalHandle?.stop()
        activeTerminalHandle = nil
        activeTask = nil
        activeSession = nil
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
            if viewState.spawnStatus != .approvalGranted {
                viewState.spawnStatus = .idle
            }
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
            if viewState.spawnStatus == .approvalGranted {
                launchApprovedSpawn()
            } else {
                viewState.spawnStatus = .blockedWaitingForApproval
            }
        case .completed:
            let completedDraft = viewState.pendingContextDraft ?? viewState.stableContextDraft

            if let pendingContextDraft = viewState.pendingContextDraft {
                viewState.stableContextDraft = pendingContextDraft
                viewState.pendingContextDraft = nil
            }

            fillEmptyAssistantMessageIfNeeded(using: completedDraft)
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

    private func fillEmptyAssistantMessageIfNeeded(using draft: TaskPrepContextDraft?) {
        let fallbackText = fallbackAssistantMessage(using: draft)

        if let assistantIndex = viewState.messages.lastIndex(where: { $0.role == .assistant }) {
            guard viewState.messages[assistantIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            viewState.messages[assistantIndex].text = fallbackText
            return
        }

        viewState.messages.append(TaskPrepMessage(role: .assistant, text: fallbackText))
    }

    private func fallbackAssistantMessage(using draft: TaskPrepContextDraft?) -> String {
        if let openQuestion = draft?.openQuestions.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !openQuestion.isEmpty {
            return openQuestion
        }

        if let taskTitle = activeTask?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !taskTitle.isEmpty {
            return "What should I clarify first about \"\(taskTitle)\"?"
        }

        return "What should I clarify first about this task?"
    }

    private func cancelActiveTurn() {
        activeTurnID = UUID()
        activeTurnTask?.cancel()
        activeTurnTask = nil
    }

    private func launchApprovedSpawn() {
        guard let activeTask,
              let activeSession,
              let pendingSpawnRequest = viewState.pendingSpawnRequest else {
            viewState.spawnStatus = .approvalGranted
            return
        }

        let draft = viewState.stableContextDraft ?? viewState.pendingContextDraft ?? TaskPrepContextDraft(
            summary: activeTask.title,
            goal: activeTask.details,
            readyToSpawn: true
        )
        let prompt = TaskPrepAgentHandoffPromptBuilder.buildPrompt(
            task: activeTask,
            transcriptSegments: activeSession.segments,
            draft: draft,
            messages: viewState.messages,
            request: pendingSpawnRequest
        )

        do {
            activeTerminalHandle?.stop()
            activeTerminalHandle = nil
            viewState.spawnStatus = .readyToSpawn
            viewState.terminalStatus = .launching
            viewState.terminalOutput = "Starting Codex...\n"
            activeTerminalHandle = try terminalLauncher.launch(
                prompt: prompt,
                onOutput: { [weak self] output in
                    self?.appendTerminalOutput(output)
                },
                onExit: { [weak self] exitCode in
                    self?.markTerminalEnded(exitCode: exitCode)
                }
            )
            viewState.spawnStatus = .launched
            viewState.terminalStatus = .running
            viewState.terminalOutput = ""
            viewState.pendingSpawnRequest = nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            viewState.spawnStatus = .launchFailed(message)
            viewState.terminalStatus = .failed(message)
        }
    }

    private func appendTerminalOutput(_ output: String) {
        viewState.terminalOutput.append(output)
    }

    private func markTerminalEnded(exitCode: Int32?) {
        guard viewState.terminalStatus == .running || viewState.terminalStatus == .launching else {
            return
        }

        viewState.terminalStatus = .ended(exitCode)
        activeTerminalHandle?.stop()
        activeTerminalHandle = nil
    }

    private func clearActiveTurnIfNeeded(_ turnID: UUID) {
        guard activeTurnID == turnID else {
            return
        }

        activeTurnTask = nil
    }
}
