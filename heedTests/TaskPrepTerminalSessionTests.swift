import Foundation
import Testing
@testable import heed

struct TaskPrepTerminalSessionTests {
    @Test func initialTerminalInputUsesBracketedPasteForMultilinePrompt() {
        let input = TaskPrepProcessTerminalSessionLauncher.initialTerminalInput(
            for: "Compressed handoff\nGoal: Keep this together."
        )

        #expect(input.hasPrefix("\u{1B}[200~"))
        #expect(input.contains("Compressed handoff\nGoal: Keep this together."))
        #expect(input.hasSuffix("\u{1B}[201~\n"))
    }

    @Test func defaultWorkingDirectoryPointsAtRepoRoot() {
        let url = TaskPrepProcessTerminalSessionLauncher.defaultWorkingDirectoryURL

        #expect(url.lastPathComponent == "heed")
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("heed.xcodeproj").path))
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
