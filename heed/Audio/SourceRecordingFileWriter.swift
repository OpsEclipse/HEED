import Darwin
import Foundation

final class SourceRecordingFileWriter {
    private let fileURL: URL
    private var fileDescriptor: Int32 = -1
    private var didClose = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.removeItem(at: fileURL)
    }

    func write(frames: [Float]) throws {
        guard !frames.isEmpty else {
            return
        }

        try ensureOpen()

        var data = Data(capacity: frames.count * MemoryLayout<Int16>.stride)
        for frame in frames {
            let clamped = max(-1.0, min(frame, 1.0))
            var sample = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }

        try POSIXFileDescriptorWriter.writeOrThrow(data, to: fileDescriptor)
    }

    func finish() throws {
        try close()
    }

    func close() throws {
        guard !didClose else {
            return
        }

        didClose = true
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func ensureOpen() throws {
        guard !didClose else {
            throw NSError(domain: "Heed.SourceRecordingFileWriter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The source recording file writer has already been closed."
            ])
        }

        if fileDescriptor >= 0 {
            return
        }

        let openedDescriptor = Darwin.open(fileURL.path, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR)
        guard openedDescriptor >= 0 else {
            throw POSIXFileDescriptorWriterError.writeFailed(errno)
        }

        fileDescriptor = openedDescriptor
    }
}
