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
}
