import AVFoundation
import Foundation

final class MicCaptureManager: MicCaptureManaging {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?

    func start(onFrames: @escaping @Sendable ([Float]) -> Void) throws {
        let inputNode = engine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        guard tapFormat.channelCount > 0 else {
            throw NSError(domain: "Heed.MicCapture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The selected microphone is not providing a usable audio format."
            ])
        }

        converter = AVAudioConverter(from: tapFormat, to: targetFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: tapFormat) { [weak self] buffer, _ in
            guard let self, let converted = self.convert(buffer) else {
                return
            }

            let frames = self.extractFrames(from: converted)
            guard !frames.isEmpty else {
                return
            }

            onFrames(frames)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw wrapStartupError(error)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else {
            return nil
        }

        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        ) + 64

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var didSupplyBuffer = false
        converter.convert(to: outputBuffer, error: &error) { _, status in
            if didSupplyBuffer {
                status.pointee = .noDataNow
                return nil
            }

            didSupplyBuffer = true
            status.pointee = .haveData
            return buffer
        }

        if error != nil {
            return nil
        }

        return outputBuffer
    }

    private func extractFrames(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let frameLength = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)
        return Array(samples)
    }

    private func wrapStartupError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == NSOSStatusErrorDomain, nsError.code == -10877 else {
            return error
        }

        return NSError(domain: "Heed.MicCapture", code: nsError.code, userInfo: [
            NSLocalizedDescriptionKey: "Heed could not connect to the current microphone. In System Settings > Sound, choose a built-in or connected input device, then try recording again.",
            NSUnderlyingErrorKey: nsError
        ])
    }
}
