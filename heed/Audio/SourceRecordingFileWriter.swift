import Foundation

final class SourceRecordingFileWriter {
    private let fileURL: URL
    private var fileHandle: FileHandle?
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

        try fileHandle?.write(contentsOf: data)
    }

    func finish() throws {
        try close()
    }

    func close() throws {
        guard !didClose else {
            return
        }

        didClose = true
        fileHandle?.closeFile()
        fileHandle = nil
    }

    private func ensureOpen() throws {
        guard !didClose else {
            throw NSError(domain: "Heed.SourceRecordingFileWriter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The source recording file writer has already been closed."
            ])
        }

        if fileHandle != nil {
            return
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
    }
}
