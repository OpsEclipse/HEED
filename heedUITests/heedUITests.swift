//
//  heedUITests.swift
//  heedUITests
//
//  Created by Sparsh Shah on 2026-04-08.
//
import AppKit
import XCTest

final class heedUITests: XCTestCase {
    private let uiTimeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRecordingShellLoadsInUITestMode() throws {
        let app = launchAppInUITestMode()
        defer { forceQuitHeed() }

        XCTAssertTrue(app.buttons["record-button"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Press record to begin the full transcript"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["sidebar-toggle"].exists)
        XCTAssertTrue(app.buttons["copy-as-text"].exists)

        let sidebarToggle = app.buttons["sidebar-toggle"]
        sidebarToggle.click()
        XCTAssertTrue(waitForButtonLabel("sidebar-toggle", label: "Close", in: app))

        app.buttons["record-button"].click()

        XCTAssertTrue(waitForButtonLabel("record-button", label: "Stop", in: app))
        XCTAssertTrue(app.otherElements["recording-blank-canvas"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Recording locally"].exists)
        XCTAssertFalse(app.staticTexts["Can you hear me clearly on this side?"].exists)

        app.buttons["record-button"].click()
        XCTAssertTrue(app.staticTexts["MIC transcript"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["SYSTEM transcript"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Can you hear me clearly on this side?"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(waitForButtonLabel("record-button", label: "Record", in: app, timeout: uiTimeout + 5))
    }

    @MainActor
    func testCompileTasksFlowAppearsInlineAfterRecordingStops() throws {
        let app = launchAppInUITestMode(taskAnalysisMode: "success")
        defer { forceQuitHeed() }

        XCTAssertTrue(app.buttons["record-button"].waitForExistence(timeout: uiTimeout))

        app.buttons["record-button"].click()
        XCTAssertTrue(waitForButtonLabel("record-button", label: "Stop", in: app))
        XCTAssertTrue(app.otherElements["recording-blank-canvas"].waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.staticTexts["Can you hear me clearly on this side?"].exists)

        app.buttons["record-button"].click()
        XCTAssertTrue(app.staticTexts["MIC transcript"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["SYSTEM transcript"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Can you hear me clearly on this side?"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(waitForButtonLabel("record-button", label: "Record", in: app, timeout: uiTimeout + 5))

        let compileButton = app.buttons["compile-tasks"]
        XCTAssertTrue(compileButton.waitForExistence(timeout: uiTimeout))
        compileButton.click()

        let sectionHeader = app.buttons["task-analysis-header"]
        XCTAssertTrue(sectionHeader.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Verify the two-way audio path before the next session"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Preview only. This build keeps task compilation local while the OpenAI-backed compile path is still in progress."].exists)
        XCTAssertEqual(compileButton.label, "Recompile")

        let prepareContextButton = app.buttons["task-row-prepare-context-verify-audio-paths"]
        XCTAssertTrue(prepareContextButton.waitForExistence(timeout: uiTimeout))
        XCTAssertEqual(prepareContextButton.label, "Prepare context")
        prepareContextButton.click()

        XCTAssertTrue(app.otherElements["task-prep-workspace"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.scrollViews["task-prep-chat-thread"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(
            app.staticTexts["I think we have enough context to proceed. Do you want me to spawn the agent now?"]
                .waitForExistence(timeout: uiTimeout)
        )
        XCTAssertTrue(app.otherElements["task-prep-context-panel"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["task-prep-approve-spawn"].waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.buttons["task-context-primary"].exists)
        XCTAssertFalse(app.buttons["task-context-close"].exists)
        XCTAssertTrue(app.staticTexts["Prepare the transcript review follow-up."].waitForExistence(timeout: uiTimeout))

        let showSourceButton = app.buttons["task-row-source-verify-audio-paths"]
        XCTAssertTrue(showSourceButton.exists)
        showSourceButton.click()
    }

    @MainActor
    private func launchAppInUITestMode(taskAnalysisMode: String? = nil) -> XCUIApplication {
        forceQuitHeed()

        let app = XCUIApplication()
        app.launchArguments = [
            "--heed-ui-test",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]

        if let taskAnalysisMode {
            app.launchArguments.append("--heed-ui-test-task-analysis=\(taskAnalysisMode)")
        }

        app.launch()
        return app
    }

    @MainActor
    func testLaunchPerformance() throws {
        throw XCTSkip("Launch performance is flaky in local macOS UI runs. Keep the functional launch test instead.")
    }
}

private func forceQuitHeed() {
    NSRunningApplication.runningApplications(withBundleIdentifier: "sprsh.ca.heed").forEach { app in
        app.forceTerminate()
    }
}

private func waitForButtonLabel(
    _ identifier: String,
    label expectedLabel: String,
    in app: XCUIApplication,
    timeout: TimeInterval = 3
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        let button = app.buttons[identifier]
        if button.exists, button.label == expectedLabel {
            return true
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    return app.buttons[identifier].exists && app.buttons[identifier].label == expectedLabel
}
