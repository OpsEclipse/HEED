import Foundation

struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let source: AudioSource
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    let text: String

    nonisolated init(
        id: UUID = UUID(),
        source: AudioSource,
        startedAt: TimeInterval,
        endedAt: TimeInterval,
        text: String
    ) {
        self.id = id
        self.source = source
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.text = text
    }
}
