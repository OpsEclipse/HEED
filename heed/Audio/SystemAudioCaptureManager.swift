import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCaptureManager: NSObject {
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let sampleHandlerQueue = DispatchQueue(label: "ca.sprsh.heed.system-audio")

    private var stream: SCStream?
    private var converter: AVAudioConverter?
    private var onFrames: (@Sendable ([Float]) -> Void)?
    private var onFailure: (@Sendable (String) -> Void)?
    private var isStopping = false

    func start(
        onFrames: @escaping @Sendable ([Float]) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) async throws {
        self.onFrames = onFrames
        self.onFailure = onFailure
        self.isStopping = false

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
            throw NSError(domain: "Heed.SystemAudioCapture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No display is available for ScreenCaptureKit."
            ])
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 1
        configuration.showsCursor = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleHandlerQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        isStopping = true
        if let stream {
            try? await stream.stopCapture()
        }
        self.stream = nil
        self.converter = nil
        self.onFailure = nil
        self.onFrames = nil
    }

    private func handle(sampleBuffer: CMSampleBuffer) {
        guard let pcmBuffer = sampleBuffer.heedAudioBuffer() else {
            NSLog("System audio capture dropped an unreadable audio buffer.")
            return
        }

        if converter == nil {
            converter = AVAudioConverter(from: pcmBuffer.format, to: targetFormat)
        }

        guard let converted = convert(buffer: pcmBuffer) else {
            NSLog("System audio capture dropped a buffer that could not be converted.")
            return
        }

        let frames = extractFrames(from: converted)
        guard !frames.isEmpty else {
            NSLog("System audio capture dropped an empty converted buffer.")
            return
        }

        onFrames?(frames)
    }

    private func convert(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
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
}

extension SystemAudioCaptureManager: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else {
            return
        }

        handle(sampleBuffer: sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        guard !isStopping else {
            return
        }

        onFailure?("System audio capture stopped unexpectedly: \(error.localizedDescription)")
        NSLog("System audio capture stopped: %@", error.localizedDescription)
    }
}

private extension CMSampleBuffer {
    func heedAudioBuffer() -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              CMSampleBufferDataIsReady(self) else {
            return nil
        }

        let audioFormat = AVAudioFormat(streamDescription: streamDescription)
        let frameCapacity = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))

        guard let audioFormat,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        pcmBuffer.frameLength = frameCapacity

        var audioBufferListSizeNeeded = 0
        var blockBuffer: CMBlockBuffer?

        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: &audioBufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )

        guard sizeStatus == noErr, audioBufferListSizeNeeded > 0 else {
            return nil
        }

        let audioBufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            audioBufferListPointer.deallocate()
        }

        let audioBufferList = audioBufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: audioBufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            return nil
        }

        let sourceBufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let destinationBufferList = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)

        for (index, sourceBuffer) in sourceBufferList.enumerated() where index < destinationBufferList.count {
            guard let sourcePointer = sourceBuffer.mData,
                  let destinationPointer = destinationBufferList[index].mData else {
                continue
            }

            let byteCount = min(Int(sourceBuffer.mDataByteSize), Int(destinationBufferList[index].mDataByteSize))
            memcpy(destinationPointer, sourcePointer, byteCount)
        }

        return pcmBuffer
    }
}
