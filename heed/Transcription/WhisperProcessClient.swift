import Foundation

enum WhisperProcessError: LocalizedError {
    case helperMissing
    case modelMissing
    case launchFailed(String)
    case requestEncodeFailed
    case responseMissing
    case responseTimedOut
    case responseDecodeFailed
    case workerError(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "The bundled Whisper helper is missing."
        case .modelMissing:
            return "The bundled Whisper model is missing."
        case .launchFailed(let reason):
            return "Whisper helper launch failed: \(reason)"
        case .requestEncodeFailed:
            return "Whisper request encoding failed."
        case .responseMissing:
            return "Whisper helper closed before sending a response."
        case .responseTimedOut:
            return "Whisper helper took too long to respond."
        case .responseDecodeFailed:
            return "Whisper helper returned unreadable output."
        case .workerError(let message):
            return message
        }
    }
}

actor WhisperProcessClient {
    struct Request: Encodable {
        let chunkID: UUID
        let inputPath: String
    }

    struct Response: Decodable {
        struct Segment: Decodable {
            let startTimeMs: Int
            let endTimeMs: Int
            let text: String
        }

        let chunkID: UUID
        let segments: [Segment]?
        let error: String?
    }

    private let helperURL: URL
    private let modelURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private let responsePollInterval = Duration.milliseconds(25)

    init(helperURL: URL, modelURL: URL) {
        self.helperURL = helperURL
        self.modelURL = modelURL
    }

    func start() throws {
        guard FileManager.default.fileExists(atPath: helperURL.path()) else {
            throw WhisperProcessError.helperMissing
        }

        guard FileManager.default.fileExists(atPath: modelURL.path()) else {
            throw WhisperProcessError.modelMissing
        }

        guard process == nil else {
            return
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = helperURL
        process.arguments = ["--model", modelURL.path()]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw WhisperProcessError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.inputHandle = stdinPipe.fileHandleForWriting
        self.outputHandle = stdoutPipe.fileHandleForReading
        self.outputHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStandardOutput(data)
            }
        }
        self.errorHandle = stderrPipe.fileHandleForReading
        self.errorHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStandardError(data)
            }
        }
    }

    func transcribe(
        frames: [Float],
        responseTimeout: Duration = .seconds(20)
    ) async throws -> [Response.Segment] {
        try start()

        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("pcm")

        let chunkID = UUID()
        try writePCM16(frames, to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let request = Request(chunkID: chunkID, inputPath: tempURL.path())
        guard let payload = try? encoder.encode(request) else {
            throw WhisperProcessError.requestEncodeFailed
        }

        errorBuffer = Data()
        let line = payload + Data([0x0A])
        try inputHandle?.write(contentsOf: line)

        let responseLine = try await readLine(timeout: responseTimeout)
        guard let responseData = responseLine.data(using: .utf8),
              let response = try? decoder.decode(Response.self, from: responseData) else {
            if let helperError = capturedStandardError() {
                throw WhisperProcessError.workerError(helperError)
            }
            throw WhisperProcessError.responseDecodeFailed
        }

        if let error = response.error {
            throw WhisperProcessError.workerError(error)
        }

        return response.segments ?? []
    }

    func stop() {
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        inputHandle?.closeFile()
        outputHandle?.closeFile()
        errorHandle?.closeFile()
        process?.terminate()
        process = nil
        inputHandle = nil
        outputHandle = nil
        errorHandle = nil
        outputBuffer = Data()
        errorBuffer = Data()
    }

    private func writePCM16(_ frames: [Float], to url: URL) throws {
        var data = Data(capacity: frames.count * MemoryLayout<Int16>.stride)
        for frame in frames {
            var sample = Int16(max(-1.0, min(frame, 1.0)) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }
        try data.write(to: url, options: .atomic)
    }

    private func readLine(timeout: Duration) async throws -> String {
        guard outputHandle != nil else {
            throw WhisperProcessError.responseMissing
        }

        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while true {
            if let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
                let lineData = outputBuffer.prefix(upTo: newlineIndex)
                outputBuffer.removeSubrange(...newlineIndex)
                return String(decoding: lineData, as: UTF8.self)
            }

            if let process, !process.isRunning {
                if let helperError = capturedStandardError() {
                    throw WhisperProcessError.workerError(helperError)
                }
                throw WhisperProcessError.responseMissing
            }

            if clock.now >= deadline {
                throw WhisperProcessError.responseTimedOut
            }

            try await Task.sleep(for: responsePollInterval)
        }
    }

    private func consumeStandardOutput(_ data: Data) {
        guard !data.isEmpty else {
            outputHandle?.readabilityHandler = nil
            return
        }

        outputBuffer.append(data)
    }

    private func consumeStandardError(_ data: Data) {
        guard !data.isEmpty else {
            errorHandle?.readabilityHandler = nil
            return
        }

        errorBuffer.append(data)
    }

    private func capturedStandardError() -> String? {
        let message = String(decoding: errorBuffer, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !message.isEmpty else {
            return nil
        }

        return message
    }
}
