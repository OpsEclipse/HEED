import Foundation

protocol BatchSourceTranscribingWorker: Sendable {
    func start() async throws
    func transcribe(
        chunk: AudioChunk,
        responseTimeout: Duration
    ) async throws -> [TranscriptSegment]
    func stop() async
}

extension WhisperWorker: BatchSourceTranscribingWorker {}

struct BatchSourceTranscriber<Worker: BatchSourceTranscribingWorker>: Sendable {
    private let source: AudioSource
    private let worker: Worker
    private let framesPerRead: Int
    private let responseTimeout: Duration

    init(
        source: AudioSource,
        worker: Worker,
        framesPerRead: Int = 4_096,
        responseTimeout: Duration = .seconds(20)
    ) {
        self.source = source
        self.worker = worker
        self.framesPerRead = max(2, framesPerRead - (framesPerRead % 2))
        self.responseTimeout = responseTimeout
    }

    func transcribe(from fileURL: URL) async throws -> [TranscriptSegment] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        var chunker = AudioChunker(source: source)
        var output: [TranscriptSegment] = []
        var didStart = false

        do {
            try await worker.start()
            didStart = true

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer {
                handle.closeFile()
            }

            while true {
                let data = handle.readData(ofLength: framesPerRead * MemoryLayout<Int16>.stride)
                guard !data.isEmpty else {
                    break
                }

                let frames = decodePCM16Frames(from: data)
                guard !frames.isEmpty else {
                    continue
                }

                try await process(
                    chunker.append(frames),
                    into: &output
                )
            }

            try await process(
                chunker.flush(),
                into: &output
            )

            await worker.stop()
            return output
        } catch {
            if didStart {
                await worker.stop()
            }
            throw error
        }
    }

    private func process(
        _ chunks: [AudioChunk],
        into output: inout [TranscriptSegment]
    ) async throws {
        for chunk in chunks {
            let segments = try await worker.transcribe(
                chunk: chunk,
                responseTimeout: responseTimeout
            )

            for segment in segments {
                output.append(
                    TranscriptSegment(
                        source: source,
                        startedAt: segment.startedAt,
                        endedAt: segment.endedAt,
                        text: segment.text
                    )
                )
            }
        }
    }

    private func decodePCM16Frames(from data: Data) -> [Float] {
        let usableCount = data.count - (data.count % MemoryLayout<Int16>.stride)
        guard usableCount > 0 else {
            return []
        }

        var frames: [Float] = []
        frames.reserveCapacity(usableCount / MemoryLayout<Int16>.stride)

        data.prefix(usableCount).withUnsafeBytes { rawBuffer in
            for offset in stride(from: 0, to: usableCount, by: MemoryLayout<Int16>.stride) {
                let rawSample = rawBuffer.loadUnaligned(fromByteOffset: offset, as: Int16.self)
                let sample = Int16(littleEndian: rawSample)
                let normalized = Float(sample) / Float(Int16.max)
                frames.append(max(-1, min(1, normalized)))
            }
        }

        return frames
    }
}
