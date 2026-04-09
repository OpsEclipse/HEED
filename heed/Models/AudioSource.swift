import Foundation

enum AudioSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case mic
    case system

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .mic:
            return "MIC"
        case .system:
            return "SYSTEM"
        }
    }
}
