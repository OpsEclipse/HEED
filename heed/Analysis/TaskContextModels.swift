import Foundation

protocol TaskContextCompiling: Sendable {
    func prepareTaskContext(session: TranscriptSession, task: CompiledTask) async throws -> TaskContextPanelContent
}

struct TaskContextPanelContent: Equatable, Sendable {
    let task: CompiledTask
    let goal: String
    let whyItMatters: String
    let implementationNotes: [String]
    let acceptanceCriteria: [String]
    let risks: [String]
    let suggestedSkills: [String]
    let evidence: [TaskContextEvidence]
}

struct TaskContextEvidence: Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let excerpt: String
    let segmentIDs: [UUID]
}

enum TaskContextPanelState: Equatable, Sendable {
    case idle
    case loading(task: CompiledTask)
    case loaded(TaskContextPanelContent)
    case failed(task: CompiledTask, message: String)
}
