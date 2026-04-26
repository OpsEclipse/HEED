import Darwin
import Foundation

enum POSIXFileDescriptorWriter {
    static func write(_ data: Data, to fileDescriptor: Int32) -> Bool {
        do {
            try writeOrThrow(data, to: fileDescriptor)
            return true
        } catch {
            return false
        }
    }

    static func writeOrThrow(_ data: Data, to fileDescriptor: Int32) throws {
        guard fileDescriptor >= 0 else {
            throw POSIXFileDescriptorWriterError.invalidFileDescriptor
        }

        guard !data.isEmpty else {
            return
        }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var bytesWritten = 0
            while bytesWritten < rawBuffer.count {
                let result = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    rawBuffer.count - bytesWritten
                )

                if result > 0 {
                    bytesWritten += result
                    continue
                }

                if result == -1, errno == EINTR {
                    continue
                }

                throw POSIXFileDescriptorWriterError.writeFailed(errno)
            }
        }
    }
}

enum POSIXFileDescriptorWriterError: LocalizedError, Equatable {
    case invalidFileDescriptor
    case writeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidFileDescriptor:
            return "The file descriptor was invalid."
        case let .writeFailed(errorCode):
            return String(cString: strerror(errorCode))
        }
    }
}

@MainActor
protocol TaskPrepTerminalSessionLaunching {
    func launch(
        prompt: String,
        onOutput: @escaping @MainActor (String) -> Void,
        onExit: @escaping @MainActor (Int32?) -> Void
    ) throws -> any TaskPrepTerminalSessionHandle
}

@MainActor
protocol TaskPrepTerminalSessionHandle: AnyObject {
    func write(_ input: String)
    func stop()
}

struct TaskPrepProcessTerminalSessionLauncher: TaskPrepTerminalSessionLaunching {
    private let executableURL: URL
    private let arguments: [String]
    private let workingDirectoryURL: URL

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [String] = Self.defaultArguments,
        workingDirectoryURL: URL = Self.defaultWorkingDirectoryURL
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectoryURL = workingDirectoryURL
    }

    nonisolated static let defaultArguments = ["codex", "--model", "gpt-5.2-codex", "--no-alt-screen"]
    nonisolated static let defaultWindowSize = winsize(
        ws_row: 40,
        ws_col: 120,
        ws_xpixel: 0,
        ws_ypixel: 0
    )

    nonisolated static var defaultWorkingDirectoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    nonisolated static func initialTerminalInput(for prompt: String) -> String {
        "\u{1B}[200~\(prompt)\u{1B}[201~\n"
    }

    nonisolated static func launchArguments(baseArguments: [String], prompt: String) -> [String] {
        baseArguments + [prompt]
    }

    func launch(
        prompt: String,
        onOutput: @escaping @MainActor (String) -> Void,
        onExit: @escaping @MainActor (Int32?) -> Void
    ) throws -> any TaskPrepTerminalSessionHandle {
        var masterFileDescriptor: Int32 = -1
        var slaveFileDescriptor: Int32 = -1
        var windowSize = Self.defaultWindowSize
        guard openpty(&masterFileDescriptor, &slaveFileDescriptor, nil, nil, &windowSize) == 0 else {
            throw TaskPrepTerminalSessionError.launchFailed(String(cString: strerror(errno)))
        }
        Self.configureChildTerminal(slaveFileDescriptor)

        let process = Process()
        let masterHandle = FileHandle(fileDescriptor: masterFileDescriptor, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slaveFileDescriptor, closeOnDealloc: true)

        process.executableURL = executableURL
        process.arguments = Self.launchArguments(baseArguments: arguments, prompt: prompt)
        process.currentDirectoryURL = workingDirectoryURL
        process.environment = Self.terminalEnvironment()
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle
        process.terminationHandler = { process in
            Task { @MainActor in
                onExit(process.terminationStatus)
            }
        }

        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8) else {
                return
            }

            let processedOutput = TerminalControlSequenceResponder.process(output)
            for response in processedOutput.responses {
                if let data = response.data(using: .utf8) {
                    try? POSIXFileDescriptorWriter.writeOrThrow(data, to: handle.fileDescriptor)
                }
            }

            guard !processedOutput.displayText.isEmpty else {
                return
            }

            Task { @MainActor in
                onOutput(processedOutput.displayText)
            }
        }

        do {
            try process.run()
            try? slaveHandle.close()
        } catch {
            masterHandle.readabilityHandler = nil
            try? masterHandle.close()
            try? slaveHandle.close()
            throw TaskPrepTerminalSessionError.launchFailed(error.localizedDescription)
        }

        let handle = TaskPrepProcessTerminalSessionHandle(process: process, masterHandle: masterHandle)
        return handle
    }

    nonisolated static func terminalEnvironment(
        from baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = baseEnvironment
        let commonPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingPath = environment["PATH"] ?? ""
        let mergedPath = (commonPaths + existingPath.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { paths, path in
                if !paths.contains(path) {
                    paths.append(path)
                }
            }
            .joined(separator: ":")
        environment["PATH"] = mergedPath
        if environment["TERM"]?.isEmpty != false || environment["TERM"] == "dumb" {
            environment["TERM"] = "xterm-256color"
        }
        return environment
    }

    nonisolated static func configureChildTerminal(_ fileDescriptor: Int32) {
        var attributes = termios()
        guard tcgetattr(fileDescriptor, &attributes) == 0 else {
            return
        }

        attributes.c_lflag &= ~tcflag_t(ECHO)
        _ = tcsetattr(fileDescriptor, TCSANOW, &attributes)
    }
}

struct ProcessedTerminalOutput: Equatable {
    let displayText: String
    let responses: [String]
}

enum TerminalControlSequenceResponder {
    private nonisolated static let cursorPositionResponse = "\u{1B}[1;1R"

    nonisolated static func process(_ output: String) -> ProcessedTerminalOutput {
        let scalars = Array(output.unicodeScalars)
        var displayScalars = String.UnicodeScalarView()
        var responses = [String]()
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if scalar.value == 0x1B {
                let result = consumeEscapeSequence(in: scalars, from: index)
                responses.append(contentsOf: result.responses)
                index = result.nextIndex
                continue
            }

            if scalar.value == 0x9B {
                let result = consumeControlSequence(in: scalars, bodyStartIndex: index + 1)
                responses.append(contentsOf: result.responses)
                index = result.nextIndex
                continue
            }

            if scalar.value == 0x5B,
               looksLikeNakedControlSequence(in: scalars, at: index) {
                let result = consumeControlSequence(in: scalars, bodyStartIndex: index + 1)
                responses.append(contentsOf: result.responses)
                index = result.nextIndex
                continue
            }

            if scalar.value == 0x5D,
               looksLikeNakedOperatingSystemCommand(in: scalars, at: index) {
                index = consumeOperatingSystemCommand(in: scalars, from: index + 1)
                continue
            }

            if scalar.value == 0x5E,
               index + 2 < scalars.count,
               scalars[index + 1].value == 0x5B {
                if scalars[index + 2].value == 0x5B {
                    let result = consumeControlSequence(in: scalars, bodyStartIndex: index + 3)
                    responses.append(contentsOf: result.responses)
                    index = result.nextIndex
                    continue
                }

                if scalars[index + 2].value == 0x5D {
                    index = consumeOperatingSystemCommand(in: scalars, from: index + 3)
                    continue
                }
            }

            if shouldDisplay(scalar) {
                displayScalars.append(scalar)
            }
            index += 1
        }

        return ProcessedTerminalOutput(
            displayText: String(displayScalars),
            responses: responses
        )
    }

    private nonisolated static func consumeEscapeSequence(
        in scalars: [UnicodeScalar],
        from index: Int
    ) -> TerminalSequenceResult {
        guard index + 1 < scalars.count else {
            return TerminalSequenceResult(nextIndex: scalars.count)
        }

        switch scalars[index + 1].value {
        case 0x5B:
            return consumeControlSequence(in: scalars, bodyStartIndex: index + 2)
        case 0x5D:
            return TerminalSequenceResult(nextIndex: consumeOperatingSystemCommand(in: scalars, from: index + 2))
        case 0x28, 0x29, 0x2A, 0x2B:
            return TerminalSequenceResult(nextIndex: min(index + 3, scalars.count))
        default:
            return TerminalSequenceResult(nextIndex: min(index + 2, scalars.count))
        }
    }

    private nonisolated static func consumeControlSequence(
        in scalars: [UnicodeScalar],
        bodyStartIndex: Int
    ) -> TerminalSequenceResult {
        var index = bodyStartIndex
        while index < scalars.count {
            let value = scalars[index].value
            if (0x40...0x7E).contains(value) {
                let isCursorPositionQuery = value == 0x6E
                    && index == bodyStartIndex + 1
                    && scalars[bodyStartIndex].value == 0x36
                return TerminalSequenceResult(
                    nextIndex: index + 1,
                    responses: isCursorPositionQuery ? [cursorPositionResponse] : []
                )
            }
            index += 1
        }

        return TerminalSequenceResult(nextIndex: scalars.count)
    }

    private nonisolated static func consumeOperatingSystemCommand(
        in scalars: [UnicodeScalar],
        from index: Int
    ) -> Int {
        var index = index
        while index < scalars.count {
            if scalars[index].value == 0x07 {
                return index + 1
            }

            if scalars[index].value == 0x1B,
               index + 1 < scalars.count,
               scalars[index + 1].value == 0x5C {
                return index + 2
            }

            if scalars[index].value == 0x5E,
               index + 2 < scalars.count,
               scalars[index + 1].value == 0x5B,
               scalars[index + 2].value == 0x5C {
                return index + 3
            }

            index += 1
        }

        return scalars.count
    }

    private nonisolated static func looksLikeNakedControlSequence(
        in scalars: [UnicodeScalar],
        at index: Int
    ) -> Bool {
        guard index + 1 < scalars.count else {
            return false
        }

        if scalars[index + 1].value == 0x63 {
            return true
        }

        var scanIndex = index + 1
        var sawParameter = false
        while scanIndex < scalars.count {
            let value = scalars[scanIndex].value
            if (0x30...0x3F).contains(value) {
                sawParameter = true
                scanIndex += 1
                continue
            }

            return sawParameter && isCommonControlSequenceFinalByte(value)
        }

        return sawParameter
    }

    private nonisolated static func isCommonControlSequenceFinalByte(_ value: UInt32) -> Bool {
        switch value {
        case 0x41...0x48, 0x4A, 0x4B, 0x52, 0x63, 0x66, 0x68, 0x6C, 0x6D, 0x6E, 0x75, 0x7E:
            return true
        default:
            return false
        }
    }

    private nonisolated static func looksLikeNakedOperatingSystemCommand(
        in scalars: [UnicodeScalar],
        at index: Int
    ) -> Bool {
        guard index + 2 < scalars.count else {
            return false
        }

        return scalars[index + 1].value == 0x30
            && scalars[index + 2].value == 0x3B
    }

    private nonisolated static func shouldDisplay(_ scalar: UnicodeScalar) -> Bool {
        if scalar.value == 0x0A || scalar.value == 0x09 {
            return true
        }

        return scalar.value >= 0x20 && scalar.value != 0x7F
    }
}

private struct TerminalSequenceResult {
    let nextIndex: Int
    let responses: [String]

    nonisolated init(nextIndex: Int, responses: [String] = []) {
        self.nextIndex = nextIndex
        self.responses = responses
    }
}

enum TaskPrepTerminalSessionError: LocalizedError, Equatable {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            return "Could not start the integrated Codex terminal. \(message)"
        }
    }
}

@MainActor
private final class TaskPrepProcessTerminalSessionHandle: TaskPrepTerminalSessionHandle {
    private let process: Process
    private let masterHandle: FileHandle
    private var isStopped = false

    init(process: Process, masterHandle: FileHandle) {
        self.process = process
        self.masterHandle = masterHandle
    }

    func write(_ input: String) {
        guard !isStopped,
              let data = input.data(using: .utf8) else {
            return
        }

        if !POSIXFileDescriptorWriter.write(data, to: masterHandle.fileDescriptor) {
            isStopped = true
            masterHandle.readabilityHandler = nil
        }
    }

    func stop() {
        guard !isStopped else {
            return
        }

        isStopped = true
        masterHandle.readabilityHandler = nil

        if process.isRunning {
            process.terminate()
        }

        try? masterHandle.close()
    }
}

struct TaskPrepNoopTerminalSessionLauncher: TaskPrepTerminalSessionLaunching {
    func launch(
        prompt: String,
        onOutput: @escaping @MainActor (String) -> Void,
        onExit: @escaping @MainActor (Int32?) -> Void
    ) throws -> any TaskPrepTerminalSessionHandle {
        _ = prompt
        _ = onOutput
        _ = onExit
        return TaskPrepNoopTerminalSessionHandle()
    }
}

@MainActor
private final class TaskPrepNoopTerminalSessionHandle: TaskPrepTerminalSessionHandle {
    func write(_ input: String) {
        _ = input
    }

    func stop() {}
}

struct TaskPrepAgentHandoffTerminalSessionLauncher: TaskPrepTerminalSessionLaunching {
    private let handoffLauncher: any TaskPrepAgentHandoffLaunching

    init(handoffLauncher: any TaskPrepAgentHandoffLaunching) {
        self.handoffLauncher = handoffLauncher
    }

    func launch(
        prompt: String,
        onOutput: @escaping @MainActor (String) -> Void,
        onExit: @escaping @MainActor (Int32?) -> Void
    ) throws -> any TaskPrepTerminalSessionHandle {
        _ = onOutput
        _ = onExit
        try handoffLauncher.launch(prompt: prompt)
        return TaskPrepNoopTerminalSessionHandle()
    }
}
