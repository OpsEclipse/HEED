import Foundation
import Testing
@testable import heed

@MainActor
struct OpenAIResponsesStreamTests {
    @Test func parserEmitsTextAndFunctionArgumentDeltasInOrder() throws {
        let payload = [
            "event: response.output_text.delta",
            "data: {\"delta\":\"Hello\"}",
            "",
            "event: response.function_call_arguments.delta",
            "data: {\"delta\":\"{\\\"approval\\\":true}\"}",
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .textDelta("Hello"),
            .functionArgumentsDelta("{\"approval\":true}")
        ])
    }

    @Test func parserEmitsCompletedFunctionCallWithNameAndArguments() throws {
        let payload = [
            "event: response.function_call_arguments.done",
            "data: {\"name\":\"get_meeting_transcript\",\"arguments\":\"{\\\"scope\\\":\\\"next_steps\\\"}\"}",
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .functionCallCompleted(
                name: "get_meeting_transcript",
                arguments: "{\"scope\":\"next_steps\"}"
            )
        ])
    }

    @Test func taskPrepServiceMapsCompletedToolCallsIntoConversationEvents() async throws {
        let session = sampleSession()
        let expectedDraft = TaskPrepContextDraft(
            summary: "Ready to act",
            goal: "Prepare the implementation handoff",
            constraints: ["Keep the transcript visible"],
            acceptanceCriteria: ["The prep workspace shows the live draft"],
            risks: ["A stale tool result could land on the wrong task"],
            openQuestions: ["Should support get a rollout note?"],
            evidence: [
                TaskPrepEvidence(
                    id: "evidence-1",
                    label: "Transcript proof",
                    excerpt: session.segments[0].text,
                    segmentIDs: [session.segments[0].id]
                )
            ],
            readyToSpawn: true
        )

        let streamedPayload = [
            "event: response.output_text.delta",
            "data: {\"delta\":\"I pulled the transcript. \"}",
            "",
            "event: response.function_call_arguments.done",
            "data: {\"name\":\"get_meeting_transcript\",\"arguments\":\"{\\\"scope\\\":\\\"next_steps\\\"}\"}",
            "",
            "event: response.function_call_arguments.done",
            #"data: {"name":"update_context_draft","arguments":"{\"summary\":\"Ready to act\",\"goal\":\"Prepare the implementation handoff\",\"constraints\":[\"Keep the transcript visible\"],\"acceptanceCriteria\":[\"The prep workspace shows the live draft\"],\"risks\":[\"A stale tool result could land on the wrong task\"],\"openQuestions\":[\"Should support get a rollout note?\"],\"evidence\":[{\"id\":\"evidence-1\",\"label\":\"Transcript proof\",\"excerpt\":\"\#(session.segments[0].text)\",\"segmentIDs\":[\"\#(session.segments[0].id.uuidString)\"]}],\"readyToSpawn\":true}"}"#,
            "",
            "event: response.function_call_arguments.done",
            "data: {\"name\":\"spawn_agent\",\"arguments\":\"{\\\"reason\\\":\\\"ready\\\"}\"}",
            "",
            "event: response.completed",
            "data: {}",
            ""
        ].joined(separator: "\n")

        let service = OpenAITaskPrepConversationService(
            client: OpenAIResponsesClient(
                model: "gpt-5.4",
                apiKeyProvider: { "sk-test" },
                transport: StreamOnlyOpenAITransport(payload: streamedPayload)
            )
        )

        let events = try await collect(
            from: service.beginTurn(input: TaskPrepTurnInput(task: sampleTask(), session: session))
        )

        #expect(events == [
            .assistantTextDelta("I pulled the transcript. "),
            .transcriptToolRequest(.init(scope: "next_steps")),
            .contextDraft(expectedDraft),
            .spawnAgentRequest(.init(reason: "ready")),
            .completed
        ])
    }
}

private struct StreamOnlyOpenAITransport: OpenAIResponsesTransport, Sendable {
    private let payload: String

    init(payload: String) {
        self.payload = payload
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<String, Error> {
        let lines = payload.components(separatedBy: .newlines)

        return AsyncThrowingStream { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}

private func collect(
    from stream: AsyncThrowingStream<TaskPrepConversationEvent, Error>
) async throws -> [TaskPrepConversationEvent] {
    var events: [TaskPrepConversationEvent] = []

    for try await event in stream {
        events.append(event)
    }

    return events
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
