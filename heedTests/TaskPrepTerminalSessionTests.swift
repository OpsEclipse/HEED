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
