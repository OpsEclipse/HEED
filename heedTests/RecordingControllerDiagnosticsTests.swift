import Foundation
import Testing
@testable import heed

@MainActor
struct RecordingControllerDiagnosticsTests {
    @Test func recordingControllerEmitsStartupDiagnosticsForMixedSourceStartup() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = SessionStore(baseDirectoryURL: rootURL)
        var events: [RecordingDiagnosticEvent] = []

        let controller = RecordingController(
            demoMode: false,
            sessionStore: store,
            dependencies: .init(
                refreshPermissions: {
                    PermissionSnapshot(microphone: .granted, screenCapture: .granted)
                },
                requestPermissionsIfNeeded: {
                    PermissionSnapshot(microphone: .granted, screenCapture: .granted)
                },
                makeMicCaptureManager: {
                    StubMicCaptureManager()
                },
                makeSystemAudioCaptureManager: {
                    StubSystemAudioCaptureManager(startError: StubSystemAudioCaptureManager.TestError())
                },
                diagnosticSink: { events.append($0) }
            )
        )

        controller.handlePrimaryAction()

        try await waitForRecordingState(.recording, controller: controller)

        #expect(events == [
            .recordingRequested,
            .permissionsResolved(microphone: .granted, screenCapture: .granted),
            .microphoneStartBegan,
            .microphoneStartSucceeded,
            .systemAudioStartBegan,
            .systemAudioStartFailed("Stub system audio start failure"),
            .recordingStarted(activeSources: ["MIC"])
        ])

        controller.handlePrimaryAction()
        try await Task.sleep(for: .milliseconds(100))
        try? FileManager.default.removeItem(at: rootURL)
    }
}

@MainActor
private func waitForRecordingState(
    _ expectedState: RecordingState,
    controller: RecordingController,
    attempts: Int = 60
) async throws {
    for _ in 0..<attempts {
        if controller.state == expectedState {
            return
        }

        try await Task.sleep(for: .milliseconds(50))
    }

    #expect(controller.state == expectedState)
}

private final class StubMicCaptureManager: MicCaptureManaging {
    func start(onFrames: @escaping @Sendable ([Float]) -> Void) throws {}
    func stop() {}
}

private final class StubSystemAudioCaptureManager: SystemAudioCaptureManaging {
    struct TestError: LocalizedError {
        var errorDescription: String? {
            "Stub system audio start failure"
        }
    }

    let startError: Error?

    init(startError: Error?) {
        self.startError = startError
    }

    func start(
        onFrames: @escaping @Sendable ([Float]) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) async throws {
        if let startError {
            throw startError
        }
    }

    func stop() async {}
}
