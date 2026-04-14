import Foundation

enum TranscriptSessionStatus: String, Codable, CaseIterable, Sendable {
    case recording
    case completed
    case recovered
}

struct TranscriptSession: Codable, Equatable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case endedAt
        case duration
        case status
        case modelName
        case appVersion
        case segments
        case micSegments
        case systemSegments
    }

    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval
    var status: TranscriptSessionStatus
    let modelName: String
    let appVersion: String
    var micSegments: [TranscriptSegment]
    var systemSegments: [TranscriptSegment]

    var segments: [TranscriptSegment] {
        get {
            Self.merge(micSegments: micSegments, systemSegments: systemSegments)
        }
        set {
            let split = Self.split(newValue)
            micSegments = split.mic
            systemSegments = split.system
        }
    }

    nonisolated init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        duration: TimeInterval = 0,
        status: TranscriptSessionStatus,
        modelName: String,
        appVersion: String,
        segments: [TranscriptSegment] = [],
        micSegments: [TranscriptSegment]? = nil,
        systemSegments: [TranscriptSegment]? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.status = status
        self.modelName = modelName
        self.appVersion = appVersion

        if let micSegments, let systemSegments {
            self.micSegments = micSegments
            self.systemSegments = systemSegments
        } else {
            let split = Self.split(segments)
            self.micSegments = micSegments ?? split.mic
            self.systemSegments = systemSegments ?? split.system
        }
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        status = try container.decode(TranscriptSessionStatus.self, forKey: .status)
        modelName = try container.decode(String.self, forKey: .modelName)
        appVersion = try container.decode(String.self, forKey: .appVersion)

        let legacySegments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        let decodedMicSegments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .micSegments)
        let decodedSystemSegments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .systemSegments)

        if decodedMicSegments != nil || decodedSystemSegments != nil {
            let split = Self.split(legacySegments)
            micSegments = decodedMicSegments ?? split.mic
            systemSegments = decodedSystemSegments ?? split.system
        } else {
            let split = Self.split(legacySegments)
            micSegments = split.mic
            systemSegments = split.system
        }
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(duration, forKey: .duration)
        try container.encode(status, forKey: .status)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(micSegments, forKey: .micSegments)
        try container.encode(systemSegments, forKey: .systemSegments)
        try container.encode(segments, forKey: .segments)
    }

    private nonisolated static func split(_ segments: [TranscriptSegment]) -> (mic: [TranscriptSegment], system: [TranscriptSegment]) {
        (
            mic: segments.filter { $0.source == .mic },
            system: segments.filter { $0.source == .system }
        )
    }

    private nonisolated static func merge(
        micSegments: [TranscriptSegment],
        systemSegments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        (micSegments + systemSegments).sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt < rhs.startedAt
            }

            if lhs.source != rhs.source {
                return lhs.source.label < rhs.source.label
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
