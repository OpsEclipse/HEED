import Foundation

enum TaskType: String, Codable, CaseIterable, Sendable {
    case feature = "Feature"
    case bugFix = "Bug fix"
    case miscellaneous = "Miscellaneous"
}

struct TaskAnalysisResult: Codable, Equatable, Sendable {
    var summary: String
    var tasks: [CompiledTask]
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
