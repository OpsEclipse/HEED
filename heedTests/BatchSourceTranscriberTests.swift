import Foundation
import Testing
@testable import heed

struct BatchSourceTranscriberTests {
    @Test func sourceRecordingFileWriterIgnoresEmptyWrites() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("pcm")
        let writer = SourceRecordingFileWriter(fileURL: fileURL)

        try writer.write(frames: [])
        try writer.finish()

        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test func sourceRecordingFileWriterAppendsFramesInOrder() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("pcm")
        let writer = SourceRecordingFileWriter(fileURL: fileURL)

        try writer.write(frames: [0.25, -0.5])
        try writer.write(frames: [0, 1.0])
        try writer.close()

        let data = try Data(contentsOf: fileURL)
        let samples = readPCM16Samples(from: data)

        #expect(samples == [8_191, -16_383, 0, 32_767])
    }

    @Test func batchSourceTranscriberProducesSegmentsAfterStopFromSavedPCM() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("pcm")
        let writer = SourceRecordingFileWriter(fileURL: fileURL)

        let settings = AudioEnergyGate.settings(for: .mic)
        let speechFrames = Array(repeating: Float(0.08), count: AudioChunker.analysisWindowFrames * 8)
        let silenceFrames = Array(
            repeating: Float(0),
            count: AudioChunker.analysisWindowFrames * (settings.holdWindowCount + 1)
        )

        try writer.write(frames: speechFrames)
        try writer.write(frames: silenceFrames)
        try writer.finish()

        let worker = BatchWorkerSpy(
            responses: [
                TranscriptSegment(source: .system, startedAt: 10, endedAt: 11, text: "Saved speech came back.")
            ]
        )
        let transcriber = BatchSourceTranscriber(source: .mic, worker: worker, framesPerRead: 3_200)

        let segments = try await transcriber.transcribe(from: fileURL)

        #expect(await worker.startCount == 1)
        #expect(await worker.transcribedChunkCount > 0)
        #expect(await worker.stopCount == 1)
        #expect(segments.count == 1)
        #expect(segments[0].source == .mic)
        #expect(segments[0].text == "Saved speech came back.")
        #expect(segments[0].startedAt == 10)
        #expect(segments[0].endedAt == 11)
    }

    @Test func batchSourceTranscriberFallsBackWhenSpeechGateEmitsNoChunks() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("pcm")
        let writer = SourceRecordingFileWriter(fileURL: fileURL)
        let quietFrames = Array(repeating: Float(0.001), count: AudioChunker.sampleRate * 2)

        try writer.write(frames: quietFrames)
        try writer.finish()

        let worker = BatchWorkerSpy(
            responses: [
                TranscriptSegment(source: .mic, startedAt: 0, endedAt: 1.5, text: "Quiet speech was still sent.")
            ]
        )
        let transcriber = BatchSourceTranscriber(source: .mic, worker: worker, framesPerRead: 3_200)

        let segments = try await transcriber.transcribe(from: fileURL)

        #expect(await worker.startCount == 1)
        #expect(await worker.transcribedChunkCount == 1)
        #expect(await worker.stopCount == 1)
        #expect(segments.map(\.text) == ["Quiet speech was still sent."])
    }

    @Test func batchSourceTranscriberDoesNotFallbackForQuietSystemAudio() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("pcm")
        let writer = SourceRecordingFileWriter(fileURL: fileURL)
        let quietFrames = Array(repeating: Float(0.001), count: AudioChunker.sampleRate * 2)

        try writer.write(frames: quietFrames)
        try writer.finish()

        let worker = BatchWorkerSpy(
            responses: [
                TranscriptSegment(source: .system, startedAt: 0, endedAt: 1.5, text: "you")
            ]
        )
        let transcriber = BatchSourceTranscriber(source: .system, worker: worker, framesPerRead: 3_200)

        let segments = try await transcriber.transcribe(from: fileURL)

        #expect(await worker.startCount == 1)
        #expect(await worker.transcribedChunkCount == 0)
        #expect(await worker.stopCount == 1)
        #expect(segments.isEmpty)
    }
}

private func readPCM16Samples(from data: Data) -> [Int16] {
    let usableCount = data.count - (data.count % MemoryLayout<Int16>.stride)
    guard usableCount > 0 else {
        return []
    }

    var samples: [Int16] = []
    samples.reserveCapacity(usableCount / MemoryLayout<Int16>.stride)

    data.prefix(usableCount).withUnsafeBytes { rawBuffer in
        for offset in stride(from: 0, to: usableCount, by: MemoryLayout<Int16>.stride) {
            let rawSample = rawBuffer.loadUnaligned(fromByteOffset: offset, as: Int16.self)
            samples.append(Int16(littleEndian: rawSample))
        }
    }

    return samples
}

private actor BatchWorkerSpy: BatchSourceTranscribingWorker {
    private let responses: [TranscriptSegment]
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var transcribedChunkCount = 0

    init(responses: [TranscriptSegment]) {
        self.responses = responses
    }

    func start() async throws {
        startCount += 1
    }

    func transcribe(
        chunk: AudioChunk,
        responseTimeout: Duration
    ) async throws -> [TranscriptSegment] {
        transcribedChunkCount += 1
        return responses
    }

    func stop() async {
        stopCount += 1
    }
}
