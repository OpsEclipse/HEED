import Darwin
import Foundation

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
        arguments: [String] = ["codex"],
        workingDirectoryURL: URL = Self.defaultWorkingDirectoryURL
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectoryURL = workingDirectoryURL
    }

    nonisolated static var defaultWorkingDirectoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    nonisolated static func initialTerminalInput(for prompt: String) -> String {
        "\u{1B}[200~\(prompt)\u{1B}[201~\n"
    }

    func launch(
        prompt: String,
        onOutput: @escaping @MainActor (String) -> Void,
        onExit: @escaping @MainActor (Int32?) -> Void
    ) throws -> any TaskPrepTerminalSessionHandle {
        var masterFileDescriptor: Int32 = -1
        var slaveFileDescriptor: Int32 = -1
        guard openpty(&masterFileDescriptor, &slaveFileDescriptor, nil, nil, nil) == 0 else {
            throw TaskPrepTerminalSessionError.launchFailed(String(cString: strerror(errno)))
        }

        let process = Process()
        let masterHandle = FileHandle(fileDescriptor: masterFileDescriptor, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slaveFileDescriptor, closeOnDealloc: true)

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.environment = environmentWithCommandSearchPath()
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

            Task { @MainActor in
                onOutput(output)
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
        handle.write(Self.initialTerminalInput(for: prompt))
        return handle
    }

    private func environmentWithCommandSearchPath() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
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
        return environment
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

        masterHandle.write(data)
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
