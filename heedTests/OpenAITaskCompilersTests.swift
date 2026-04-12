import Foundation
import Testing
@testable import heed

struct OpenAITaskCompilersTests {
    @Test func taskAnalysisCompilerMapsStructuredOutputIntoCompiledTasks() async throws {
        let transport = StubOpenAITransport(
            data: """
            {
              "output": [
                {
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"summary\\":\\"The meeting focused on shipping task compilation.\\",\\"tasks\\":[{\\"title\\":\\"Implement OpenAI compile flow\\",\\"details\\":\\"Replace the fixture compiler with a real OpenAI request.\\",\\"type\\":\\"feature\\",\\"assigneeHint\\":\\"Mac engineer\\",\\"evidenceIndices\\":[2],\\"evidenceExcerpt\\":\\"We need compile tasks to actually send the transcript to an LLM.\\"}],\\"decisions\\":[{\\"title\\":\\"Use GPT-5.4 mini for task compilation\\",\\"details\\":\\"Start with the faster network model for v1.\\",\\"evidenceIndices\\":[1],\\"evidenceExcerpt\\":\\"For the tasks let's use GPT 5.4 Mini.\\"}],\\"followUps\\":[{\\"title\\":\\"Add a settings surface for the API key\\",\\"details\\":\\"Expose a plain-text action in the bottom rail.\\",\\"evidenceIndices\\":[3],\\"evidenceExcerpt\\":\\"Let's make a button on the bottom for set api key.\\"}],\\"noTasksReason\\":\\"\\",\\"warnings\\":[]}"
                    }
                  ]
                }
              ]
            }
            """,
            statusCode: 200
        )
        let compiler = OpenAITaskAnalysisCompiler(
            client: OpenAIResponsesClient(
                apiKeyProvider: { "sk-test" },
                transport: transport
            )
        )

        let session = sampleTranscriptSession()
        let result = try await compiler.compile(session: session)

        #expect(result.summary == "The meeting focused on shipping task compilation.")
        #expect(result.tasks.count == 1)
        #expect(result.tasks[0].title == "Implement OpenAI compile flow")
        #expect(result.tasks[0].evidenceSegmentIDs == [session.segments[1].id])
        #expect(result.decisions.first?.evidenceSegmentIDs == [session.segments[0].id])
        #expect(result.followUps.first?.evidenceSegmentIDs == [session.segments[2].id])

        #expect(await transport.lastRequestedModel() == "gpt-5.4-mini")
    }

    @Test func taskContextCompilerMapsEvidenceIntoPanelContent() async throws {
        let transport = StubOpenAITransport(
            data: """
            {
              "output": [
                {
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"goal\\":\\"Prepare the task before handing it to an agent.\\",\\"whyItMatters\\":\\"The user wants to review context first.\\",\\"implementationNotes\\":[\\"Keep the transcript visible.\\",\\"Run the second pass only when the user asks.\\"],\\"acceptanceCriteria\\":[\\"The panel opens on the right.\\",\\"The final Spawn agent button lives inside the panel.\\"],\\"risks\\":[\\"The wrong task could stay selected after a refresh.\\"],\\"suggestedSkills\\":[\\"SwiftUI\\",\\"Structured output\\"],\\"evidence\\":[{\\"label\\":\\"Transcript evidence\\",\\"excerpt\\":\\"We need compile tasks to actually send the transcript to an LLM.\\",\\"evidenceIndices\\":[2]}]}"
                    }
                  ]
                }
              ]
            }
            """,
            statusCode: 200
        )
        let compiler = OpenAITaskContextCompiler(
            client: OpenAIResponsesClient(
                apiKeyProvider: { "sk-test" },
                transport: transport
            )
        )

        let session = sampleTranscriptSession()
        let task = CompiledTask(
            id: "implement-openai-compile-flow",
            title: "Implement OpenAI compile flow",
            details: "Replace the fixture compiler with a real OpenAI request.",
            type: .feature,
            assigneeHint: "Mac engineer",
            evidenceSegmentIDs: [session.segments[1].id],
            evidenceExcerpt: session.segments[1].text
        )

        let content = try await compiler.prepareTaskContext(session: session, task: task)

        #expect(content.goal == "Prepare the task before handing it to an agent.")
        #expect(content.evidence.count == 1)
        #expect(content.evidence[0].segmentIDs == [session.segments[1].id])
        #expect(content.suggestedSkills == ["SwiftUI", "Structured output"])
    }
}

private actor StubOpenAITransport: OpenAIResponsesTransport {
    private let responseData: Data
    private let statusCode: Int
    private var requests: [URLRequest] = []

    init(data: String, statusCode: Int) {
        self.responseData = Data(data.utf8)
        self.statusCode = statusCode
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        return (responseData, response)
    }

    func lastRequestedModel() -> String? {
        guard let body = requests.last?.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        return object["model"] as? String
    }
}

private func sampleTranscriptSession() -> TranscriptSession {
    TranscriptSession(
        startedAt: Date(timeIntervalSince1970: 0),
        endedAt: Date(timeIntervalSince1970: 15),
        duration: 15,
        status: .completed,
        modelName: "ggml-base.en",
        appVersion: "1.0",
        segments: [
            TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2, text: "For the tasks let's use GPT 5.4 Mini."),
            TranscriptSegment(source: .system, startedAt: 3, endedAt: 4, text: "We need compile tasks to actually send the transcript to an LLM."),
            TranscriptSegment(source: .mic, startedAt: 5, endedAt: 6, text: "Let's make a button on the bottom for set api key.")
        ]
    )
}
