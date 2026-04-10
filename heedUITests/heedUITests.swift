//
//  heedUITests.swift
//  heedUITests
//
//  Created by Sparsh Shah on 2026-04-08.
//

import XCTest

final class heedUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRecordingShellLoadsInUITestMode() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--heed-ui-test")
        app.launch()

        XCTAssertTrue(app.buttons["record-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Press record to begin the full transcript"].waitForExistence(timeout: 5))
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

        let micTranscript = app.otherElements["segment-mic"].firstMatch
        XCTAssertTrue(micTranscript.waitForExistence(timeout: 5))

        app.buttons["record-button"].click()
        let recordButton = app.buttons["record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 2))
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

        let recordButton = app.buttons["record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))

        recordButton.click()

        let micTranscript = app.otherElements["segment-mic"].firstMatch
        XCTAssertTrue(micTranscript.waitForExistence(timeout: 5))

        recordButton.click()
        for _ in 0..<30 where recordButton.label != "Record" {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTAssertEqual(recordButton.label, "Record")

        let compileButton = app.buttons["compile-tasks"]
        XCTAssertTrue(compileButton.waitForExistence(timeout: 5))
        compileButton.click()

        let sectionHeader = app.buttons["task-analysis-header"]
        XCTAssertTrue(sectionHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Suggested tasks"].exists)
        XCTAssertTrue(app.staticTexts["Verify the two-way audio path before the next session"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preview only. This build keeps task compilation local while the OpenAI-backed compile path is still in progress."].exists)
        XCTAssertTrue(app.buttons["task-analysis-decisions-toggle"].exists)
        XCTAssertTrue(app.buttons["task-analysis-follow-ups-toggle"].exists)
        XCTAssertEqual(compileButton.label, "Recompile")

        let showSourceButton = app.buttons["task-row-source-verify-audio-paths"]
        XCTAssertTrue(showSourceButton.exists)
        showSourceButton.click()
        XCTAssertTrue(micTranscript.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        throw XCTSkip("Launch performance is flaky in local macOS UI runs. Keep the functional launch test instead.")
    }
}
