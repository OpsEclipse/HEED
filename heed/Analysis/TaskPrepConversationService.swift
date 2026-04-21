import Foundation

protocol TaskPrepConversationServicing: Sendable {
    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error>
    func sendUserMessage(_ message: String) -> AsyncThrowingStream<TaskPrepConversationEvent, Error>
    func submitTranscript(scope: TaskPrepTranscriptRequest, session: TranscriptSession)
}

extension TaskPrepConversationServicing {
    func sendUserMessage(_ message: String) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: OpenAITaskPrepConversationServiceError.failedTurn(
                    "Task prep conversation is not ready for a follow-up message."
                )
            )
        }
    }

    func submitTranscript(scope: TaskPrepTranscriptRequest, session: TranscriptSession) {}
}

@MainActor
final class TaskPrepFixtureConversationService: TaskPrepConversationServicing {
    private struct FixtureTurn {
        let events: [TaskPrepConversationEvent]
    }

    private let delay: Duration
    private var currentInput: TaskPrepTurnInput?

    init(delay: Duration = .milliseconds(120)) {
        self.delay = delay
    }

    convenience init(processInfo: ProcessInfo = .processInfo) {
        let delay: Duration = processInfo.arguments.contains("--heed-ui-test") ? .milliseconds(90) : .milliseconds(120)
        self.init(delay: delay)
    }

    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        currentInput = input
        return makeStream(turn: initialTurn(for: input))
    }

    func sendUserMessage(_ message: String) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        guard let currentInput else {
            return AsyncThrowingStream { continuation in
                continuation.finish(
                    throwing: OpenAITaskPrepConversationServiceError.failedTurn(
                        "Task prep conversation is not ready for a follow-up message."
                    )
                )
            }
        }

        return makeStream(turn: followUpTurn(for: currentInput, message: message))
    }

    func submitTranscript(scope: TaskPrepTranscriptRequest, session: TranscriptSession) {}

    private func makeStream(turn: FixtureTurn) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for event in turn.events {
                        try await Task.sleep(for: delay)
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func initialTurn(for input: TaskPrepTurnInput) -> FixtureTurn {
        FixtureTurn(
            events: [
                .assistantTextDelta("I think we have enough context to proceed. "),
                .assistantTextDelta("Do you want me to spawn the agent now?"),
                .contextDraft(makeContextDraft(for: input)),
                .spawnAgentRequest(
                    .init(reason: "The brief is stable and ready for approval before handoff.")
                ),
                .completed
            ]
        )
    }

    private func followUpTurn(for input: TaskPrepTurnInput, message: String) -> FixtureTurn {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let acknowledgement = trimmedMessage.isEmpty ? "that follow-up" : "\"\(trimmedMessage)\""
        var draft = makeContextDraft(for: input)
        draft.openQuestions = [
            "Should the next agent start from the current prep brief or from a fresh task analysis?",
            "The user asked to refine \(acknowledgement)."
        ]

        return FixtureTurn(
            events: [
                .assistantTextDelta("I updated the brief to reflect \(acknowledgement)."),
                .contextDraft(draft),
                .completed
            ]
        )
    }

    private func makeContextDraft(for input: TaskPrepTurnInput) -> TaskPrepContextDraft {
        let evidenceSegment = input.session.segments.first { input.task.evidenceSegmentIDs.contains($0.id) }
            ?? input.session.segments.first

        let evidence = TaskPrepEvidence(
            id: "fixture-evidence-\(input.task.id)",
            label: "Meeting evidence",
            excerpt: evidenceSegment?.text ?? input.task.evidenceExcerpt,
            segmentIDs: evidenceSegment.map { [$0.id] } ?? input.task.evidenceSegmentIDs
        )

        return TaskPrepContextDraft(
            summary: "Prepare the transcript review follow-up.",
            goal: "Turn the captured audio review into a short implementation handoff with clear approval before spawning.",
            constraints: [
                "Keep the transcript evidence tied to the current task.",
                "Do not hide the prep workspace while the first turn is streaming."
            ],
            acceptanceCriteria: [
                "The prep workspace shows a stable brief after the streamed turn completes.",
                "The assistant asks for approval before the spawn action becomes available."
            ],
            risks: [
                "The underlying audio issue may still be environmental, so the follow-up should stay scoped to verification first."
            ],
            openQuestions: [
                "Should the final spawn action immediately hand off to another agent or pause on approval?"
            ],
            evidence: [evidence],
            readyToSpawn: true
        )
    }
}

enum OpenAITaskPrepConversationServiceError: LocalizedError, Equatable {
    case failedTurn(String)
    case invalidToolArguments(toolName: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .failedTurn(message):
            return "Task prep failed: \(message)"
        case let .invalidToolArguments(toolName, message):
            return "Task prep tool \(toolName) returned invalid arguments: \(message)"
        }
    }
}

@MainActor
final class OpenAITaskPrepConversationService: TaskPrepConversationServicing {
    private struct ConversationContext {
        let input: TaskPrepTurnInput
        var lastResponseID: String?
    }

    private struct PendingTranscriptRequest {
        let request: TaskPrepTranscriptRequest
        let metadata: OpenAIStreamFunctionCallMetadata
    }

    private struct QueuedTranscriptOutput {
        let callID: String
        let output: String
    }

    private struct ActiveStream {
        let continuation: AsyncThrowingStream<TaskPrepConversationEvent, Error>.Continuation
        var streamTask: Task<Void, Never>?
        var currentStreamID: UUID?
        var pendingTranscriptRequest: PendingTranscriptRequest?
        var queuedTranscriptOutput: QueuedTranscriptOutput?
        var terminalEventReceived = false
        var isStreaming = false
    }

    private let client: OpenAIResponsesClient
    private var conversationContext: ConversationContext?
    private var activeStream: ActiveStream?

    init(client: OpenAIResponsesClient = OpenAIResponsesClient(model: "gpt-5.4")) {
        self.client = client
    }

    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        cancelActiveStream()
        conversationContext = ConversationContext(input: input)
        return makeStreamedTurn(
            inputItems: Self.initialInputItems(for: input),
            previousResponseID: nil
        )
    }

    func sendUserMessage(_ message: String) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        guard activeStream == nil else {
            return failedStream(
                OpenAITaskPrepConversationServiceError.failedTurn(
                    "A task prep turn is already in progress."
                )
            )
        }

        guard let conversationContext,
              let previousResponseID = conversationContext.lastResponseID else {
            return failedStream(
                OpenAITaskPrepConversationServiceError.failedTurn(
                    "Task prep conversation is not ready for a follow-up message."
                )
            )
        }

        return makeStreamedTurn(
            inputItems: [Self.messagePayload(role: "user", text: message)],
            previousResponseID: previousResponseID
        )
    }

    func submitTranscript(scope: TaskPrepTranscriptRequest, session: TranscriptSession) {
        guard var stream = activeStream,
              let conversationContext,
              let pendingRequest = stream.pendingTranscriptRequest,
              pendingRequest.request == scope,
              session.id == conversationContext.input.session.id else {
            return
        }

        stream.queuedTranscriptOutput = QueuedTranscriptOutput(
            callID: pendingRequest.metadata.callID,
            output: Self.transcriptToolOutput(scope: scope, session: session)
        )
        activeStream = stream
        continueWithQueuedTranscriptOutputIfPossible()
    }

    private func makeStreamedTurn(
        inputItems: [[String: Any]],
        previousResponseID: String?
    ) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        AsyncThrowingStream { continuation in
            self.activeStream = ActiveStream(continuation: continuation)
            self.startStreaming(
                inputItems: inputItems,
                previousResponseID: previousResponseID
            )

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.cancelActiveStream()
                }
            }
        }
    }

    private func failedStream(_ error: Error) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    private func startStreaming(inputItems: [[String: Any]], previousResponseID: String?) {
        guard var streamState = activeStream else {
            return
        }

        do {
            let streamID = UUID()
            let stream = try client.streamConversation(
                input: inputItems,
                tools: Self.tools,
                previousResponseID: previousResponseID
            )

            streamState.isStreaming = true
            streamState.currentStreamID = streamID
            streamState.terminalEventReceived = false
            streamState.streamTask = Task { [weak self] in
                do {
                    for try await event in stream {
                        await MainActor.run {
                            self?.handle(event, fromStreamID: streamID)
                        }
                    }

                    await MainActor.run {
                        self?.handleStreamFinished(streamID: streamID)
                    }
                } catch {
                    await MainActor.run {
                        self?.finishActiveStream(throwing: error)
                    }
                }
            }
            activeStream = streamState
        } catch {
            finishActiveStream(throwing: error)
        }
    }

    private func handle(_ event: OpenAIStreamEvent, fromStreamID streamID: UUID) {
        guard var streamState = activeStream, streamState.currentStreamID == streamID else {
            return
        }

        switch event {
        case let .textDelta(delta):
            streamState.continuation.yield(.assistantTextDelta(delta))
            activeStream = streamState
        case .functionArgumentsDelta:
            activeStream = streamState
        case let .functionCallCompleted(metadata, name, arguments):
            do {
                if let toolEvent = try decodeToolEvent(name: name, arguments: arguments) {
                    switch toolEvent {
                    case let .transcriptToolRequest(request):
                        streamState.pendingTranscriptRequest = PendingTranscriptRequest(
                            request: request,
                            metadata: metadata
                        )
                        streamState.continuation.yield(toolEvent)
                    case .contextDraft, .spawnAgentRequest:
                        streamState.continuation.yield(toolEvent)
                    default:
                        break
                    }
                }

                activeStream = streamState
            } catch {
                finishActiveStream(throwing: error)
            }
        case let .completed(responseID):
            streamState.isStreaming = false
            streamState.currentStreamID = nil
            streamState.terminalEventReceived = true
            activeStream = streamState

            if let responseID {
                conversationContext?.lastResponseID = responseID
            }

            if streamState.queuedTranscriptOutput != nil {
                continueWithQueuedTranscriptOutputIfPossible()
                return
            }

            if streamState.pendingTranscriptRequest != nil {
                return
            }

            finishActiveStreamSuccessfully()
        case let .failed(message):
            streamState.terminalEventReceived = true
            activeStream = streamState
            finishActiveStream(throwing: OpenAITaskPrepConversationServiceError.failedTurn(message))
        }
    }

    private func continueWithQueuedTranscriptOutputIfPossible() {
        guard var streamState = activeStream,
              let previousResponseID = conversationContext?.lastResponseID,
              !streamState.isStreaming,
              let queuedTranscriptOutput = streamState.queuedTranscriptOutput else {
            return
        }

        streamState.queuedTranscriptOutput = nil
        streamState.pendingTranscriptRequest = nil
        streamState.terminalEventReceived = false
        activeStream = streamState

        startStreaming(
            inputItems: [
                Self.functionCallOutputItem(
                    callID: queuedTranscriptOutput.callID,
                    output: queuedTranscriptOutput.output
                )
            ],
            previousResponseID: previousResponseID
        )
    }

    private func handleStreamFinished(streamID: UUID) {
        guard let streamState = activeStream, streamState.currentStreamID == streamID else {
            return
        }

        if streamState.terminalEventReceived {
            return
        }

        finishActiveStream(
            throwing: OpenAITaskPrepConversationServiceError.failedTurn(
                "The streamed response ended before the turn completed."
            )
        )
    }

    private func finishActiveStreamSuccessfully() {
        guard let streamState = activeStream else {
            return
        }

        streamState.continuation.yield(.completed)
        streamState.continuation.finish()
        activeStream = nil
    }

    private func finishActiveStream(throwing error: Error) {
        guard let streamState = activeStream else {
            return
        }

        streamState.streamTask?.cancel()
        streamState.continuation.finish(throwing: error)
        activeStream = nil
    }

    private func cancelActiveStream() {
        guard let streamState = activeStream else {
            return
        }

        streamState.streamTask?.cancel()
        streamState.continuation.finish()
        activeStream = nil
    }

    private static let systemPrompt = """
    You help turn one meeting task into clear implementation context.
    Stream short assistant updates as you think.
    Use the transcript tool when you need more meeting detail.
    Use the context draft tool when you have a better structured draft to share.
    Use the spawn agent tool only when the user clearly approved it.
    """

    private static func initialInputItems(for input: TaskPrepTurnInput) -> [[String: Any]] {
        [
            messagePayload(role: "system", text: systemPrompt),
            messagePayload(role: "user", text: userPrompt(for: input))
        ]
    }

    private static func userPrompt(for input: TaskPrepTurnInput) -> String {
        """
        Prepare implementation context for this task.

        Task title: \(input.task.title)
        Task details: \(input.task.details)
        Task type: \(input.task.type.rawValue)
        Assignee hint: \(input.task.assigneeHint ?? "")
        Current evidence excerpt: \(input.task.evidenceExcerpt)

        Use get_meeting_transcript if you need more transcript detail.
        """
    }

    private static let tools: [[String: Any]] = [
        [
            "type": "function",
            "name": "get_meeting_transcript",
            "description": "Read transcript lines from the current meeting session.",
            "strict": true,
            "parameters": [
                "type": "object",
                "additionalProperties": false,
                "required": ["scope"],
                "properties": [
                    "scope": ["type": "string"]
                ]
            ]
        ],
        [
            "type": "function",
            "name": "spawn_agent",
            "description": "Request agent handoff after the user explicitly approves it.",
            "strict": true,
            "parameters": [
                "type": "object",
                "additionalProperties": false,
                "required": ["reason"],
                "properties": [
                    "reason": ["type": "string"]
                ]
            ]
        ],
        [
            "type": "function",
            "name": "update_context_draft",
            "description": "Send the latest structured task-prep context draft.",
            "strict": true,
            "parameters": [
                "type": "object",
                "additionalProperties": false,
                "required": [
                    "summary",
                    "goal",
                    "constraints",
                    "acceptanceCriteria",
                    "risks",
                    "openQuestions",
                    "evidence",
                    "readyToSpawn"
                ],
                "properties": [
                    "summary": ["type": "string"],
                    "goal": ["type": "string"],
                    "constraints": [
                        "type": "array",
                        "items": ["type": "string"]
                    ],
                    "acceptanceCriteria": [
                        "type": "array",
                        "items": ["type": "string"]
                    ],
                    "risks": [
                        "type": "array",
                        "items": ["type": "string"]
                    ],
                    "openQuestions": [
                        "type": "array",
                        "items": ["type": "string"]
                    ],
                    "evidence": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "additionalProperties": false,
                            "required": ["id", "label", "excerpt", "segmentIDs"],
                            "properties": [
                                "id": ["type": "string"],
                                "label": ["type": "string"],
                                "excerpt": ["type": "string"],
                                "segmentIDs": [
                                    "type": "array",
                                    "items": ["type": "string"]
                                ]
                            ]
                        ]
                    ],
                    "readyToSpawn": ["type": "boolean"]
                ]
            ]
        ]
    ]

    private func decodeToolEvent(name: String, arguments: String) throws -> TaskPrepConversationEvent? {
        switch name {
        case "get_meeting_transcript":
            let request: TranscriptToolArguments = try decodeToolArguments(arguments, toolName: name)
            return .transcriptToolRequest(.init(scope: request.scope))
        case "spawn_agent":
            let request: SpawnToolArguments = try decodeToolArguments(arguments, toolName: name)
            return .spawnAgentRequest(.init(reason: request.reason))
        case "update_context_draft":
            let draft: ContextDraftToolArguments = try decodeToolArguments(arguments, toolName: name)
            return .contextDraft(draft.asContextDraft)
        default:
            return nil
        }
    }

    private func decodeToolArguments<Arguments: Decodable>(
        _ arguments: String,
        toolName: String
    ) throws -> Arguments {
        guard let data = arguments.data(using: .utf8) else {
            throw OpenAITaskPrepConversationServiceError.invalidToolArguments(
                toolName: toolName,
                message: "The tool arguments were not valid UTF-8."
            )
        }

        do {
            return try JSONDecoder().decode(Arguments.self, from: data)
        } catch {
            throw OpenAITaskPrepConversationServiceError.invalidToolArguments(
                toolName: toolName,
                message: error.localizedDescription
            )
        }
    }

    private static func transcriptToolOutput(
        scope: TaskPrepTranscriptRequest,
        session: TranscriptSession
    ) -> String {
        """
        Requested scope: \(scope.scope)
        Transcript:
        \(formattedTranscript(session))
        """
    }

    private static func functionCallOutputItem(callID: String, output: String) -> [String: Any] {
        [
            "type": "function_call_output",
            "call_id": callID,
            "output": output
        ]
    }

    private static func messagePayload(role: String, text: String) -> [String: Any] {
        [
            "role": role,
            "content": [
                [
                    "type": "input_text",
                    "text": text
                ]
            ]
        ]
    }

    private static func formattedTranscript(_ session: TranscriptSession) -> String {
        session.segments.enumerated().map { index, segment in
            let start = Int(segment.startedAt.rounded(.down))
            let end = Int(segment.endedAt.rounded(.up))
            return "\(index + 1). [\(segment.source.rawValue.uppercased()) \(start)s-\(end)s] \(segment.text.heedCollapsedWhitespace)"
        }
        .joined(separator: "\n")
    }
}

private struct TranscriptToolArguments: Decodable {
    let scope: String
}

private struct SpawnToolArguments: Decodable {
    let reason: String
}

private struct ContextDraftToolArguments: Decodable {
    let summary: String
    let goal: String
    let constraints: [String]
    let acceptanceCriteria: [String]
    let risks: [String]
    let openQuestions: [String]
    let evidence: [ContextDraftEvidence]
    let readyToSpawn: Bool

    var asContextDraft: TaskPrepContextDraft {
        TaskPrepContextDraft(
            summary: summary,
            goal: goal,
            constraints: constraints,
            acceptanceCriteria: acceptanceCriteria,
            risks: risks,
            openQuestions: openQuestions,
            evidence: evidence.map(\.asEvidence),
            readyToSpawn: readyToSpawn
        )
    }
}

private struct ContextDraftEvidence: Decodable {
    let id: String
    let label: String
    let excerpt: String
    let segmentIDs: [UUID]

    var asEvidence: TaskPrepEvidence {
        TaskPrepEvidence(
            id: id,
            label: label,
            excerpt: excerpt,
            segmentIDs: segmentIDs
        )
    }
}
