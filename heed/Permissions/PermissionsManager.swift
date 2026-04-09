import AVFoundation
import CoreGraphics
import Foundation

enum PermissionState: String, Sendable {
    case unknown
    case granted
    case denied
}

struct PermissionSnapshot: Equatable, Sendable {
    var microphone: PermissionState
    var screenCapture: PermissionState

    static let unknown = PermissionSnapshot(microphone: .unknown, screenCapture: .unknown)

    var canRecord: Bool {
        microphone == .granted && screenCapture == .granted
    }

    var guidanceText: String {
        if canRecord {
            return "Microphone and screen capture are ready."
        }

        if microphone == .denied && screenCapture == .denied {
            return "Turn on microphone and screen capture in System Settings, then reopen Heed."
        }

        if microphone == .denied {
            return "Turn on microphone access in System Settings, then reopen Heed."
        }

        if screenCapture == .denied {
            return "Turn on screen recording in System Settings, then reopen Heed."
        }

        return "Heed asks for access only when you press Record."
    }
}

struct PermissionsManager {
    func refresh() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphoneState(),
            screenCapture: screenCaptureState()
        )
    }

    func requestIfNeeded() async -> PermissionSnapshot {
        let current = refresh()
        guard !current.canRecord else {
            return current
        }

        if current.microphone != .granted {
            _ = await requestMicrophoneAccess()
        }

        if current.screenCapture != .granted {
            _ = CGRequestScreenCaptureAccess()
        }

        return refresh()
    }

    private func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    private func screenCaptureState() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
