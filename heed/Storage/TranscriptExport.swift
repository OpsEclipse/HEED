import Foundation

enum TranscriptExportFormat: String, CaseIterable, Sendable {
    case text
    case markdown

    var fileExtension: String {
        switch self {
        case .text:
            return "txt"
        case .markdown:
            return "md"
        }
    }
}

enum TranscriptExport {
    nonisolated static func plainText(from session: TranscriptSession) -> String {
        session.segments
            .sorted(by: timelineSort)
            .map { "[\(timestamp(for: $0.startedAt))] \($0.source.label): \($0.text)" }
            .joined(separator: "\n")
    }

    nonisolated static func markdown(from session: TranscriptSession) -> String {
        let header = [
            "# Heed Transcript",
            "",
            "- Session ID: \(session.id.uuidString)",
            "- Started: \(dateFormatter().string(from: session.startedAt))",
            "- Status: \(session.status.rawValue)",
            "- Model: \(session.modelName)",
            "",
        ].joined(separator: "\n")

        let body = session.segments
            .sorted(by: timelineSort)
            .map { "- **\(timestamp(for: $0.startedAt))** `\($0.source.label)` \($0.text)" }
            .joined(separator: "\n")

        return "\(header)\n\(body)\n"
    }

    private nonisolated static func timestamp(for interval: TimeInterval) -> String {
        let totalSeconds = Int(interval.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private nonisolated static func timelineSort(_ lhs: TranscriptSegment, _ rhs: TranscriptSegment) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }

        if lhs.source != rhs.source {
            return lhs.source.label < rhs.source.label
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func dateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
