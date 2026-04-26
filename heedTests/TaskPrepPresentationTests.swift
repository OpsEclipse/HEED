import Foundation
import AppKit
import Testing
@testable import heed

@MainActor
struct TaskPrepPresentationTests {
    @Test func contextBriefHidesOpenQuestionsFromVisibleSections() {
        let controller = TaskPrepController(service: TaskPrepPresentationServiceStub())
        controller.start(task: samplePresentationTask(), in: samplePresentationSession())

        let panel = TaskPrepContextPanelView(
            controller: controller,
            onClose: {}
        )

        let titles = panel.visibleSectionTitles(
            for: TaskPrepContextDraft(
                summary: "Stable summary",
                goal: "Keep only settled context in the brief.",
                constraints: ["Keep the chat visible."],
                acceptanceCriteria: ["Open questions stay in chat only."],
                risks: ["Questions could leak into the panel."],
                openQuestions: ["Should the assistant ask this in chat?"],
                evidence: [],
                readyToSpawn: false
            )
        )

        #expect(titles.contains("Summary"))
        #expect(titles.contains("Goal"))
        #expect(titles.contains("Open questions") == false)
    }

    @Test func assistantMessagesUseFlatChrome() {
        let bubble = TaskPrepMessageBubble(
            message: TaskPrepMessage(role: .assistant, text: "What should the retry button do?")
        )

        #expect(bubble.usesFlatChrome == true)
    }

    @Test func userMessagesUseContentWidth() {
        let bubble = TaskPrepMessageBubble(
            message: TaskPrepMessage(role: .user, text: "Keep the bubble tight to the text.")
        )

        #expect(bubble.usesContentWidth == true)
    }

    @Test func latestStreamingAssistantMessageShowsLoadingIndicator() {
        let bubble = TaskPrepMessageBubble(
            message: TaskPrepMessage(role: .assistant, text: "Drafting the handoff"),
            isLatestStreamingAssistant: true
        )

        #expect(bubble.showsLoadingIndicator == true)
    }

    @Test func workspaceShowsTerminalAfterSpawnLaunches() {
        let controller = TaskPrepController(service: TaskPrepPresentationServiceStub())
        controller.start(task: samplePresentationTask(), in: samplePresentationSession())

        let workspace = TaskPrepWorkspaceView(
            controller: controller,
            onClose: {}
        )

        #expect(workspace.shouldShowTerminal(for: .idle) == false)
        #expect(workspace.shouldShowTerminal(for: .running) == true)
        #expect(workspace.shouldShowTerminal(for: .failed("codex was not found.")) == true)
    }

    @Test func terminalKeyMapperSendsDirectTerminalControls() {
        #expect(TerminalKeyMapper.input(characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36, modifierFlags: []) == "\r")
        #expect(TerminalKeyMapper.input(characters: nil, charactersIgnoringModifiers: nil, keyCode: 123, modifierFlags: []) == "\u{1B}[D")
        #expect(TerminalKeyMapper.input(characters: nil, charactersIgnoringModifiers: nil, keyCode: 124, modifierFlags: []) == "\u{1B}[C")
        #expect(TerminalKeyMapper.input(characters: nil, charactersIgnoringModifiers: nil, keyCode: 125, modifierFlags: []) == "\u{1B}[B")
        #expect(TerminalKeyMapper.input(characters: nil, charactersIgnoringModifiers: nil, keyCode: 126, modifierFlags: []) == "\u{1B}[A")
        #expect(TerminalKeyMapper.input(characters: "c", charactersIgnoringModifiers: "c", keyCode: 8, modifierFlags: [.control]) == "\u{3}")
    }

    @Test func terminalCanvasKeepsReadableTextWidth() {
        #expect(TerminalCanvasLayout.textContainerWidth(for: 0) == 288)
        #expect(TerminalCanvasLayout.textContainerWidth(for: 640) == 608)
    }
}

private struct TaskPrepPresentationServiceStub: TaskPrepConversationServicing {
    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        AsyncThrowingStream { _ in }
    }
}

private func samplePresentationSession() -> TranscriptSession {
    TranscriptSession(
        startedAt: Date(timeIntervalSince1970: 0),
        endedAt: Date(timeIntervalSince1970: 12),
        duration: 12,
        status: .completed,
        modelName: "ggml-base.en",
        appVersion: "1.0",
        segments: [
            TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2, text: "We should keep the chat visible."),
            TranscriptSegment(source: .system, startedAt: 3, endedAt: 4, text: "Questions belong in the conversation."),
        ]
    )
}

private func samplePresentationTask() -> CompiledTask {
    CompiledTask(
        id: "task-presentation",
        title: "Polish task prep presentation",
        details: "Keep unsettled questions in chat.",
        type: .feature,
        assigneeHint: "Mac engineer",
        evidenceSegmentIDs: [],
        evidenceExcerpt: "Questions belong in the conversation."
    )
}
