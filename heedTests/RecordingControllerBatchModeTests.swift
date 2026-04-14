import Foundation
import Testing
@testable import heed

struct RecordingControllerBatchModeTests {
    @Test func demoModeDoesNotPublishTranscriptWhileRecording() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = SessionStore(baseDirectoryURL: rootURL)
        let controller = await MainActor.run {
            RecordingController(demoMode: true, sessionStore: store)
        }

        await MainActor.run {
            controller.handlePrimaryAction()
        }

        try await waitForRecordingState(.recording, controller: controller)
        try await Task.sleep(for: .milliseconds(1500))

        let liveSegments = await MainActor.run { controller.liveSegments }
        let activeSegments = await MainActor.run { controller.activeSession?.segments ?? [] }

        #expect(liveSegments.isEmpty)
        #expect(activeSegments.isEmpty)

        try? await Task.sleep(for: .milliseconds(50))
        try? FileManager.default.removeItem(at: rootURL)
    }

    @Test func demoModeStopEntersProcessingAndProducesSplitTranscript() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = SessionStore(baseDirectoryURL: rootURL)
        let controller = await MainActor.run {
            RecordingController(demoMode: true, sessionStore: store)
        }

        await MainActor.run {
            controller.handlePrimaryAction()
        }

        try await waitForRecordingState(.recording, controller: controller)

        await MainActor.run {
            controller.handlePrimaryAction()
        }

        try await waitForRecordingState(.processing, controller: controller)
        try await waitForRecordingState(.ready, controller: controller)

        let selectedSession = await MainActor.run { controller.selectedSession }
        let session = try #require(selectedSession)

        #expect(!session.micSegments.isEmpty)
        #expect(!session.systemSegments.isEmpty)
        #expect(session.segments.count == session.micSegments.count + session.systemSegments.count)

        try? await Task.sleep(for: .milliseconds(50))
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func waitForRecordingState(
    _ expectedState: RecordingState,
    controller: RecordingController,
    attempts: Int = 60
) async throws {
    for _ in 0..<attempts {
        let currentState = await MainActor.run { controller.state }
        if currentState == expectedState {
            return
        }

        try await Task.sleep(for: .milliseconds(50))
    }

    #expect(await MainActor.run { controller.state } == expectedState)
}
