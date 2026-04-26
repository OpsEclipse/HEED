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
        var composioMCPTool: ComposioMCPTool?
        var didResolveComposioMCPTool = false
    }

    private struct PendingTranscriptRequest {
        let request: TaskPrepTranscriptRequest
        let callID: String
    }

    private struct QueuedFunctionOutput {
        let callID: String
        let output: String
    }

    private struct ActiveStream {
        struct FunctionCallRecord {
            let metadata: OpenAIStreamFunctionCallMetadata
            let name: String?
        }

        let continuation: AsyncThrowingStream<TaskPrepConversationEvent, Error>.Continuation
        var streamTask: Task<Void, Never>?
        var currentStreamID: UUID?
        var pendingTranscriptRequest: PendingTranscriptRequest?
        var queuedFunctionOutputs: [QueuedFunctionOutput] = []
        var functionCallRecordByItemID: [String: FunctionCallRecord] = [:]
        var functionCallRecordByOutputIndex: [Int: FunctionCallRecord] = [:]
        var terminalEventReceived = false
        var isStreaming = false
    }

    private let client: OpenAIResponsesClient
    private let composioSessionProvider: any ComposioSessionProviding
    private var conversationContext: ConversationContext?
    private var activeStream: ActiveStream?

    init(
        client: OpenAIResponsesClient = OpenAIResponsesClient(model: "gpt-5.4"),
        composioSessionProvider: any ComposioSessionProviding = ComposioToolRouterSessionProvider()
    ) {
        self.client = client
        self.composioSessionProvider = composioSessionProvider
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

        stream.pendingTranscriptRequest = nil
        stream.queuedFunctionOutputs.append(
            QueuedFunctionOutput(
            callID: pendingRequest.callID,
            output: Self.transcriptToolOutput(scope: scope, session: session)
        )
        )
        activeStream = stream
        continueWithQueuedToolOutputsIfPossible()
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

        let streamID = UUID()
        streamState.isStreaming = true
        streamState.currentStreamID = streamID
        streamState.terminalEventReceived = false
        streamState.streamTask = Task { [weak self] in
            do {
                guard let self else {
                    return
                }

                let responseTools = try await self.responseTools()
                try Task.checkCancellation()

                let stream = try self.client.streamConversation(
                    input: inputItems,
                    tools: responseTools,
                    previousResponseID: previousResponseID
                )

                for try await event in stream {
                    await MainActor.run {
                        self.handle(event, fromStreamID: streamID)
                    }
                }

                await MainActor.run {
                    self.handleStreamFinished(streamID: streamID)
                }
            } catch {
                await MainActor.run {
                    self?.finishActiveStream(throwing: error)
                }
            }
        }
        activeStream = streamState
    }

    private func responseTools() async throws -> [[String: Any]] {
        if conversationContext?.didResolveComposioMCPTool == false {
            let tool = try await composioSessionProvider.makeMCPTool()
            conversationContext?.composioMCPTool = tool
            conversationContext?.didResolveComposioMCPTool = true
        }

        var tools = Self.tools
        if let composioMCPTool = conversationContext?.composioMCPTool {
            tools.append(composioMCPTool.responseToolPayload)
        }

        return tools
    }

    private func handle(_ event: OpenAIStreamEvent, fromStreamID streamID: UUID) {
        guard var streamState = activeStream, streamState.currentStreamID == streamID else {
            return
        }

        switch event {
        case let .textDelta(delta):
            streamState.continuation.yield(.assistantTextDelta(delta))
            activeStream = streamState
        case let .functionCallItemAdded(identity):
            rememberFunctionCallIdentity(identity, in: &streamState)
            activeStream = streamState
        case let .functionArgumentsDelta(metadata, _):
            rememberFunctionCallMetadata(metadata, in: &streamState)
            activeStream = streamState
        case let .functionCallCompleted(identity, arguments):
            do {
                let resolvedIdentity = resolvedFunctionCallIdentity(from: identity, in: streamState)
                rememberFunctionCallIdentity(resolvedIdentity, in: &streamState)

                guard let name = resolvedIdentity.name else {
                    throw OpenAIResponsesStreamParseError.missingRequiredField(
                        event: "response.function_call_arguments.done",
                        field: "name"
                    )
                }

                if let toolEvent = try decodeToolEvent(name: name, arguments: arguments) {
                    switch toolEvent {
                    case let .transcriptToolRequest(request):
                        guard let callID = resolvedIdentity.metadata.callID else {
                            throw OpenAITaskPrepConversationServiceError.failedTurn(
                                "Streamed tool call was missing call_id."
                            )
                        }

                        streamState.pendingTranscriptRequest = PendingTranscriptRequest(
                            request: request,
                            callID: callID
                        )
                        streamState.continuation.yield(toolEvent)
                    case .contextDraft:
                        try queueToolOutput(
                            callID: resolvedIdentity.metadata.callID,
                            output: Self.contextDraftToolOutput(),
                            in: &streamState
                        )
                        streamState.continuation.yield(toolEvent)
                    case let .spawnAgentRequest(request):
                        try queueToolOutput(
                            callID: resolvedIdentity.metadata.callID,
                            output: Self.spawnAgentToolOutput(reason: request.reason),
                            in: &streamState
                        )
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

            if !streamState.queuedFunctionOutputs.isEmpty {
                continueWithQueuedToolOutputsIfPossible()
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

    private func rememberFunctionCallMetadata(
        _ metadata: OpenAIStreamFunctionCallMetadata,
        in streamState: inout ActiveStream
    ) {
        rememberFunctionCallIdentity(
            OpenAIStreamFunctionCallIdentity(metadata: metadata, name: nil),
            in: &streamState
        )
    }

    private func rememberFunctionCallIdentity(
        _ identity: OpenAIStreamFunctionCallIdentity,
        in streamState: inout ActiveStream
    ) {
        let matchedRecord =
            identity.metadata.itemID.flatMap { streamState.functionCallRecordByItemID[$0] }
            ?? identity.metadata.outputIndex.flatMap { streamState.functionCallRecordByOutputIndex[$0] }

        let record = ActiveStream.FunctionCallRecord(
            metadata: OpenAIStreamFunctionCallMetadata(
                callID: identity.metadata.callID ?? matchedRecord?.metadata.callID,
                itemID: identity.metadata.itemID ?? matchedRecord?.metadata.itemID,
                outputIndex: identity.metadata.outputIndex ?? matchedRecord?.metadata.outputIndex,
                sequenceNumber: identity.metadata.sequenceNumber ?? matchedRecord?.metadata.sequenceNumber
            ),
            name: identity.name ?? matchedRecord?.name
        )

        if let itemID = record.metadata.itemID {
            streamState.functionCallRecordByItemID[itemID] = record
        }

        if let outputIndex = record.metadata.outputIndex {
            streamState.functionCallRecordByOutputIndex[outputIndex] = record
        }
    }

    private func resolvedFunctionCallIdentity(
        from identity: OpenAIStreamFunctionCallIdentity,
        in streamState: ActiveStream
    ) -> OpenAIStreamFunctionCallIdentity {
        let resolvedMetadata = resolvedFunctionCallMetadata(from: identity.metadata, in: streamState)
        let matchedRecord =
            resolvedMetadata.itemID.flatMap { streamState.functionCallRecordByItemID[$0] }
            ?? resolvedMetadata.outputIndex.flatMap { streamState.functionCallRecordByOutputIndex[$0] }

        return OpenAIStreamFunctionCallIdentity(
            metadata: resolvedMetadata,
            name: identity.name ?? matchedRecord?.name
        )
    }

    private func resolvedFunctionCallMetadata(
        from metadata: OpenAIStreamFunctionCallMetadata,
        in streamState: ActiveStream
    ) -> OpenAIStreamFunctionCallMetadata {
        guard metadata.callID == nil else {
            return metadata
        }

        let matchedRecord =
            metadata.itemID.flatMap { streamState.functionCallRecordByItemID[$0] }
            ?? metadata.outputIndex.flatMap { streamState.functionCallRecordByOutputIndex[$0] }

        guard let matchedRecord else {
            return metadata
        }

        return OpenAIStreamFunctionCallMetadata(
            callID: matchedRecord.metadata.callID,
            itemID: metadata.itemID ?? matchedRecord.metadata.itemID,
            outputIndex: metadata.outputIndex ?? matchedRecord.metadata.outputIndex,
            sequenceNumber: metadata.sequenceNumber ?? matchedRecord.metadata.sequenceNumber
        )
    }

    private func queueToolOutput(
        callID: String?,
        output: String,
        in streamState: inout ActiveStream
    ) throws {
        guard let callID else {
            throw OpenAITaskPrepConversationServiceError.failedTurn(
                "Streamed tool call was missing call_id."
            )
        }

        streamState.queuedFunctionOutputs.append(
            QueuedFunctionOutput(callID: callID, output: output)
        )
    }

    private func continueWithQueuedToolOutputsIfPossible() {
        guard var streamState = activeStream,
              let previousResponseID = conversationContext?.lastResponseID,
              !streamState.isStreaming,
              streamState.pendingTranscriptRequest == nil,
              !streamState.queuedFunctionOutputs.isEmpty else {
            return
        }

        let queuedFunctionOutputs = streamState.queuedFunctionOutputs
        streamState.queuedFunctionOutputs = []
        streamState.terminalEventReceived = false
        activeStream = streamState

        startStreaming(
            inputItems: queuedFunctionOutputs.map { queuedOutput in
                Self.functionCallOutputItem(
                    callID: queuedOutput.callID,
                    output: queuedOutput.output
                )
            },
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
    Use the transcript tool when you need more meeting detail.
    Use Composio tools for Gmail, Google Calendar, and Google Drive only when they are relevant to the current task.
    Ask for clear user confirmation before sending email, creating or changing calendar events, or changing external app data.
    Use the context draft tool when you have a better structured draft to share.
    Use the spawn agent tool only when the user clearly approved it.
    If you need missing information from the user, ask only the direct question in chat.
    Do not narrate your process or mention internal tools.
    Keep the chat natural and concise while the draft keeps improving in the background.
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
                                    "description": "Use transcript segment UUID strings from get_meeting_transcript when available. Otherwise return an empty array.",
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

    private static func contextDraftToolOutput() -> String {
        "Context draft received."
    }

    private static func spawnAgentToolOutput(reason: String) -> String {
        "Spawn request recorded and is waiting for explicit user approval. Reason: \(reason)"
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
            return "\(index + 1). [SEGMENT_ID \(segment.id.uuidString)] [\(segment.source.rawValue.uppercased()) \(start)s-\(end)s] \(segment.text.heedCollapsedWhitespace)"
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
    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case excerpt
        case segmentIDs
    }

    let id: String
    let label: String
    let excerpt: String
    private let rawSegmentIDs: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        excerpt = try container.decode(String.self, forKey: .excerpt)
        rawSegmentIDs = try container.decode([String].self, forKey: .segmentIDs)
    }

    var asEvidence: TaskPrepEvidence {
        TaskPrepEvidence(
            id: id,
            label: label,
            excerpt: excerpt,
            segmentIDs: rawSegmentIDs.compactMap(UUID.init(uuidString:))
        )
    }
}
