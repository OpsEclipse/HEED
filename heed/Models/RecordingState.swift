import Foundation

enum SourceProcessingState: String, Equatable, Sendable {
    case queued
    case processing
    case done
    case failed
}

enum RecordingState: Equatable, Sendable {
    case idle
    case requestingPermissions
    case ready
    case recording
    case stopping
    case processing
    case error(String)

    nonisolated var isBusy: Bool {
        switch self {
        case .requestingPermissions, .recording, .stopping, .processing:
            return true
        case .idle, .ready, .error:
            return false
        }
    }

    nonisolated var statusText: String {
        switch self {
        case .idle:
            return "Idle"
        case .requestingPermissions:
            return "Requesting permissions"
        case .ready:
            return "Ready to record"
        case .recording:
            return "Recording locally"
        case .stopping:
            return "Stopping and flushing"
        case .processing:
            return "Transcribing after stop"
        case .error:
            return "Blocked"
        }
    }
}
