import Foundation

extension String {
    nonisolated var heedCollapsedWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    nonisolated func trimmingSharedPrefix(with previousTail: String) -> String {
        let candidate = heedCollapsedWhitespace
        let previous = previousTail.heedCollapsedWhitespace

        guard !candidate.isEmpty, !previous.isEmpty else {
            return candidate
        }

        let candidateWords = candidate.split(separator: " ")
        let previousWords = previous.split(separator: " ")
        let overlapLimit = Swift.min(candidateWords.count, previousWords.count, 12)

        guard overlapLimit > 0 else {
            return candidate
        }

        for overlapCount in stride(from: overlapLimit, through: 1, by: -1) {
            let prefix = candidateWords.prefix(overlapCount)
            let suffix = previousWords.suffix(overlapCount)
            if Array(prefix) == Array(suffix) {
                let trimmedWords = candidateWords.dropFirst(overlapCount)
                return trimmedWords.joined(separator: " ")
            }
        }

        return candidate
    }
}
