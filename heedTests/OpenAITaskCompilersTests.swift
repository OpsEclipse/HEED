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
                      "text": "{\\"summary\\":\\"The meeting focused on shipping task compilation.\\",\\"tasks\\":[{\\"title\\":\\"Implement OpenAI compile flow\\",\\"details\\":\\"Replace the fixture compiler with a real OpenAI request and keep the feature work grouped into one deliverable.\\",\\"type\\":\\"feature\\",\\"assigneeHint\\":\\"Mac engineer\\",\\"evidenceIndices\\":[2,3],\\"evidenceExcerpt\\":\\"We need compile tasks to actually send the transcript to an LLM.\\"},{\\"title\\":\\"Fix the stale task panel state\\",\\"details\\":\\"Stop old task-context responses from landing on the newly selected task.\\",\\"type\\":\\"bug_fix\\",\\"assigneeHint\\":\\"Mac engineer\\",\\"evidenceIndices\\":[4],\\"evidenceExcerpt\\":\\"Sometimes the previous task stays selected after reload.\\"},{\\"title\\":\\"Email the rollout note to support\\",\\"details\\":\\"Send a short update once the compile flow ships.\\",\\"type\\":\\"miscellaneous\\",\\"assigneeHint\\":\\"Product lead\\",\\"evidenceIndices\\":[5],\\"evidenceExcerpt\\":\\"After it ships, send support a note.\\"}],\\"noTasksReason\\":\\"\\",\\"warnings\\":[]}"
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
        #expect(result.tasks.count == 3)
        #expect(result.tasks[0].title == "Implement OpenAI compile flow")
        #expect(result.tasks[0].evidenceSegmentIDs == [session.segments[1].id, session.segments[2].id])
        #expect(result.tasks.map(\.type.rawValue) == ["Feature", "Bug fix", "Miscellaneous"])
        #expect(result.noTasksReason == nil)

        #expect(await transport.lastRequestedModel() == "gpt-5.4-mini")
    }

    @Test func taskAnalysisCompilerRequestAsksToKeepOneFeatureGroupedIntoOneTask() async throws {
        let transport = StubOpenAITransport(
            data: """
            {
              "output": [
                {
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"summary\\":\\"One feature was discussed.\\",\\"tasks\\":[],\\"noTasksReason\\":\\"\\",\\"warnings\\":[]}"
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

        _ = try await compiler.compile(session: sampleTranscriptSession())

        let systemPrompt = await transport.lastRequestedInputText(role: "system")

        #expect(systemPrompt?.contains("Do not split one feature into multiple tasks") == true)
        #expect(systemPrompt?.contains("Use miscellaneous for non-feature, non-bug action items") == true)
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

    func lastRequestedInputText(role: String) -> String? {
        guard let body = requests.last?.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let input = object["input"] as? [[String: Any]] else {
            return nil
        }

        guard let message = input.first(where: { ($0["role"] as? String) == role }),
              let content = message["content"] as? [[String: Any]] else {
            return nil
        }

        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
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
            TranscriptSegment(source: .mic, startedAt: 5, endedAt: 6, text: "The whole feature should stay grouped into one implementation task."),
            TranscriptSegment(source: .system, startedAt: 7, endedAt: 8, text: "Sometimes the previous task stays selected after reload."),
            TranscriptSegment(source: .mic, startedAt: 9, endedAt: 10, text: "After it ships, send support a note.")
        ]
    )
}
