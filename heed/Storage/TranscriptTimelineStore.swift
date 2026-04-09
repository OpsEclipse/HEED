import Foundation

struct TranscriptTimelineStore: Sendable {
    private struct TimedSegment: Sendable {
        let insertionIndex: Int
        let segment: TranscriptSegment
    }

    private var items: [TimedSegment] = []
    private var nextInsertionIndex = 0

    var orderedSegments: [TranscriptSegment] {
        items
            .sorted { lhs, rhs in
                if lhs.segment.startedAt != rhs.segment.startedAt {
                    return lhs.segment.startedAt < rhs.segment.startedAt
                }

                if lhs.segment.source != rhs.segment.source {
                    return lhs.segment.source.label < rhs.segment.source.label
                }

                return lhs.insertionIndex < rhs.insertionIndex
            }
            .map(\.segment)
    }

    mutating func replaceAll(with segments: [TranscriptSegment]) {
        items = []
        nextInsertionIndex = 0
        append(segments)
    }

    mutating func append(_ segments: [TranscriptSegment]) {
        for segment in segments {
            items.append(TimedSegment(insertionIndex: nextInsertionIndex, segment: segment))
            nextInsertionIndex += 1
        }
    }

    mutating func reset() {
        items = []
        nextInsertionIndex = 0
    }
}
