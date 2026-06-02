import Darwin
import Foundation
import Testing
@testable import heed

struct TaskPrepTerminalSessionTests {
    @Test func fileDescriptorWriterReportsInvalidDescriptorInsteadOfUsingFileHandleWrite() {
        let data = Data("hello".utf8)

        let result = POSIXFileDescriptorWriter.write(data, to: -1)

        #expect(result == false)
    }

    @Test func launchArgumentsPinCompatibleModelAndPassPromptToCodexInline() {
        let prompt = "Compressed handoff\nGoal: Keep this together."

        let arguments = TaskPrepProcessTerminalSessionLauncher.launchArguments(
            baseArguments: TaskPrepProcessTerminalSessionLauncher.defaultArguments,
            prompt: prompt
        )

        #expect(arguments == ["codex", "--model", "gpt-5.2-codex", "--no-alt-screen", prompt])
    }

    @Test func codexPreflightUsesFirstCompleteCodexInstall() throws {
        let fixture = try CodexPreflightFixture()
        defer { fixture.remove() }

        let brokenCommand = try fixture.makeCodexPackage(
            binName: "broken-bin",
            hasNativeBinary: false
        )
        let workingCommand = try fixture.makeCodexPackage(
            binName: "working-bin",
            hasNativeBinary: true
        )
        let preflight = CodexLaunchPreflight(fileManager: fixture.fileManager)

        let arguments = try preflight.resolveLaunchArguments(
            baseArguments: ["codex", "--model", "gpt-5.2-codex"],
            environment: [
                "PATH": [
                    brokenCommand.deletingLastPathComponent().path,
                    workingCommand.deletingLastPathComponent().path
                ].joined(separator: ":")
            ]
        )

        #expect(arguments == [workingCommand.resolvingSymlinksInPath().path, "--model", "gpt-5.2-codex"])
    }

    @Test func codexPreflightReportsIncompleteCodexInstall() throws {
        let fixture = try CodexPreflightFixture()
        defer { fixture.remove() }

        let brokenCommand = try fixture.makeCodexPackage(
            binName: "broken-bin",
            hasNativeBinary: false
        )
        let preflight = CodexLaunchPreflight(fileManager: fixture.fileManager)

        do {
            _ = try preflight.resolveLaunchArguments(
                baseArguments: ["codex"],
                environment: ["PATH": brokenCommand.deletingLastPathComponent().path]
            )
            Issue.record("Expected incomplete Codex install to fail preflight.")
        } catch let error as TaskPrepTerminalSessionError {
            #expect(error.errorDescription?.contains("local Codex CLI is incomplete") == true)
            #expect(error.errorDescription?.contains("npm install -g @openai/codex@latest") == true)
        }
    }

    @Test func defaultTerminalWindowSizeIsReadable() {
        let windowSize = TaskPrepProcessTerminalSessionLauncher.defaultWindowSize

        #expect(windowSize.ws_col == 120)
        #expect(windowSize.ws_row == 40)
    }

    @Test func defaultWorkingDirectoryPointsAtRepoRoot() {
        let url = TaskPrepProcessTerminalSessionLauncher.defaultWorkingDirectoryURL

        #expect(url.lastPathComponent == "heed")
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("heed.xcodeproj").path))
    }

    @Test func terminalEnvironmentOverridesDumbTermForCodexTUI() {
        let environment = TaskPrepProcessTerminalSessionLauncher.terminalEnvironment(
            from: [
                "PATH": "/custom/bin",
                "TERM": "dumb"
            ]
        )

        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["PATH"]?.contains("/opt/homebrew/bin") == true)
        #expect(environment["PATH"]?.contains("/custom/bin") == true)
    }

    @Test func terminalResponderAnswersCursorPositionQueries() {
        let processed = TerminalControlSequenceResponder.process("before\u{1B}[6nafter\u{1B}[6n")

        #expect(processed.displayText == "beforeafter")
        #expect(processed.responses == ["\u{1B}[1;1R", "\u{1B}[1;1R"])
    }

    @Test func terminalResponderStripsTerminalControlSequencesFromDisplay() {
        let processed = TerminalControlSequenceResponder.process(
            "before\u{1B}[?2004h\u{1B}[39mcolor\u{1B}[0m\u{1B}]0;heed\u{7}after"
        )

        #expect(processed.displayText == "beforecolorafter")
        #expect(processed.responses.isEmpty)
    }

    @Test func terminalResponderStripsCaretEscapedAndNakedControlSequences() {
        let processed = TerminalControlSequenceResponder.process(
            "^[[200~Compressed handoff^[[201~\n[?2004hready[39m"
        )

        #expect(processed.displayText == "Compressed handoff\nready")
        #expect(processed.responses.isEmpty)
    }

    @Test func terminalResponderKeepsNormalBracketedText() {
        let processed = TerminalControlSequenceResponder.process("[1/2] visible")

        #expect(processed.displayText == "[1/2] visible")
        #expect(processed.responses.isEmpty)
    }

    @Test func childTerminalConfigurationDisablesEcho() throws {
        var masterFileDescriptor: Int32 = -1
        var slaveFileDescriptor: Int32 = -1
        guard openpty(&masterFileDescriptor, &slaveFileDescriptor, nil, nil, nil) == 0 else {
            throw POSIXFileDescriptorWriterError.writeFailed(errno)
        }
        defer {
            close(masterFileDescriptor)
            close(slaveFileDescriptor)
        }

        var attributes = termios()
        #expect(tcgetattr(slaveFileDescriptor, &attributes) == 0)
        attributes.c_lflag |= tcflag_t(ECHO)
        #expect(tcsetattr(slaveFileDescriptor, TCSANOW, &attributes) == 0)

        TaskPrepProcessTerminalSessionLauncher.configureChildTerminal(slaveFileDescriptor)

        var updatedAttributes = termios()
        #expect(tcgetattr(slaveFileDescriptor, &updatedAttributes) == 0)
        #expect(updatedAttributes.c_lflag & tcflag_t(ECHO) == 0)
    }

    @Test func appTargetDoesNotEnableSandboxForIntegratedTerminal() throws {
        let repoRoot = TaskPrepProcessTerminalSessionLauncher.defaultWorkingDirectoryURL
        let projectFile = repoRoot.appendingPathComponent("heed.xcodeproj/project.pbxproj")
        let entitlementsFile = repoRoot.appendingPathComponent("heed/heed.entitlements")

        let projectContents = try String(contentsOf: projectFile, encoding: .utf8)
        let entitlementsContents = try String(contentsOf: entitlementsFile, encoding: .utf8)

        #expect(!projectContents.contains("ENABLE_APP_SANDBOX = YES;"))
        #expect(!entitlementsContents.contains("com.apple.security.app-sandbox"))
    }
}

private struct CodexPreflightFixture {
    let fileManager = FileManager.default
    let root: URL

    init() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("heed-codex-preflight-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? fileManager.removeItem(at: root)
    }

    func makeCodexPackage(binName: String, hasNativeBinary: Bool) throws -> URL {
        let installRoot = root.appendingPathComponent(binName)
        let binDirectory = installRoot.appendingPathComponent("bin")
        let openAIDirectory = installRoot.appendingPathComponent("lib/node_modules/@openai")
        let packageRoot = openAIDirectory.appendingPathComponent("codex")
        let scriptDirectory = packageRoot.appendingPathComponent("bin")
        let scriptURL = scriptDirectory.appendingPathComponent("codex.js")
        let commandURL = binDirectory.appendingPathComponent("codex")

        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try """
        #!/usr/bin/env node
        // Unified entry point for the Codex CLI.
        const PLATFORM_PACKAGE_BY_TARGET = { "aarch64-apple-darwin": "@openai/codex-darwin-arm64" };
        """
        .write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try fileManager.createSymbolicLink(at: commandURL, withDestinationURL: scriptURL)

        if hasNativeBinary {
            let nativeBinary = openAIDirectory
                .appendingPathComponent(Self.platformPackageName)
                .appendingPathComponent("vendor")
                .appendingPathComponent(Self.targetTriple)
                .appendingPathComponent("bin")
                .appendingPathComponent("codex")
            try fileManager.createDirectory(
                at: nativeBinary.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "#!/bin/sh\nexit 0\n".write(to: nativeBinary, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nativeBinary.path)
        }

        return commandURL
    }

    private static var targetTriple: String {
        #if arch(arm64)
        return "aarch64-apple-darwin"
        #else
        return "x86_64-apple-darwin"
        #endif
    }

    private static var platformPackageName: String {
        #if arch(arm64)
        return "codex-darwin-arm64"
        #else
        return "codex-darwin-x64"
        #endif
    }
}
