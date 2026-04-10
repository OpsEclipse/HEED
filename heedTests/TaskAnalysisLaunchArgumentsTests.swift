//
//  TaskAnalysisLaunchArgumentsTests.swift
//  heedTests
//
//  Created by Sparsh Shah on 2026-04-09.
//

import Foundation
import Testing
@testable import heed

struct TaskAnalysisLaunchArgumentsTests {
    @Test func emptyLaunchArgumentBuildsEmptyTaskDraft() async throws {
        let controller = await MainActor.run {
            makeTaskAnalysisController(
                processInfo: FakeProcessInfo(arguments: [
                    "--heed-ui-test",
                    "--heed-ui-test-task-analysis=empty"
                ])
            )
        }

        await MainActor.run {
            controller.updateDisplayedSession(demoTranscriptSession())
            controller.handleCompileAction()
        }

        let sectionModel = try await waitForTaskAnalysisSectionModel(controller)

        #expect(sectionModel?.result?.tasks.isEmpty == true)
        #expect(sectionModel?.result?.noTasksReason == "No clear tasks found")
    }

    @Test func failureLaunchArgumentBuildsFailureDraft() async throws {
        let controller = await MainActor.run {
            makeTaskAnalysisController(
                processInfo: FakeProcessInfo(arguments: [
                    "--heed-ui-test",
                    "--heed-ui-test-task-analysis=failure"
                ])
            )
        }

        await MainActor.run {
            controller.updateDisplayedSession(demoTranscriptSession())
            controller.handleCompileAction()
        }

        let sectionModel = try await waitForTaskAnalysisSectionModel(controller)

        #expect(sectionModel?.errorText == "Could not compile tasks")
        #expect(sectionModel?.result == nil)
    }
}

private final class FakeProcessInfo: ProcessInfo {
    private let fakeArguments: [String]

    init(arguments: [String]) {
        self.fakeArguments = arguments
        super.init()
    }

    override var arguments: [String] {
        fakeArguments
    }
}

private func waitForTaskAnalysisSectionModel(
    _ controller: TaskAnalysisController,
    attempts: Int = 20
) async throws -> TaskAnalysisController.SectionModel? {
    for _ in 0..<attempts {
        let sectionModel = await MainActor.run { controller.sectionModel }
        if sectionModel?.isCompiling != true {
            return sectionModel
        }
        try await Task.sleep(for: .milliseconds(25))
    }

    return await MainActor.run { controller.sectionModel }
}

private func demoTranscriptSession() -> TranscriptSession {
    TranscriptSession(
        startedAt: Date(timeIntervalSince1970: 0),
        endedAt: Date(timeIntervalSince1970: 10),
        duration: 10,
        status: .completed,
        modelName: "ggml-base.en",
        appVersion: "1.0",
        segments: [
            TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2.4, text: "Can you hear me clearly on this side?"),
            TranscriptSegment(source: .system, startedAt: 2, endedAt: 3.5, text: "Yes, the remote call audio is coming through."),
            TranscriptSegment(source: .mic, startedAt: 4.2, endedAt: 5.8, text: "Perfect. Heed is showing separate live labels."),
        ]
    )
}
