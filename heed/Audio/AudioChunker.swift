import Foundation

struct AudioChunker: Sendable {
    static let sampleRate = 16_000
    static let windowFrames = 80_000
    static let stepFrames = 64_000
    static let overlapFrames = 16_000

    private let source: AudioSource
    private var buffer: [Float] = []
    private var bufferStartFrame = 0
    private var nextChunkStartFrame = 0
    private var lastFlushStartFrame: Int?

    nonisolated init(source: AudioSource) {
        self.source = source
    }

    nonisolated mutating func append(_ frames: [Float]) -> [AudioChunk] {
        guard !frames.isEmpty else {
            return []
        }

        buffer.append(contentsOf: frames)
        let chunks = makeReadyChunks()
        trimBufferIfNeeded()
        return chunks
    }

    nonisolated mutating func flush() -> [AudioChunk] {
        let bufferEndFrame = bufferStartFrame + buffer.count
        guard bufferEndFrame > nextChunkStartFrame else {
            return []
        }

        let preferredStartFrame = max(0, bufferEndFrame - Self.windowFrames)
        let finalStartFrame = max(nextChunkStartFrame, preferredStartFrame)

        guard lastFlushStartFrame != finalStartFrame else {
            return []
        }

        let localStart = finalStartFrame - bufferStartFrame
        guard localStart >= 0, localStart < buffer.count else {
            return []
        }

        let frames = Array(buffer[localStart..<buffer.count])
        lastFlushStartFrame = finalStartFrame

        return [
            AudioChunk(
                source: source,
                startedAt: TimeInterval(finalStartFrame) / TimeInterval(Self.sampleRate),
                frames: frames
            ),
        ]
    }

    private mutating func makeReadyChunks() -> [AudioChunk] {
        var chunks: [AudioChunk] = []
        let bufferEndFrame = bufferStartFrame + buffer.count

        while nextChunkStartFrame + Self.windowFrames <= bufferEndFrame {
            let localStart = nextChunkStartFrame - bufferStartFrame
            let localEnd = localStart + Self.windowFrames
            let frames = Array(buffer[localStart..<localEnd])

            chunks.append(
                AudioChunk(
                    source: source,
                    startedAt: TimeInterval(nextChunkStartFrame) / TimeInterval(Self.sampleRate),
                    frames: frames
                )
            )

            nextChunkStartFrame += Self.stepFrames
        }

        return chunks
    }

    private mutating func trimBufferIfNeeded() {
        let keepFromFrame = max(0, nextChunkStartFrame - Self.overlapFrames)
        let framesToDrop = keepFromFrame - bufferStartFrame

        guard framesToDrop > 0 else {
            return
        }

        buffer.removeFirst(framesToDrop)
        bufferStartFrame = keepFromFrame
    }
}
