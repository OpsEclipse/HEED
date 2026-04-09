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
}
