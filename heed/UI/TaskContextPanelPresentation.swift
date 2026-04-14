import Foundation

struct TaskContextPanelPresentation: Equatable {
    struct Section: Equatable, Identifiable {
        let id: String
        let title: String
        let lines: [String]
    }

    struct Footer: Equatable {
        let primaryActionTitle: String
        let isPrimaryActionEnabled: Bool
        let secondaryActionTitle: String?
        let isSecondaryActionEnabled: Bool
    }

    let panelTitle: String
    let taskTitle: String?
    let statusText: String?
    let sections: [Section]
    let footer: Footer

    init(state: TaskContextPanelState) {
        panelTitle = "Task context"

        switch state {
        case .idle:
            taskTitle = nil
            statusText = "Select a task to prepare context."
            sections = []
            footer = Footer(
                primaryActionTitle: "Spawn agent",
                isPrimaryActionEnabled: false,
                secondaryActionTitle: nil,
                isSecondaryActionEnabled: false
            )
        case .loading(let task):
            taskTitle = task.title
            statusText = "Preparing context"
            sections = []
            footer = Footer(
                primaryActionTitle: "Spawn agent",
                isPrimaryActionEnabled: false,
                secondaryActionTitle: nil,
                isSecondaryActionEnabled: false
            )
        case .loaded(let content):
            taskTitle = content.task.title
            statusText = nil
            sections = [
                .init(id: "goal", title: "Goal", lines: [content.goal]),
                .init(id: "why-it-matters", title: "Why it matters", lines: [content.whyItMatters]),
                .init(id: "implementation-notes", title: "Implementation notes", lines: content.implementationNotes),
                .init(id: "acceptance-criteria", title: "Acceptance criteria", lines: content.acceptanceCriteria),
                .init(id: "risks", title: "Risks", lines: content.risks),
                .init(id: "suggested-skills", title: "Suggested skills", lines: content.suggestedSkills),
                .init(
                    id: "evidence",
                    title: "Evidence",
                    lines: content.evidence.map { "\($0.label): \($0.excerpt)" }
                )
            ]
            .filter { !$0.lines.isEmpty }
            footer = Footer(
                primaryActionTitle: "Spawn agent",
                isPrimaryActionEnabled: true,
                secondaryActionTitle: nil,
                isSecondaryActionEnabled: false
            )
        case .failed(let task, let message):
            taskTitle = task.title
            statusText = message
            sections = []
            footer = Footer(
                primaryActionTitle: "Spawn agent",
                isPrimaryActionEnabled: false,
                secondaryActionTitle: "Retry",
                isSecondaryActionEnabled: true
            )
        }
    }
}
