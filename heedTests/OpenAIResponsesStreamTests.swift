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
            "data: {\"call_id\":\"call_123\",\"item_id\":\"item_123\",\"output_index\":0,\"sequence_number\":2,\"delta\":\"{\\\"approval\\\":true}\"}",
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .textDelta("Hello"),
            .functionArgumentsDelta(
                OpenAIStreamFunctionCallMetadata(
                    callID: "call_123",
                    itemID: "item_123",
                    outputIndex: 0,
                    sequenceNumber: 2
                ),
                "{\"approval\":true}"
            )
        ])
    }

    @Test func parserEmitsCompletedFunctionCallWithIdentityMetadata() throws {
        let payload = [
            "event: response.function_call_arguments.done",
            "data: {\"call_id\":\"call_123\",\"item_id\":\"item_123\",\"output_index\":0,\"sequence_number\":3,\"name\":\"get_meeting_transcript\",\"arguments\":\"{\\\"scope\\\":\\\"next_steps\\\"}\"}",
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .functionCallCompleted(
                OpenAIStreamFunctionCallMetadata(
                    callID: "call_123",
                    itemID: "item_123",
                    outputIndex: 0,
                    sequenceNumber: 3
                ),
                name: "get_meeting_transcript",
                arguments: "{\"scope\":\"next_steps\"}"
            )
        ])
    }

    @Test func parserFailsOnMalformedSSEPayload() {
        let payload = [
            "event: response.function_call_arguments.done",
            "data: {not-json}",
            ""
        ].joined(separator: "\n")

        do {
            _ = try OpenAIResponsesStreamParser().parse(payload)
            Issue.record("Expected malformed SSE payload to fail")
        } catch let error as OpenAIResponsesStreamParseError {
            #expect(error == .invalidEventData(event: "response.function_call_arguments.done"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func parserEmitsFailedEventForResponseFailed() throws {
        let payload = [
            "event: response.failed",
            #"data: {"response":{"id":"resp_fail","status":"failed","status_details":{"error":{"message":"Transcript tool failed"}}}}"#,
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .failed("Transcript tool failed")
        ])
    }

    @Test func taskPrepServiceBuildsStreamingRequestWithTrimmedPromptAndTools() async throws {
        let transport = ScriptedStreamingTransport(
            payloads: [
                [
                    "event: response.completed",
                    #"data: {"response":{"id":"resp_initial"}}"#,
                    ""
                ].joined(separator: "\n")
            ]
        )
        let service = OpenAITaskPrepConversationService(
            client: OpenAIResponsesClient(
                model: "gpt-5.4",
                apiKeyProvider: { "sk-test" },
                transport: transport
            )
        )

        _ = try await collect(
            from: service.beginTurn(input: TaskPrepTurnInput(task: sampleTask(), session: sampleSession()))
        )

        let requests = transport.recordedJSONBodies()
        #expect(requests.count == 1)

        let request = try #require(requests.first)
        #expect(request["stream"] as? Bool == true)

        let tools = try #require(request["tools"] as? [[String: Any]])
        let toolNames = tools.compactMap { $0["name"] as? String }
        #expect(toolNames == ["get_meeting_transcript", "spawn_agent", "update_context_draft"])

        let input = try #require(request["input"] as? [[String: Any]])
        let allText = input
            .compactMap { $0["content"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")

        #expect(allText.contains(sampleTask().title))
        #expect(allText.contains(sampleTask().details))
        #expect(allText.contains(sampleTask().evidenceExcerpt))
        #expect(allText.contains("Transcript summary:") == false)
        #expect(allText.contains("We should prepare a context packet.") == false)
        #expect(allText.contains("[MIC") == false)
    }

    @Test func taskPrepServiceContinuesTranscriptToolRoundTrip() async throws {
        let transport = ScriptedStreamingTransport(
            payloads: [
                [
                    "event: response.function_call_arguments.done",
                    "data: {\"call_id\":\"call_transcript\",\"item_id\":\"item_transcript\",\"output_index\":0,\"sequence_number\":1,\"name\":\"get_meeting_transcript\",\"arguments\":\"{\\\"scope\\\":\\\"next_steps\\\"}\"}",
                    "",
                    "event: response.completed",
                    #"data: {"response":{"id":"resp_initial"}}"#,
                    ""
                ].joined(separator: "\n"),
                [
                    "event: response.output_text.delta",
                    "data: {\"delta\":\"I reviewed the transcript and updated the plan.\"}",
                    "",
                    "event: response.completed",
                    #"data: {"response":{"id":"resp_followup"}}"#,
                    ""
                ].joined(separator: "\n")
            ]
        )
        let session = sampleSession()
        let service = OpenAITaskPrepConversationService(
            client: OpenAIResponsesClient(
                model: "gpt-5.4",
                apiKeyProvider: { "sk-test" },
                transport: transport
            )
        )

        let stream = service.beginTurn(input: TaskPrepTurnInput(task: sampleTask(), session: session))
        var iterator = stream.makeAsyncIterator()

        let firstEvent = try #require(try await iterator.next())
        #expect(firstEvent == .transcriptToolRequest(.init(scope: "next_steps")))

        service.submitTranscript(scope: .init(scope: "next_steps"), session: session)

        var remainingEvents: [TaskPrepConversationEvent] = []
        while let event = try await iterator.next() {
            remainingEvents.append(event)
        }

        #expect(remainingEvents == [
            .assistantTextDelta("I reviewed the transcript and updated the plan."),
            .completed
        ])

        let requests = transport.recordedJSONBodies()
        #expect(requests.count == 2)

        let followupRequest = try #require(requests.last)
        #expect(followupRequest["previous_response_id"] as? String == "resp_initial")

        let followupInput = try #require(followupRequest["input"] as? [[String: Any]])
        let toolOutput = try #require(followupInput.first)
        #expect(toolOutput["type"] as? String == "function_call_output")
        #expect(toolOutput["call_id"] as? String == "call_transcript")

        let output = toolOutput["output"] as? String ?? ""
        #expect(output.contains("Requested scope: next_steps"))
        #expect(output.contains("We should prepare a context packet."))
        #expect(output.contains("The side panel should stay visible."))
    }

    @Test func taskPrepServiceContinuesConversationWithUserFollowUp() async throws {
        let transport = ScriptedStreamingTransport(
            payloads: [
                [
                    "event: response.output_text.delta",
                    "data: {\"delta\":\"What should we focus on next?\"}",
                    "",
                    "event: response.completed",
                    #"data: {"response":{"id":"resp_initial"}}"#,
                    ""
                ].joined(separator: "\n"),
                [
                    "event: response.output_text.delta",
                    "data: {\"delta\":\"Focus on the side panel behavior first.\"}",
                    "",
                    "event: response.completed",
                    #"data: {"response":{"id":"resp_followup"}}"#,
                    ""
                ].joined(separator: "\n")
            ]
        )
        let service = OpenAITaskPrepConversationService(
            client: OpenAIResponsesClient(
                model: "gpt-5.4",
                apiKeyProvider: { "sk-test" },
                transport: transport
            )
        )

        _ = try await collect(
            from: service.beginTurn(input: TaskPrepTurnInput(task: sampleTask(), session: sampleSession()))
        )

        let followUpEvents = try await collect(
            from: service.sendUserMessage("What did the meeting suggest?")
        )

        #expect(followUpEvents == [
            .assistantTextDelta("Focus on the side panel behavior first."),
            .completed
        ])

        let requests = transport.recordedJSONBodies()
        #expect(requests.count == 2)

        let followupRequest = try #require(requests.last)
        #expect(followupRequest["previous_response_id"] as? String == "resp_initial")

        let followupInput = try #require(followupRequest["input"] as? [[String: Any]])
        let userMessage = try #require(followupInput.first)
        #expect(userMessage["role"] as? String == "user")

        let content = try #require(userMessage["content"] as? [[String: Any]])
        let textItem = try #require(content.first)
        #expect(textItem["type"] as? String == "input_text")
        #expect(textItem["text"] as? String == "What did the meeting suggest?")
    }

    @Test func taskPrepServiceSurfacesResponseFailed() async {
        let transport = ScriptedStreamingTransport(
            payloads: [
                [
                    "event: response.failed",
                    #"data: {"response":{"id":"resp_fail","status":"failed","status_details":{"error":{"message":"OpenAI stopped the turn"}}}}"#,
                    ""
                ].joined(separator: "\n")
            ]
        )
        let service = OpenAITaskPrepConversationService(
            client: OpenAIResponsesClient(
                model: "gpt-5.4",
                apiKeyProvider: { "sk-test" },
                transport: transport
            )
        )

        do {
            _ = try await collect(
                from: service.beginTurn(input: TaskPrepTurnInput(task: sampleTask(), session: sampleSession()))
            )
            Issue.record("Expected response.failed to surface as a service error")
        } catch let error as OpenAITaskPrepConversationServiceError {
            #expect(error == .failedTurn("OpenAI stopped the turn"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func taskPrepServiceFailsInterruptedStreamWithoutTerminalEvent() async {
        let transport = ScriptedStreamingTransport(
            payloads: [
                [
                    "event: response.output_text.delta",
                    "data: {\"delta\":\"Partial answer\"}",
                    ""
                ].joined(separator: "\n")
            ]
        )
        let service = OpenAITaskPrepConversationService(
            client: OpenAIResponsesClient(
                model: "gpt-5.4",
                apiKeyProvider: { "sk-test" },
                transport: transport
            )
        )

        do {
            _ = try await collect(
                from: service.beginTurn(input: TaskPrepTurnInput(task: sampleTask(), session: sampleSession()))
            )
            Issue.record("Expected interrupted stream to surface as a service error")
        } catch let error as OpenAITaskPrepConversationServiceError {
            #expect(error == .failedTurn("The streamed response ended before the turn completed."))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private final class ScriptedStreamingTransport: @unchecked Sendable, OpenAIResponsesTransport {
    private let payloads: [String]
    private let lock = NSLock()
    private var nextPayloadIndex = 0
    private var requests: [URLRequest] = []

    init(payloads: [String]) {
        self.payloads = payloads
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            requests.append(request)
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (Data(), response)
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<String, Error> {
        let payload: String

        payload = lock.withLock {
            requests.append(request)
            let nextPayload = payloads.indices.contains(nextPayloadIndex) ? payloads[nextPayloadIndex] : ""
            nextPayloadIndex += 1
            return nextPayload
        }

        let lines = payload.components(separatedBy: .newlines)

        return AsyncThrowingStream { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }

    func recordedJSONBodies() -> [[String: Any]] {
        let capturedRequests = lock.withLock { requests }

        return capturedRequests.compactMap { request in
            guard let body = request.httpBody,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return nil
            }

            return object
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
