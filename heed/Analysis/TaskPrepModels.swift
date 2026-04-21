import Foundation

enum TaskPrepMessageRole: Equatable, Sendable {
    case user
    case assistant
    case system
}

struct TaskPrepMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: TaskPrepMessageRole
    var text: String
    var isInterrupted: Bool

    nonisolated init(
        id: UUID = UUID(),
        role: TaskPrepMessageRole,
        text: String,
        isInterrupted: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isInterrupted = isInterrupted
    }
}

struct TaskPrepContextDraft: Equatable, Sendable {
    var summary: String = ""
    var goal: String = ""
    var constraints: [String] = []
    var acceptanceCriteria: [String] = []
    var risks: [String] = []
    var openQuestions: [String] = []
    var evidence: [TaskPrepEvidence] = []
    var readyToSpawn: Bool = false
}

struct TaskPrepEvidence: Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let excerpt: String
    let segmentIDs: [UUID]
}

struct TaskPrepTranscriptRequest: Equatable, Sendable {
    let scope: String
}

struct TaskPrepSpawnRequest: Equatable, Sendable {
    let reason: String
}

enum TaskPrepConversationEvent: Equatable, Sendable {
    case assistantTextDelta(String)
    case contextDraft(TaskPrepContextDraft)
    case transcriptToolRequest(TaskPrepTranscriptRequest)
    case spawnAgentRequest(TaskPrepSpawnRequest)
    case completed
}

struct TaskPrepTurnInput: Equatable, Sendable {
    let task: CompiledTask
    let session: TranscriptSession
}

enum TaskPrepTurnState: Equatable, Sendable {
    case idle
    case streaming
    case failed(String)
    case completed
}

struct TaskPrepViewState: Equatable, Sendable {
    var messages: [TaskPrepMessage] = []
    var turnState: TaskPrepTurnState = .idle
}
