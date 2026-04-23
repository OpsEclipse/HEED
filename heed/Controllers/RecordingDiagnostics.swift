import Foundation
import OSLog

enum RecordingDiagnosticEvent: Equatable {
    case recordingRequested
    case permissionsResolved(microphone: PermissionState, screenCapture: PermissionState)
    case microphoneStartBegan
    case microphoneStartSucceeded
    case microphoneStartFailed(String)
    case systemAudioStartBegan
    case systemAudioStartSucceeded
    case systemAudioStartFailed(String)
    case recordingStarted(activeSources: [String])
    case sourceFailed(AudioSource, String)
}

struct RecordingControllerDependencies {
    var refreshPermissions: () -> PermissionSnapshot
    var requestPermissionsIfNeeded: () async -> PermissionSnapshot
    var makeMicCaptureManager: () -> any MicCaptureManaging
    var makeSystemAudioCaptureManager: () -> any SystemAudioCaptureManaging
    var diagnosticSink: (RecordingDiagnosticEvent) -> Void

    static func live() -> Self {
        let permissionsManager = PermissionsManager()
        return Self(
            refreshPermissions: { permissionsManager.refresh() },
            requestPermissionsIfNeeded: { await permissionsManager.requestIfNeeded() },
            makeMicCaptureManager: { MicCaptureManager() },
            makeSystemAudioCaptureManager: { SystemAudioCaptureManager() },
            diagnosticSink: RecordingDiagnostics.log
        )
    }
}

enum RecordingDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "sprsh.ca.heed",
        category: "Recording"
    )

    static func log(_ event: RecordingDiagnosticEvent) {
        switch event {
        case .recordingRequested:
            logger.notice("Recording requested.")
        case let .permissionsResolved(microphone, screenCapture):
            logger.notice("Permissions resolved. microphone=\(microphone.rawValue, privacy: .public) screenCapture=\(screenCapture.rawValue, privacy: .public)")
        case .microphoneStartBegan:
            logger.notice("Microphone capture start began.")
        case .microphoneStartSucceeded:
            logger.notice("Microphone capture started.")
        case let .microphoneStartFailed(message):
            logger.error("Microphone capture failed to start. \(message, privacy: .public)")
        case .systemAudioStartBegan:
            logger.notice("System audio capture start began.")
        case .systemAudioStartSucceeded:
            logger.notice("System audio capture started.")
        case let .systemAudioStartFailed(message):
            logger.error("System audio capture failed to start. \(message, privacy: .public)")
        case let .recordingStarted(activeSources):
            logger.notice("Recording entered active state with sources: \(activeSources.joined(separator: ", "), privacy: .public)")
        case let .sourceFailed(source, message):
            logger.error("\(source.label, privacy: .public) source failed while recording. \(message, privacy: .public)")
        }
    }
}
