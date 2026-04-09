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
        XCTAssertTrue(app.staticTexts["Heed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No saved sessions yet."].exists)

        app.buttons["record-button"].click()

        let micTranscript = app.staticTexts["Can you hear me clearly on this side?"]
        XCTAssertTrue(micTranscript.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        throw XCTSkip("Launch performance is flaky in local macOS UI runs. Keep the functional launch test instead.")
    }
}
