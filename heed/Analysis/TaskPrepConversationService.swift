import Foundation

protocol TaskPrepConversationServicing: Sendable {
    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error>
}

enum OpenAITaskPrepConversationServiceError: LocalizedError, Equatable {
    case failedTurn(String)

    var errorDescription: String? {
        switch self {
        case let .failedTurn(message):
            return "Task prep failed: \(message)"
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
}
