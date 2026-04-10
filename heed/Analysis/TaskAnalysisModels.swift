import Foundation

enum TaskType: String, Codable, CaseIterable, Sendable {
    case feature = "Feature"
    case bug = "Bug"
    case followUp = "Follow-up"
    case decision = "Decision"
}

struct TaskAnalysisResult: Codable, Equatable, Sendable {
    var summary: String
    var tasks: [CompiledTask]
    var decisions: [CompiledNote]
    var followUps: [CompiledNote]
    var noTasksReason: String?
    var warnings: [String] = []
}

struct CompiledTask: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let details: String
    let type: TaskType
    let assigneeHint: String?
    let evidenceSegmentIDs: [UUID]
    let evidenceExcerpt: String
}

struct CompiledNote: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let details: String
    let evidenceSegmentIDs: [UUID]
    let evidenceExcerpt: String
}

typealias TaskAnalysisItemType = TaskType
typealias CompiledContextNote = CompiledNote
