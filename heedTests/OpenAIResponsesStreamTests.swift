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

    @Test func parserAllowsFunctionArgumentDeltaWithoutCallID() throws {
        let payload = [
            "event: response.function_call_arguments.delta",
            "data: {\"item_id\":\"item_123\",\"output_index\":0,\"sequence_number\":2,\"delta\":\"{\\\"approval\\\":true}\"}",
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .functionArgumentsDelta(
                OpenAIStreamFunctionCallMetadata(
                    callID: nil,
                    itemID: "item_123",
                    outputIndex: 0,
                    sequenceNumber: 2
                ),
                "{\"approval\":true}"
            )
        ])
    }

    @Test func parserEmitsFunctionCallItemAddedWithCallID() throws {
        let payload = [
            "event: response.output_item.added",
            "data: {\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"item_123\",\"call_id\":\"call_123\",\"name\":\"get_meeting_transcript\",\"arguments\":\"\"}}",
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .functionCallItemAdded(
                OpenAIStreamFunctionCallIdentity(
                    metadata: OpenAIStreamFunctionCallMetadata(
                        callID: "call_123",
                        itemID: "item_123",
                        outputIndex: 0,
                        sequenceNumber: nil
                    ),
                    name: "get_meeting_transcript"
                )
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
                OpenAIStreamFunctionCallIdentity(
                    metadata: OpenAIStreamFunctionCallMetadata(
                        callID: "call_123",
                        itemID: "item_123",
                        outputIndex: 0,
                        sequenceNumber: 3
                    ),
                    name: "get_meeting_transcript"
                ),
                arguments: "{\"scope\":\"next_steps\"}"
            )
        ])
    }

    @Test func parserEmitsCompletedFunctionCallFromNestedItem() throws {
        let payload = [
            "event: response.function_call_arguments.done",
            "data: {\"output_index\":0,\"sequence_number\":3,\"item\":{\"id\":\"item_123\",\"call_id\":\"call_123\",\"name\":\"get_meeting_transcript\",\"arguments\":\"{\\\"scope\\\":\\\"next_steps\\\"}\"}}",
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .functionCallCompleted(
                OpenAIStreamFunctionCallIdentity(
                    metadata: OpenAIStreamFunctionCallMetadata(
                        callID: "call_123",
                        itemID: "item_123",
                        outputIndex: 0,
                        sequenceNumber: 3
                    ),
                    name: "get_meeting_transcript"
                ),
                arguments: "{\"scope\":\"next_steps\"}"
            )
        ])
    }

    @Test func parserAllowsCompletedFunctionCallWithoutName() throws {
        let payload = [
            "event: response.function_call_arguments.done",
            "data: {\"item_id\":\"item_123\",\"output_index\":0,\"sequence_number\":3,\"arguments\":\"{\\\"scope\\\":\\\"next_steps\\\"}\"}",
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .functionCallCompleted(
                OpenAIStreamFunctionCallIdentity(
                    metadata: OpenAIStreamFunctionCallMetadata(
                        callID: nil,
                        itemID: "item_123",
                        outputIndex: 0,
                        sequenceNumber: 3
                    ),
                    name: nil
                ),
                arguments: "{\"scope\":\"next_steps\"}"
            )
        ])
    }

    @Test func parserHandlesStreamingLinesWithoutBlankSeparators() throws {
        let payload = [
            "event: response.output_text.delta",
            "data: {\"delta\":\"Hello\"}",
            "event: response.completed",
            #"data: {"response":{"id":"resp_no_blank"}}"#
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .textDelta("Hello"),
            .completed(responseID: "resp_no_blank")
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
        #expect(allText.contains("If you need missing information from the user, ask only the direct question in chat.") == true)
        #expect(allText.contains("Do not narrate your process or mention internal tools.") == true)
        #expect(allText.contains("Stream short assistant updates as you think.") == false)
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
        #expect(output.contains(session.segments[0].id.uuidString))
        #expect(output.contains("We should prepare a context packet."))
        #expect(output.contains("The side panel should stay visible."))
    }

    @Test func taskPrepServiceUsesFunctionIdentityFromOutputItemAddedWhenDoneOmitsIt() async throws {
        let transport = ScriptedStreamingTransport(
            payloads: [
                [
                    "event: response.output_item.added",
                    "data: {\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"item_transcript\",\"call_id\":\"call_transcript\",\"name\":\"get_meeting_transcript\",\"arguments\":\"\"}}",
                    "",
                    "event: response.function_call_arguments.done",
                    "data: {\"item_id\":\"item_transcript\",\"output_index\":0,\"sequence_number\":1,\"arguments\":\"{\\\"scope\\\":\\\"next_steps\\\"}\"}",
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
        let followupRequest = try #require(requests.last)
        let followupInput = try #require(followupRequest["input"] as? [[String: Any]])
        let toolOutput = try #require(followupInput.first)
        #expect(toolOutput["call_id"] as? String == "call_transcript")
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

    @Test func taskPrepServiceIgnoresInvalidEvidenceSegmentIDsInContextDrafts() async throws {
        let session = sampleSession()
        let validSegmentID = session.segments[1].id.uuidString
        let transport = ScriptedStreamingTransport(
            payloads: [
                [
                    "event: response.function_call_arguments.done",
                    "data: {\"call_id\":\"call_draft\",\"item_id\":\"item_draft\",\"output_index\":0,\"sequence_number\":1,\"name\":\"update_context_draft\",\"arguments\":\"{\\\"summary\\\":\\\"Pin the context panel update.\\\",\\\"goal\\\":\\\"Stop the button from animating during the panel clip-down.\\\",\\\"constraints\\\":[\\\"Keep the current layout.\\\"],\\\"acceptanceCriteria\\\":[\\\"The reload button stays still during the closing transition.\\\"],\\\"risks\\\":[\\\"Animation state could leak between views.\\\"],\\\"openQuestions\\\":[],\\\"evidence\\\":[{\\\"id\\\":\\\"evidence-1\\\",\\\"label\\\":\\\"Transcript evidence\\\",\\\"excerpt\\\":\\\"The reload icon swings during clip-down.\\\",\\\"segmentIDs\\\":[\\\"line-2\\\",\\\"\(validSegmentID)\\\"]}],\\\"readyToSpawn\\\":false}\"}",
                    "",
                    "event: response.completed",
                    #"data: {"response":{"id":"resp_context"}}"#,
                    ""
                ].joined(separator: "\n"),
                [
                    "event: response.completed",
                    #"data: {"response":{"id":"resp_context_ack"}}"#,
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

        let events = try await collect(
            from: service.beginTurn(input: TaskPrepTurnInput(task: sampleTask(), session: session))
        )

        #expect(events == [
            .contextDraft(
                TaskPrepContextDraft(
                    summary: "Pin the context panel update.",
                    goal: "Stop the button from animating during the panel clip-down.",
                    constraints: ["Keep the current layout."],
                    acceptanceCriteria: ["The reload button stays still during the closing transition."],
                    risks: ["Animation state could leak between views."],
                    openQuestions: [],
                    evidence: [
                        TaskPrepEvidence(
                            id: "evidence-1",
                            label: "Transcript evidence",
                            excerpt: "The reload icon swings during clip-down.",
                            segmentIDs: [session.segments[1].id]
                        )
                    ],
                    readyToSpawn: false
                )
            ),
            .completed
        ])

        let requests = transport.recordedJSONBodies()
        #expect(requests.count == 2)

        let followupRequest = try #require(requests.last)
        #expect(followupRequest["previous_response_id"] as? String == "resp_context")

        let followupInput = try #require(followupRequest["input"] as? [[String: Any]])
        let toolOutput = try #require(followupInput.first)
        #expect(toolOutput["type"] as? String == "function_call_output")
        #expect(toolOutput["call_id"] as? String == "call_draft")
    }

    @Test func taskPrepServiceAcknowledgesContextDraftAndSpawnToolCalls() async throws {
        let transport = ScriptedStreamingTransport(
            payloads: [
                [
                    "event: response.function_call_arguments.done",
                    "data: {\"call_id\":\"call_draft\",\"item_id\":\"item_draft\",\"output_index\":0,\"sequence_number\":1,\"name\":\"update_context_draft\",\"arguments\":\"{\\\"summary\\\":\\\"Stable summary\\\",\\\"goal\\\":\\\"Collect more implementation context.\\\",\\\"constraints\\\":[\\\"Stay in the current workspace.\\\"],\\\"acceptanceCriteria\\\":[\\\"The assistant asks a direct follow-up question.\\\"],\\\"risks\\\":[\\\"The assistant could over-explain its plan.\\\"],\\\"openQuestions\\\":[],\\\"evidence\\\":[],\\\"readyToSpawn\\\":false}\"}",
                    "",
                    "event: response.function_call_arguments.done",
                    "data: {\"call_id\":\"call_spawn\",\"item_id\":\"item_spawn\",\"output_index\":1,\"sequence_number\":2,\"name\":\"spawn_agent\",\"arguments\":\"{\\\"reason\\\":\\\"The task looks implementation-ready after approval.\\\"}\"}",
                    "",
                    "event: response.completed",
                    #"data: {"response":{"id":"resp_initial"}}"#,
                    ""
                ].joined(separator: "\n"),
                [
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

        let events = try await collect(
            from: service.beginTurn(input: TaskPrepTurnInput(task: sampleTask(), session: sampleSession()))
        )

        #expect(events == [
            .contextDraft(
                TaskPrepContextDraft(
                    summary: "Stable summary",
                    goal: "Collect more implementation context.",
                    constraints: ["Stay in the current workspace."],
                    acceptanceCriteria: ["The assistant asks a direct follow-up question."],
                    risks: ["The assistant could over-explain its plan."],
                    openQuestions: [],
                    evidence: [],
                    readyToSpawn: false
                )
            ),
            .spawnAgentRequest(.init(reason: "The task looks implementation-ready after approval.")),
            .completed
        ])

        let requests = transport.recordedJSONBodies()
        #expect(requests.count == 2)

        let followupRequest = try #require(requests.last)
        #expect(followupRequest["previous_response_id"] as? String == "resp_initial")

        let followupInput = try #require(followupRequest["input"] as? [[String: Any]])
        #expect(followupInput.count == 2)

        let firstOutput = try #require(followupInput.first)
        let secondOutput = try #require(followupInput.last)
        #expect(firstOutput["type"] as? String == "function_call_output")
        #expect(firstOutput["call_id"] as? String == "call_draft")
        #expect(secondOutput["type"] as? String == "function_call_output")
        #expect(secondOutput["call_id"] as? String == "call_spawn")
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
