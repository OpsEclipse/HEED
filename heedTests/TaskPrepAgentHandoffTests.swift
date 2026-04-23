import Foundation
import Testing
@testable import heed

@MainActor
struct TaskPrepAgentHandoffTests {
    @Test func promptBuilderIncludesOpenQuestionsAndFullTranscriptContext() {
        let prompt = TaskPrepAgentHandoffPromptBuilder.buildPrompt(
            task: CompiledTask(
                id: "task-1",
                title: "Fix spawn handoff",
                details: "Make the spawned agent start with the full brief.",
                type: .bugFix,
                assigneeHint: "Codex",
                evidenceSegmentIDs: [],
                evidenceExcerpt: "The full brief did not make it through."
            ),
            transcriptSegments: [
                TranscriptSegment(source: .mic, startedAt: 1, endedAt: 3, text: "The full brief did not work."),
                TranscriptSegment(source: .system, startedAt: 4, endedAt: 7, text: "Open Terminal and start Codex end-to-end.")
            ],
            draft: TaskPrepContextDraft(
                summary: "Spawn the agent with the whole context packet.",
                goal: "Carry every important detail into the handoff.",
                constraints: ["Do not add extra success chrome."],
                acceptanceCriteria: ["The spawned Codex session starts with the brief already attached."],
                risks: ["Terminal automation can fail if macOS blocks it."],
                openQuestions: ["Should we include the full transcript or only the cited excerpts?"],
                evidence: [
                    TaskPrepEvidence(
                        id: "ev-1",
                        label: "User feedback",
                        excerpt: "The full brief did not work.",
                        segmentIDs: []
                    )
                ],
                readyToSpawn: true
            ),
            messages: [
                TaskPrepMessage(role: .user, text: "Make sure the full brief reaches the next agent."),
                TaskPrepMessage(role: .assistant, text: "I will include the extra transcript context.")
            ],
            request: TaskPrepSpawnRequest(reason: "The user approved the full handoff.")
        )

        #expect(prompt.contains("Open questions"))
        #expect(prompt.contains("Should we include the full transcript or only the cited excerpts?"))
        #expect(prompt.contains("Full transcript"))
        #expect(prompt.contains("[MIC 1s-3s] The full brief did not work."))
        #expect(prompt.contains("[SYSTEM 4s-7s] Open Terminal and start Codex end-to-end."))
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
