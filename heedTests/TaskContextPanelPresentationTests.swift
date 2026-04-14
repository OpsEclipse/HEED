import Foundation
import Testing
@testable import heed

struct TaskContextPanelPresentationTests {
    @Test func idlePresentationShowsPromptAndDisabledSpawnArea() {
        let presentation = TaskContextPanelPresentation(state: .idle)

        #expect(presentation.panelTitle == "Task context")
        #expect(presentation.statusText == "Select a task to prepare context.")
        #expect(presentation.taskTitle == nil)
        #expect(presentation.sections.isEmpty)
        #expect(presentation.footer.primaryActionTitle == "Spawn agent")
        #expect(presentation.footer.isPrimaryActionEnabled == false)
        #expect(presentation.footer.secondaryActionTitle == nil)
    }

    @Test func loadedPresentationShowsAllRequiredSections() {
        let task = CompiledTask(
            id: "task-one",
            title: "Prepare the follow-up plan",
            details: "Use the right-side panel to build task context.",
            type: .feature,
            assigneeHint: "Product engineer",
            evidenceSegmentIDs: [],
            evidenceExcerpt: "The side panel should stay visible."
        )

        let presentation = TaskContextPanelPresentation(
            state: .loaded(
                TaskContextPanelContent(
                    task: task,
                    goal: "Make task context readable before the agent is spawned.",
                    whyItMatters: "The user needs enough detail to trust the next step.",
                    implementationNotes: [
                        "Keep the transcript visible while the context panel is open.",
                        "Keep the controller in memory only for this pass."
                    ],
                    acceptanceCriteria: [
                        "The panel opens for one selected task.",
                        "The panel can show a final Spawn agent button area."
                    ],
                    risks: [
                        "The panel could crowd the transcript if it becomes too tall."
                    ],
                    suggestedSkills: [
                        "SwiftUI",
                        "Task cancellation",
                        "Structured output"
                    ],
                    evidence: [
                        TaskContextEvidence(
                            id: "evidence-1",
                            label: "Transcript evidence",
                            excerpt: "The side panel should stay visible.",
                            segmentIDs: []
                        )
                    ]
                )
            )
        )

        #expect(presentation.taskTitle == "Prepare the follow-up plan")
        #expect(presentation.statusText == nil)
        #expect(presentation.sections.map(\.title) == [
            "Goal",
            "Why it matters",
            "Implementation notes",
            "Acceptance criteria",
            "Risks",
            "Suggested skills",
            "Evidence"
        ])
        #expect(presentation.footer.primaryActionTitle == "Spawn agent")
        #expect(presentation.footer.isPrimaryActionEnabled == true)
        #expect(presentation.footer.secondaryActionTitle == nil)
    }

    @Test func failedPresentationShowsErrorAndRetryAction() {
        let task = CompiledTask(
            id: "task-one",
            title: "Prepare the follow-up plan",
            details: "Use the right-side panel to build task context.",
            type: .feature,
            assigneeHint: "Product engineer",
            evidenceSegmentIDs: [],
            evidenceExcerpt: "The side panel should stay visible."
        )

        let presentation = TaskContextPanelPresentation(
            state: .failed(task: task, message: "Could not prepare task context")
        )

        #expect(presentation.taskTitle == "Prepare the follow-up plan")
        #expect(presentation.statusText == "Could not prepare task context")
        #expect(presentation.sections.isEmpty)
        #expect(presentation.footer.primaryActionTitle == "Spawn agent")
        #expect(presentation.footer.isPrimaryActionEnabled == false)
        #expect(presentation.footer.secondaryActionTitle == "Retry")
        #expect(presentation.footer.isSecondaryActionEnabled == true)
    }
}
