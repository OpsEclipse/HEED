import Foundation

enum TranscriptSessionStatus: String, Codable, CaseIterable, Sendable {
    case recording
    case completed
    case recovered
}

struct TranscriptSession: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval
    var status: TranscriptSessionStatus
    let modelName: String
    let appVersion: String
    var segments: [TranscriptSegment]

    nonisolated init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        duration: TimeInterval = 0,
        status: TranscriptSessionStatus,
        modelName: String,
        appVersion: String,
        segments: [TranscriptSegment] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.status = status
        self.modelName = modelName
        self.appVersion = appVersion
        self.segments = segments
    }
}
