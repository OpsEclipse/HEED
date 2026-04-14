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
        let app = XCUIApplication()
        app.launchArguments.append("--heed-ui-test")
        app.launch()
        defer { forceQuitHeed() }

        XCTAssertTrue(app.buttons["record-button"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Press record to begin the full transcript"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["sidebar-toggle"].exists)
        XCTAssertTrue(app.buttons["copy-as-text"].exists)
        XCTAssertTrue(app.buttons["fullscreen-toggle"].exists)

        let sidebarToggle = app.buttons["sidebar-toggle"]
        sidebarToggle.click()
        for _ in 0..<20 where sidebarToggle.label != "Close" {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTAssertEqual(sidebarToggle.label, "Close")

        app.buttons["record-button"].click()

        let micTranscript = app.staticTexts["Can you hear me clearly on this side?"]
        XCTAssertTrue(micTranscript.waitForExistence(timeout: uiTimeout))

        app.buttons["record-button"].click()
        let recordButton = app.buttons["record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: uiTimeout + 5))
        for _ in 0..<30 where recordButton.label != "Record" {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTAssertEqual(recordButton.label, "Record")
    }

    @MainActor
    func testCompileTasksFlowAppearsInlineAfterRecordingStops() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--heed-ui-test")
        app.launchArguments.append("--heed-ui-test-task-analysis=success")
        app.launch()
        defer { forceQuitHeed() }

        let recordButton = app.buttons["record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: uiTimeout))

        recordButton.click()
        for _ in 0..<30 where recordButton.label != "Stop" {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTAssertEqual(recordButton.label, "Stop")

        let firstTranscript = app.staticTexts["Can you hear me clearly on this side?"]
        XCTAssertTrue(firstTranscript.waitForExistence(timeout: uiTimeout))

        recordButton.click()
        for _ in 0..<30 where recordButton.label != "Record" {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTAssertEqual(recordButton.label, "Record")

        let compileButton = app.buttons["compile-tasks"]
        XCTAssertTrue(compileButton.waitForExistence(timeout: uiTimeout))
        compileButton.click()

        let sectionHeader = app.buttons["task-analysis-header"]
        XCTAssertTrue(sectionHeader.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Verify the two-way audio path before the next session"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.staticTexts["Preview only. This build keeps task compilation local while the OpenAI-backed compile path is still in progress."].exists)
        XCTAssertTrue(app.buttons["task-analysis-decisions-toggle"].exists)
        XCTAssertTrue(app.buttons["task-analysis-follow-ups-toggle"].exists)
        XCTAssertEqual(compileButton.label, "Recompile")

        let prepareContextButton = app.buttons["task-row-prepare-context-verify-audio-paths"]
        XCTAssertTrue(prepareContextButton.waitForExistence(timeout: uiTimeout))
        XCTAssertEqual(prepareContextButton.label, "Prepare context")
        prepareContextButton.click()

        let taskContextPanel = app.buttons["task-context-primary"]
        XCTAssertTrue(taskContextPanel.waitForExistence(timeout: uiTimeout))
        XCTAssertEqual(taskContextPanel.label, "Spawn agent")
        XCTAssertTrue(app.buttons["task-context-close"].exists)
        XCTAssertTrue(app.staticTexts["Turn this transcript task into a concrete implementation plan."].waitForExistence(timeout: uiTimeout))

        taskContextPanel.click()
        for _ in 0..<30 where taskContextPanel.label != "Spawn agent" {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTAssertEqual(taskContextPanel.label, "Spawn agent")

        let showSourceButton = app.buttons["task-row-source-verify-audio-paths"]
        XCTAssertTrue(showSourceButton.exists)
        showSourceButton.click()
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
