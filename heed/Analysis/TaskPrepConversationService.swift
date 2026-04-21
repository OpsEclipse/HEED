import Foundation

protocol TaskPrepConversationServicing: Sendable {
    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error>
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

struct OpenAITaskPrepConversationService: TaskPrepConversationServicing {
    private let client: OpenAIResponsesClient

    init(client: OpenAIResponsesClient = OpenAIResponsesClient(model: "gpt-5.4")) {
        self.client = client
    }

    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                let stream = try client.streamConversation(
                    systemPrompt: Self.systemPrompt,
                    userPrompt: Self.userPrompt(for: input),
                    tools: Self.tools
                )

                let task = Task {
                    do {
                        for try await event in stream {
                            switch event {
                            case let .textDelta(delta):
                                continuation.yield(.assistantTextDelta(delta))
                            case .functionArgumentsDelta:
                                continue
                            case let .functionCallCompleted(name, arguments):
                                if let toolEvent = try decodeToolEvent(name: name, arguments: arguments) {
                                    continuation.yield(toolEvent)
                                }
                            case .completed:
                                continuation.yield(.completed)
                            case let .failed(message):
                                throw OpenAITaskPrepConversationServiceError.failedTurn(message)
                            }
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private static let systemPrompt = """
    You help turn one meeting task into clear implementation context.
    Stream short assistant updates as you think.
    Use the transcript tool when you need transcript detail.
    Use the context draft tool when you have a better structured draft to share.
    Use the spawn agent tool only when the user clearly approved it.
    """

    private static func userPrompt(for input: TaskPrepTurnInput) -> String {
        """
        Prepare implementation context for this task.

        Task title: \(input.task.title)
        Task details: \(input.task.details)
        Task type: \(input.task.type.rawValue)
        Assignee hint: \(input.task.assigneeHint ?? "")
        Evidence excerpt: \(input.task.evidenceExcerpt)

        Transcript summary:
        \(formattedTranscript(input.session))
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

    private static func formattedTranscript(_ session: TranscriptSession) -> String {
        session.segments.enumerated().map { index, segment in
            let start = Int(segment.startedAt.rounded(.down))
            let end = Int(segment.endedAt.rounded(.up))
            return "\(index + 1). [\(segment.source.rawValue.uppercased()) \(start)s-\(end)s] \(segment.text.heedCollapsedWhitespace)"
        }
        .joined(separator: "\n")
    }

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
