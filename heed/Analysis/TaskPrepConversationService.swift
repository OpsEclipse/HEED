import Foundation

protocol TaskPrepConversationServicing: Sendable {
    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error>
    func submitTranscript(scope: TaskPrepTranscriptRequest, session: TranscriptSession)
}

extension TaskPrepConversationServicing {
    func submitTranscript(scope: TaskPrepTranscriptRequest, session: TranscriptSession) {}
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
    private struct PendingTranscriptRequest {
        let request: TaskPrepTranscriptRequest
        let metadata: OpenAIStreamFunctionCallMetadata
    }

    private struct QueuedTranscriptOutput {
        let callID: String
        let output: String
    }

    private struct ActiveTurn {
        let input: TaskPrepTurnInput
        let continuation: AsyncThrowingStream<TaskPrepConversationEvent, Error>.Continuation
        var streamTask: Task<Void, Never>?
        var currentStreamID: UUID?
        var pendingTranscriptRequest: PendingTranscriptRequest?
        var queuedTranscriptOutput: QueuedTranscriptOutput?
        var lastResponseID: String?
        var isStreaming = false
    }

    private let client: OpenAIResponsesClient
    private var activeTurn: ActiveTurn?

    init(client: OpenAIResponsesClient = OpenAIResponsesClient(model: "gpt-5.4")) {
        self.client = client
    }

    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        cancelActiveTurn()

        return AsyncThrowingStream { continuation in
            self.activeTurn = ActiveTurn(
                input: input,
                continuation: continuation
            )
            self.startStreaming(
                inputItems: Self.initialInputItems(for: input),
                previousResponseID: nil
            )

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.cancelActiveTurn()
                }
            }
        }
    }

    func submitTranscript(scope: TaskPrepTranscriptRequest, session: TranscriptSession) {
        guard var turn = activeTurn,
              let pendingRequest = turn.pendingTranscriptRequest,
              pendingRequest.request == scope,
              session.id == turn.input.session.id else {
            return
        }

        turn.queuedTranscriptOutput = QueuedTranscriptOutput(
            callID: pendingRequest.metadata.callID,
            output: Self.transcriptToolOutput(scope: scope, session: session)
        )
        activeTurn = turn
        continueWithQueuedTranscriptOutputIfPossible()
    }

    private func startStreaming(inputItems: [[String: Any]], previousResponseID: String?) {
        guard var turn = activeTurn else {
            return
        }

        do {
            let streamID = UUID()
            let stream = try client.streamConversation(
                input: inputItems,
                tools: Self.tools,
                previousResponseID: previousResponseID
            )

            turn.isStreaming = true
            turn.currentStreamID = streamID
            turn.streamTask = Task { [weak self] in
                do {
                    for try await event in stream {
                        await MainActor.run {
                            self?.handle(event, fromStreamID: streamID)
                        }
                    }

                    await MainActor.run {
                        self?.markStreamIdle(streamID: streamID)
                    }
                } catch {
                    await MainActor.run {
                        self?.finishActiveTurn(throwing: error)
                    }
                }
            }
            activeTurn = turn
        } catch {
            finishActiveTurn(throwing: error)
        }
    }

    private func handle(_ event: OpenAIStreamEvent, fromStreamID streamID: UUID) {
        guard var turn = activeTurn, turn.currentStreamID == streamID else {
            return
        }

        switch event {
        case let .textDelta(delta):
            turn.continuation.yield(.assistantTextDelta(delta))
            activeTurn = turn
        case .functionArgumentsDelta:
            activeTurn = turn
        case let .functionCallCompleted(metadata, name, arguments):
            do {
                if let toolEvent = try decodeToolEvent(name: name, arguments: arguments) {
                    switch toolEvent {
                    case let .transcriptToolRequest(request):
                        turn.pendingTranscriptRequest = PendingTranscriptRequest(
                            request: request,
                            metadata: metadata
                        )
                        turn.continuation.yield(toolEvent)
                    case .contextDraft, .spawnAgentRequest:
                        turn.continuation.yield(toolEvent)
                    default:
                        break
                    }
                }

                activeTurn = turn
            } catch {
                finishActiveTurn(throwing: error)
            }
        case let .completed(responseID):
            turn.isStreaming = false
            turn.currentStreamID = nil
            turn.lastResponseID = responseID
            activeTurn = turn

            if turn.queuedTranscriptOutput != nil {
                continueWithQueuedTranscriptOutputIfPossible()
                return
            }

            if turn.pendingTranscriptRequest != nil {
                return
            }

            turn.continuation.yield(.completed)
            turn.continuation.finish()
            activeTurn = nil
        case let .failed(message):
            finishActiveTurn(throwing: OpenAITaskPrepConversationServiceError.failedTurn(message))
        }
    }

    private func continueWithQueuedTranscriptOutputIfPossible() {
        guard var turn = activeTurn,
              !turn.isStreaming,
              let queuedTranscriptOutput = turn.queuedTranscriptOutput,
              let previousResponseID = turn.lastResponseID else {
            return
        }

        turn.queuedTranscriptOutput = nil
        turn.pendingTranscriptRequest = nil
        turn.lastResponseID = nil
        activeTurn = turn

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

    private func markStreamIdle(streamID: UUID) {
        guard var turn = activeTurn, turn.currentStreamID == streamID else {
            return
        }

        turn.isStreaming = false
        turn.currentStreamID = nil
        activeTurn = turn
    }

    private func finishActiveTurn(throwing error: Error) {
        guard let turn = activeTurn else {
            return
        }

        turn.streamTask?.cancel()
        turn.continuation.finish(throwing: error)
        activeTurn = nil
    }

    private func cancelActiveTurn() {
        guard let turn = activeTurn else {
            return
        }

        turn.streamTask?.cancel()
        turn.continuation.finish()
        activeTurn = nil
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
