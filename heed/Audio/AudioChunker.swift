import Foundation

struct AudioChunker: Sendable {
    static let sampleRate = 16_000
    static let analysisWindowFrames = 320

    private let source: AudioSource
    private let settings: AudioEnergyGate.SpeechSettings
    private var buffer: [Float] = []
    private var bufferStartFrame = 0
    private var streamEndFrame = 0
    private var currentWindowPeak: Float = 0
    private var currentWindowEnergy: Float = 0
    private var currentWindowFrameCount = 0
    private var utteranceStartFrame: Int?
    private var speechWindowCount = 0
    private var holdRemainingWindows = 0

    nonisolated init(source: AudioSource) {
        self.source = source
        self.settings = AudioEnergyGate.settings(for: source)
    }

    nonisolated mutating func append(_ frames: [Float]) -> [AudioChunk] {
        guard !frames.isEmpty else {
            return []
        }

        buffer.append(contentsOf: frames)

        var emittedChunks: [AudioChunk] = []

        for frame in frames {
            streamEndFrame += 1
            let magnitude = abs(frame)
            currentWindowPeak = max(currentWindowPeak, magnitude)
            currentWindowEnergy += frame * frame
            currentWindowFrameCount += 1

            if currentWindowFrameCount == settings.analysisWindowFrames,
               let chunk = finalizeWindow(endingAt: streamEndFrame) {
                emittedChunks.append(chunk)
            }
        }

        trimBufferIfNeeded()
        return emittedChunks
    }

    nonisolated mutating func flush() -> [AudioChunk] {
        defer {
            resetUtteranceState()
            trimBufferIfNeeded()
        }

        guard let utteranceStartFrame else {
            return []
        }

        guard let chunk = makeChunk(
            startFrame: utteranceStartFrame,
            endFrame: streamEndFrame,
            minimumSpeechWindows: speechWindowCount
        ) else {
            return []
        }

        return [chunk]
    }

    private nonisolated mutating func finalizeWindow(endingAt windowEndFrame: Int) -> AudioChunk? {
        let windowStartFrame = windowEndFrame - settings.analysisWindowFrames
        let rms = sqrt(currentWindowEnergy / Float(currentWindowFrameCount))
        let rawSpeech = currentWindowPeak >= settings.speechWindowPeakThreshold
            && rms >= settings.speechWindowRMSThreshold

        var emittedChunk: AudioChunk?

        if rawSpeech {
            if utteranceStartFrame == nil {
                utteranceStartFrame = max(0, windowStartFrame - settings.leadingPaddingFrames)
                speechWindowCount = 0
            }
            speechWindowCount += 1
            holdRemainingWindows = settings.holdWindowCount
        } else if utteranceStartFrame != nil {
            if holdRemainingWindows > 0 {
                holdRemainingWindows -= 1
            } else {
                emittedChunk = makeChunk(
                    startFrame: utteranceStartFrame ?? windowStartFrame,
                    endFrame: windowStartFrame,
                    minimumSpeechWindows: speechWindowCount
                )
                resetUtteranceState()
            }
        }

        if let utteranceStartFrame,
           windowEndFrame - utteranceStartFrame >= settings.maxUtteranceFrames {
            emittedChunk = makeChunk(
                startFrame: utteranceStartFrame,
                endFrame: windowEndFrame,
                minimumSpeechWindows: speechWindowCount
            )

            if rawSpeech || holdRemainingWindows > 0 {
                self.utteranceStartFrame = max(0, windowEndFrame - settings.continuationOverlapFrames)
                speechWindowCount = rawSpeech ? 1 : 0
            } else {
                resetUtteranceState()
            }
        }

        currentWindowPeak = 0
        currentWindowEnergy = 0
        currentWindowFrameCount = 0

        return emittedChunk
    }

    private nonisolated mutating func makeChunk(
        startFrame: Int,
        endFrame: Int,
        minimumSpeechWindows: Int
    ) -> AudioChunk? {
        guard minimumSpeechWindows >= settings.minimumSpeechWindows else {
            return nil
        }

        let clampedStartFrame = max(bufferStartFrame, startFrame)
        let clampedEndFrame = min(streamEndFrame, endFrame)
        guard clampedEndFrame > clampedStartFrame else {
            return nil
        }

        let localStart = clampedStartFrame - bufferStartFrame
        let localEnd = clampedEndFrame - bufferStartFrame
        guard localStart >= 0, localEnd <= buffer.count, localStart < localEnd else {
            return nil
        }

        return AudioChunk(
            source: source,
            startedFrame: clampedStartFrame,
            startedAt: TimeInterval(clampedStartFrame) / TimeInterval(Self.sampleRate),
            frames: Array(buffer[localStart..<localEnd])
        )
    }

    private nonisolated mutating func resetUtteranceState() {
        utteranceStartFrame = nil
        speechWindowCount = 0
        holdRemainingWindows = 0
    }

    private nonisolated mutating func trimBufferIfNeeded() {
        let keepFromFrame: Int
        if let utteranceStartFrame {
            keepFromFrame = max(0, utteranceStartFrame - settings.leadingPaddingFrames)
        } else {
            keepFromFrame = max(0, streamEndFrame - settings.idleBufferFrames)
        }

        let framesToDrop = keepFromFrame - bufferStartFrame
        guard framesToDrop > 0 else {
            return
        }

        buffer.removeFirst(framesToDrop)
        bufferStartFrame = keepFromFrame
    }
}
