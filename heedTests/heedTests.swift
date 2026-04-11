//
//  heedTests.swift
//  heedTests
//
//  Created by Sparsh Shah on 2026-04-08.
//

import Foundation
import Testing
@testable import heed

struct heedTests {
    @Test func audioSourceLabelsStayStable() {
        #expect(AudioSource.mic.label == "MIC")
        #expect(AudioSource.system.label == "SYSTEM")
    }

    @Test func timelineStoreOrdersByTimeThenSource() {
        var timeline = TranscriptTimelineStore()
        timeline.append([
            TranscriptSegment(source: .system, startedAt: 3, endedAt: 4, text: "system later"),
            TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2, text: "mic first"),
            TranscriptSegment(source: .system, startedAt: 1, endedAt: 2, text: "system same time"),
        ])

        let ordered = timeline.orderedSegments
        #expect(ordered.map(\.text) == ["mic first", "system same time", "system later"])
    }

    @Test func transcriptExportFormatsLabelsAndTimestamps() {
        let session = TranscriptSession(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 10),
            duration: 10,
            status: .completed,
            modelName: "ggml-base.en",
            appVersion: "1.0",
            segments: [
                TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2, text: "Hello there"),
                TranscriptSegment(source: .system, startedAt: 3, endedAt: 4, text: "Welcome back"),
            ]
        )

        let plainText = TranscriptExport.plainText(from: session)
        let markdown = TranscriptExport.markdown(from: session)

        #expect(plainText.contains("[00:00:01] MIC: Hello there"))
        #expect(plainText.contains("[00:00:03] SYSTEM: Welcome back"))
        #expect(markdown.contains("**00:00:01** `MIC` Hello there"))
        #expect(markdown.contains("Status: completed"))
    }

    @Test func sessionStoreRecoversIncompleteSessions() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = SessionStore(baseDirectoryURL: rootURL)

        let session = TranscriptSession(
            startedAt: Date(timeIntervalSince1970: 0),
            duration: 12,
            status: .recording,
            modelName: "ggml-base.en",
            appVersion: "1.0",
            segments: [
                TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2, text: "Recovered")
            ]
        )

        try await store.save(session: session)
        let loaded = try await store.loadSessions()

        #expect(loaded.count == 1)
        #expect(loaded[0].status == .recovered)
        #expect(loaded[0].endedAt != nil)

        try? FileManager.default.removeItem(at: rootURL)
    }

    @Test func sessionStoreDeleteRemovesSavedSession() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = SessionStore(baseDirectoryURL: rootURL)
        let session = TranscriptSession(
            startedAt: Date(timeIntervalSince1970: 0),
            duration: 1,
            status: .recording,
            modelName: "ggml-base.en",
            appVersion: "1.0"
        )

        try await store.save(session: session)
        try await store.deleteSession(id: session.id)
        let loaded = try await store.loadSessions()

        #expect(loaded.isEmpty)

        try? FileManager.default.removeItem(at: rootURL)
    }

    @Test func audioChunkerWaitsForSilenceBeforeEmitting() {
        var chunker = AudioChunker(source: .mic)
        let speechFrames = Array(repeating: Float(0.08), count: AudioChunker.analysisWindowFrames * 8)

        let chunks = chunker.append(speechFrames)

        #expect(chunks.isEmpty)
    }

    @Test func audioChunkerEmitsAfterSpeechThenSilence() {
        var chunker = AudioChunker(source: .mic)
        let settings = AudioEnergyGate.settings(for: .mic)
        let speechFrames = Array(repeating: Float(0.08), count: settings.analysisWindowFrames * 8)
        let silenceFrames = Array(
            repeating: Float(0),
            count: settings.analysisWindowFrames * (settings.holdWindowCount + 1)
        )

        _ = chunker.append(speechFrames)
        let chunks = chunker.append(silenceFrames)

        #expect(chunks.count == 1)
        #expect(chunks[0].startedAt == 0)
        #expect(chunks[0].frames.count > speechFrames.count)
    }

    @Test func audioEnergyGateSkipsSilentFramesForStartupCheck() {
        let silentFrames = Array(repeating: Float(0), count: AudioChunker.analysisWindowFrames * 12)

        #expect(AudioEnergyGate.containsSpeechLikeEnergy(silentFrames, source: .mic) == false)
    }

    @Test func audioEnergyGateAcceptsQuietMicSpeechForStartupCheck() {
        let quietSpeechFrames = Array(repeating: Float(0.022), count: AudioChunker.analysisWindowFrames * 12)

        #expect(AudioEnergyGate.containsSpeechLikeEnergy(quietSpeechFrames, source: .mic) == true)
    }

    @Test func audioChunkerEmitsQuietMicSpeechAfterSilence() {
        var chunker = AudioChunker(source: .mic)
        let settings = AudioEnergyGate.settings(for: .mic)
        let quietSpeechFrames = Array(repeating: Float(0.03), count: settings.analysisWindowFrames * 8)
        let silenceFrames = Array(
            repeating: Float(0),
            count: settings.analysisWindowFrames * (settings.holdWindowCount + 1)
        )

        _ = chunker.append(quietSpeechFrames)
        let chunks = chunker.append(silenceFrames)

        #expect(chunks.count == 1)
        #expect(chunks[0].frames.count > quietSpeechFrames.count)
    }

    @Test func audioChunkerFlushesOngoingUtteranceOnStop() {
        var chunker = AudioChunker(source: .mic)
        let speechFrames = Array(repeating: Float(0.08), count: AudioChunker.analysisWindowFrames * 10)

        _ = chunker.append(speechFrames)
        let chunks = chunker.flush()

        #expect(chunks.count == 1)
        #expect(chunks[0].frames.count >= speechFrames.count)
    }

    @Test func demoModeRecordingImmediatelyEntersRecordingState() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = SessionStore(baseDirectoryURL: rootURL)
        let controller = await MainActor.run {
            RecordingController(demoMode: true, sessionStore: store)
        }

        await MainActor.run {
            controller.handlePrimaryAction()
        }

        var recordedState: RecordingState?
        for _ in 0..<20 {
            recordedState = await MainActor.run { controller.state }
            if recordedState == .recording {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(recordedState == .recording)

        await MainActor.run {
            controller.handlePrimaryAction()
        }

        try? await Task.sleep(for: .milliseconds(50))
        try? FileManager.default.removeItem(at: rootURL)
    }

    @Test func taskAnalysisFixtureCompilerBuildsDeterministicDraftFromSession() async throws {
        let compiler = TaskAnalysisFixtureCompiler(mode: .success, delay: .milliseconds(0))
        let result = try await compiler.compile(session: demoTranscriptSession())

        #expect(result.tasks.count == 2)
        #expect(result.tasks[0].title == "Verify the two-way audio path before the next session")
        #expect(result.tasks[1].title == "Review the live source labels in the transcript")
        #expect(result.decisions.count == 1)
        #expect(result.followUps.count == 1)
        #expect(result.warnings.first == "Preview only. This build keeps task compilation local while the OpenAI-backed compile path is still in progress.")
    }

    @Test func taskAnalysisControllerOnlyShowsCompileForFinishedSessionsWithText() async throws {
        let controller = await MainActor.run {
            TaskAnalysisController(compiler: TaskAnalysisFixtureCompiler(mode: .success, delay: .milliseconds(0)))
        }

        let recordingSession = makeSession(status: .recording, texts: ["Still recording"])
        let emptyCompletedSession = makeSession(status: .completed, texts: ["   "])
        let completedSession = makeSession(status: .completed, texts: ["Review the labels"])

        await MainActor.run {
            controller.updateDisplayedSession(recordingSession)
        }
        let recordingVisibility = await MainActor.run { controller.canShowCompileAction }

        await MainActor.run {
            controller.updateDisplayedSession(emptyCompletedSession)
        }
        let emptyVisibility = await MainActor.run { controller.canShowCompileAction }

        await MainActor.run {
            controller.updateDisplayedSession(completedSession)
        }
        let completedVisibility = await MainActor.run { controller.canShowCompileAction }

        #expect(recordingVisibility == false)
        #expect(emptyVisibility == false)
        #expect(completedVisibility == true)
    }

    @Test func taskAnalysisControllerReachesCompiledNoTasksState() async throws {
        let controller = await MainActor.run {
            TaskAnalysisController(compiler: TaskAnalysisFixtureCompiler(mode: .empty, delay: .milliseconds(0)))
        }

        await MainActor.run {
            controller.updateDisplayedSession(demoTranscriptSession())
            controller.handleCompileAction()
        }

        let sectionModel = try await waitForTaskAnalysisSectionModel(controller)
        #expect(sectionModel?.result?.tasks.isEmpty == true)
        #expect(sectionModel?.result?.noTasksReason == "No clear tasks found")
        let actionTitle = await MainActor.run { controller.compileActionTitle }
        #expect(actionTitle == "Recompile")
    }

    @Test func taskAnalysisControllerSurfacesFailureStateAndRetryLabel() async throws {
        let controller = await MainActor.run {
            TaskAnalysisController(compiler: StubTaskAnalysisCompiler { _ in
                throw StubTaskAnalysisError()
            })
        }

        await MainActor.run {
            controller.updateDisplayedSession(demoTranscriptSession())
            controller.handleCompileAction()
        }

        let sectionModel = try await waitForTaskAnalysisSectionModel(controller)
        #expect(sectionModel?.errorText == "Task analysis failed on purpose.")
        let actionTitle = await MainActor.run { controller.compileActionTitle }
        #expect(actionTitle == "Try again")
    }

    @Test func taskAnalysisControllerRecordsSpawnAgentRequests() async {
        let controller = await MainActor.run {
            TaskAnalysisController()
        }

        await MainActor.run {
            controller.requestSpawnAgent(for: "verify-audio-paths")
        }

        let firstSpawnedTaskID = await MainActor.run {
            controller.lastSpawnedTaskID
        }
        #expect(firstSpawnedTaskID == "verify-audio-paths")

        await MainActor.run {
            controller.requestSpawnAgent(for: "review-source-labels")
        }

        let secondSpawnedTaskID = await MainActor.run {
            controller.lastSpawnedTaskID
        }
        #expect(secondSpawnedTaskID == "review-source-labels")
    }
}

private struct StubTaskAnalysisCompiler: TaskAnalysisCompiling {
    let operation: @Sendable (TranscriptSession) async throws -> TaskAnalysisResult

    func compile(session: TranscriptSession) async throws -> TaskAnalysisResult {
        try await operation(session)
    }
}

private struct StubTaskAnalysisError: LocalizedError {
    var errorDescription: String? {
        "Task analysis failed on purpose."
    }
}

private func waitForTaskAnalysisSectionModel(
    _ controller: TaskAnalysisController,
    attempts: Int = 20
) async throws -> TaskAnalysisController.SectionModel? {
    for _ in 0..<attempts {
        let sectionModel = await MainActor.run { controller.sectionModel }
        if sectionModel?.isCompiling != true {
            return sectionModel
        }
        try await Task.sleep(for: .milliseconds(25))
    }

    return await MainActor.run { controller.sectionModel }
}

private func demoTranscriptSession() -> TranscriptSession {
    TranscriptSession(
        startedAt: Date(timeIntervalSince1970: 0),
        endedAt: Date(timeIntervalSince1970: 10),
        duration: 10,
        status: .completed,
        modelName: "ggml-base.en",
        appVersion: "1.0",
        segments: [
            TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2.4, text: "Can you hear me clearly on this side?"),
            TranscriptSegment(source: .system, startedAt: 2, endedAt: 3.5, text: "Yes, the remote call audio is coming through."),
            TranscriptSegment(source: .mic, startedAt: 4.2, endedAt: 5.8, text: "Perfect. Heed is showing separate live labels."),
        ]
    )
}

private func makeSession(status: TranscriptSessionStatus, texts: [String]) -> TranscriptSession {
    TranscriptSession(
        startedAt: Date(timeIntervalSince1970: 0),
        endedAt: Date(timeIntervalSince1970: 12),
        duration: 12,
        status: status,
        modelName: "ggml-base.en",
        appVersion: "1.0",
        segments: texts.enumerated().map { index, text in
            TranscriptSegment(
                source: index.isMultiple(of: 2) ? .mic : .system,
                startedAt: TimeInterval(index),
                endedAt: TimeInterval(index + 1),
                text: text
            )
        }
    )
}
