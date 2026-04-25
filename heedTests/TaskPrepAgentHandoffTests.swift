import Foundation
import Testing
@testable import heed

@MainActor
struct TaskPrepAgentHandoffTests {
    @Test func promptBuilderCreatesCompressedHandoffWithoutFullTranscript() {
        let citedSegmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let unrelatedSegmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let prompt = TaskPrepAgentHandoffPromptBuilder.buildPrompt(
            task: CompiledTask(
                id: "task-1",
                title: "Fix spawn handoff",
                details: "Make the spawned agent start with a concise handoff.",
                type: .bugFix,
                assigneeHint: "Codex",
                evidenceSegmentIDs: [citedSegmentID],
                evidenceExcerpt: "The compressed brief did not make it through."
            ),
            transcriptSegments: [
                TranscriptSegment(id: citedSegmentID, source: .mic, startedAt: 1, endedAt: 3, text: "The compressed brief should cite this segment."),
                TranscriptSegment(id: unrelatedSegmentID, source: .system, startedAt: 4, endedAt: 7, text: "Unrelated transcript detail that should not be pasted.")
            ],
            draft: TaskPrepContextDraft(
                summary: "Spawn the agent with a compressed context packet.",
                goal: "Carry every important detail into the handoff.",
                constraints: ["Do not add extra success chrome.", "Do not paste the whole transcript by default."],
                acceptanceCriteria: ["The spawned Codex session starts with the concise brief already attached."],
                risks: ["The compressed handoff could omit useful context."],
                openQuestions: ["Should Codex ask Heed for more transcript detail later?"],
                evidence: [
                    TaskPrepEvidence(
                        id: "ev-1",
                        label: "User feedback",
                        excerpt: "The compressed brief should cite this segment.",
                        segmentIDs: [citedSegmentID]
                    )
                ],
                readyToSpawn: true
            ),
            messages: [
                TaskPrepMessage(role: .user, text: "Make sure the next agent gets the goal and limits."),
                TaskPrepMessage(role: .assistant, text: "I will keep the prompt concise and cite only relevant transcript evidence.")
            ],
            request: TaskPrepSpawnRequest(reason: "The user approved a compressed handoff.")
        )

        #expect(prompt.contains("Compressed handoff"))
        #expect(prompt.contains("Title: Fix spawn handoff"))
        #expect(prompt.contains("Type: Bug fix"))
        #expect(prompt.contains("Details: Make the spawned agent start with a concise handoff."))
        #expect(prompt.contains("Spawn reason: The user approved a compressed handoff."))
        #expect(prompt.contains("Summary: Spawn the agent with a compressed context packet."))
        #expect(prompt.contains("Goal: Carry every important detail into the handoff."))
        #expect(prompt.contains("Do not add extra success chrome."))
        #expect(prompt.contains("The spawned Codex session starts with the concise brief already attached."))
        #expect(prompt.contains("The compressed handoff could omit useful context."))
        #expect(prompt.contains("Open questions"))
        #expect(prompt.contains("Should Codex ask Heed for more transcript detail later?"))
        #expect(prompt.contains("Evidence"))
        #expect(prompt.contains("[MIC 1s-3s] The compressed brief should cite this segment."))
        #expect(prompt.contains("Prep conversation"))
        #expect(prompt.contains("User: Make sure the next agent gets the goal and limits."))
        #expect(!prompt.contains("Full transcript"))
        #expect(!prompt.contains("Unrelated transcript detail that should not be pasted."))
    }

    @Test func terminalLauncherLaunchesCodexThenPastesPromptAndRestoresClipboard() throws {
        let scripts = RecordingAppleScriptRunner()
        let pasteboard = InMemoryTaskPrepPasteboard(initialString: "original clipboard")
        let launcher = TaskPrepTerminalHandoffLauncher(
            appleScriptRunner: scripts,
            pasteboard: pasteboard
        )

        try launcher.launch(prompt: "Investigate the spawn handoff bug.")

        #expect(scripts.sources.count == 2)
        #expect(scripts.sources[0].contains("tell application \"Terminal\" to launch"))
        #expect(scripts.sources[0].contains("set launchDeadline to (current date) + 5"))
        #expect(scripts.sources[0].contains("Terminal did not finish launching."))
        #expect(scripts.sources[0].contains("repeat until application \"Terminal\" is running"))
        #expect(scripts.sources[0].contains("do script \"codex\""))
        #expect(scripts.sources[1].contains("keystroke \"v\" using command down"))
        #expect(scripts.sources[1].contains("key code 36"))
        #expect(pasteboard.string == "original clipboard")
    }

    @Test func terminalLauncherRestoresClipboardWhenPasteStepFails() {
        let scripts = RecordingAppleScriptRunner(failAtCall: 2)
        let pasteboard = InMemoryTaskPrepPasteboard(initialString: "original clipboard")
        let launcher = TaskPrepTerminalHandoffLauncher(
            appleScriptRunner: scripts,
            pasteboard: pasteboard
        )

        #expect(throws: TaskPrepAgentHandoffError.self) {
            try launcher.launch(prompt: "Investigate the spawn handoff bug.")
        }
        #expect(pasteboard.string == "original clipboard")
    }
}

@MainActor
private final class RecordingAppleScriptRunner: AppleScriptRunning {
    private let failAtCall: Int?
    private(set) var sources: [String] = []

    init(failAtCall: Int? = nil) {
        self.failAtCall = failAtCall
    }

    func run(source: String) throws {
        sources.append(source)

        if failAtCall == sources.count {
            throw TaskPrepAgentHandoffError.launchFailed("Injected launcher failure.")
        }
    }
}

@MainActor
private final class InMemoryTaskPrepPasteboard: TaskPrepPasteboardAccessing {
    private(set) var string: String?

    init(initialString: String?) {
        string = initialString
    }

    func readString() -> String? {
        string
    }

    func writeString(_ value: String?) {
        string = value
    }
}
