import Foundation

enum AudioEnergyGate {
    struct BatchThresholds {
        let peak: Float
        let rms: Float
    }

    struct SpeechSettings {
        let analysisWindowFrames: Int
        let startupThresholds: BatchThresholds
        let speechWindowPeakThreshold: Float
        let speechWindowRMSThreshold: Float
        let holdWindowCount: Int
        let leadingPaddingWindows: Int
        let minimumSpeechWindows: Int
        let maxUtteranceFrames: Int
        let continuationOverlapWindows: Int

        nonisolated var leadingPaddingFrames: Int {
            leadingPaddingWindows * analysisWindowFrames
        }

        nonisolated var continuationOverlapFrames: Int {
            continuationOverlapWindows * analysisWindowFrames
        }

        nonisolated var idleBufferFrames: Int {
            max(leadingPaddingFrames, analysisWindowFrames * 6)
        }
    }

    nonisolated static func settings(for source: AudioSource) -> SpeechSettings {
        switch source {
        case .mic:
            return SpeechSettings(
                analysisWindowFrames: AudioChunker.analysisWindowFrames,
                startupThresholds: BatchThresholds(peak: 0.020, rms: 0.005),
                speechWindowPeakThreshold: 0.025,
                speechWindowRMSThreshold: 0.006,
                holdWindowCount: 18,
                leadingPaddingWindows: 4,
                minimumSpeechWindows: 3,
                maxUtteranceFrames: 15 * AudioChunker.sampleRate,
                continuationOverlapWindows: 4
            )
        case .system:
            return SpeechSettings(
                analysisWindowFrames: AudioChunker.analysisWindowFrames,
                startupThresholds: BatchThresholds(peak: 0.045, rms: 0.012),
                speechWindowPeakThreshold: 0.055,
                speechWindowRMSThreshold: 0.015,
                holdWindowCount: 15,
                leadingPaddingWindows: 4,
                minimumSpeechWindows: 4,
                maxUtteranceFrames: 15 * AudioChunker.sampleRate,
                continuationOverlapWindows: 4
            )
        }
    }

    nonisolated static func containsSpeechLikeEnergy(_ frames: [Float], source: AudioSource) -> Bool {
        let thresholds = settings(for: source).startupThresholds
        let metrics = analyze(frames)
        return metrics.peak >= thresholds.peak && metrics.rms >= thresholds.rms
    }
}

private extension AudioEnergyGate {
    nonisolated static func analyze(_ frames: [Float]) -> AudioEnergyMetrics {
        guard !frames.isEmpty else {
            return AudioEnergyMetrics(peak: 0, rms: 0)
        }

        var peak: Float = 0
        var sum: Float = 0

        for frame in frames {
            let magnitude = abs(frame)
            peak = max(peak, magnitude)
            sum += frame * frame
        }

        return AudioEnergyMetrics(
            peak: peak,
            rms: sqrt(sum / Float(frames.count))
        )
    }
}

private struct AudioEnergyMetrics {
    let peak: Float
    let rms: Float
}
