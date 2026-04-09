import Foundation

actor WhisperWorker {
    private let source: AudioSource
    private let client: WhisperProcessClient
    private var lastPublishedEnd: TimeInterval = 0
    private var lastPublishedTail = ""

    init(source: AudioSource, helperURL: URL, modelURL: URL) {
        self.source = source
        self.client = WhisperProcessClient(helperURL: helperURL, modelURL: modelURL)
    }

    func start() async throws {
        try await client.start()
    }

    func transcribe(chunk: AudioChunk) async throws -> [TranscriptSegment] {
        let rawSegments = try await client.transcribe(frames: chunk.frames)
        var output: [TranscriptSegment] = []

        for (index, rawSegment) in rawSegments.enumerated() {
            let startedAt = chunk.startedAt + (Double(rawSegment.startTimeMs) / 1_000)
            let endedAt = chunk.startedAt + (Double(rawSegment.endTimeMs) / 1_000)

            guard endedAt > lastPublishedEnd - 0.05 else {
                continue
            }

            var text = rawSegment.text.heedCollapsedWhitespace
            if index == 0 {
                text = text.trimmingSharedPrefix(with: lastPublishedTail)
            }

            guard !text.isEmpty else {
                continue
            }

            output.append(
                TranscriptSegment(
                    source: source,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    text: text
                )
            )

            lastPublishedEnd = max(lastPublishedEnd, endedAt)
            lastPublishedTail = text.suffix(160).description
        }

        return output
    }

    func stop() async {
        await client.stop()
    }
}
