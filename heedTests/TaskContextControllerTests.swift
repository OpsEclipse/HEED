import Foundation
import Testing
@testable import heed

struct TaskContextControllerTests {
    @Test func loadsSelectedTaskContextThroughInjectedCompiler() async throws {
        let session = sampleSession()
        let task = sampleTask(id: "task-one", title: "Prepare the follow-up plan")
        let content = sampleContent(for: task, session: session)

        let controller = await MainActor.run {
            TaskContextController(compiler: ImmediateTaskContextCompiler(content: content))
        }

        #expect(await MainActor.run { controller.panelState == .idle })

        await MainActor.run {
            controller.prepareTaskContext(for: task, in: session)
        }

        let state = try await waitForPanelState(controller) { state in
            if case .loaded(let loadedContent) = state {
                return loadedContent == content
            }

            return false
        }

        #expect(state == .loaded(content))
        #expect(await MainActor.run { controller.selectedTaskID == task.id })
    }

    @Test func ignoresStaleTaskContextResultsWhenAnotherTaskIsRequested() async throws {
        let session = sampleSession()
        let firstTask = sampleTask(id: "task-one", title: "Prepare the follow-up plan")
        let secondTask = sampleTask(id: "task-two", title: "Review the rollout notes")

        let compiler = ControlledTaskContextCompiler()
        let controller = await MainActor.run {
            TaskContextController(compiler: compiler)
        }

        await MainActor.run {
            controller.prepareTaskContext(for: firstTask, in: session)
            controller.prepareTaskContext(for: secondTask, in: session)
        }

        try await waitForPendingRequestCount(2, compiler: compiler)

        await compiler.completeNext(with: sampleContent(for: firstTask, session: session))

        try await Task.sleep(for: .milliseconds(50))

        #expect(await MainActor.run { controller.panelState == .loading(task: secondTask) })

        await compiler.completeNext(with: sampleContent(for: secondTask, session: session))

        let state = try await waitForPanelState(controller) { state in
            if case .loaded(let loadedContent) = state {
                return loadedContent.task.id == secondTask.id
            }

            return false
        }

        #expect(state == .loaded(sampleContent(for: secondTask, session: session)))
        #expect(await MainActor.run { controller.selectedTaskID == secondTask.id })
    }

    @Test func marksFailedLoadsWithTheSelectedTaskAndErrorMessage() async throws {
        let session = sampleSession()
        let task = sampleTask(id: "task-one", title: "Prepare the follow-up plan")
        let compiler = FailingTaskContextCompiler(message: "Could not prepare task context")

        let controller = await MainActor.run {
            TaskContextController(compiler: compiler)
        }

        await MainActor.run {
            controller.prepareTaskContext(for: task, in: session)
        }

        let state = try await waitForPanelState(controller) { state in
            if case .failed = state {
                return true
            }

            return false
        }

        #expect(state == .failed(task: task, message: "Could not prepare task context"))
        #expect(await MainActor.run { controller.selectedTaskID == task.id })
    }
}

private struct ImmediateTaskContextCompiler: TaskContextCompiling {
    let content: TaskContextPanelContent

    func prepareTaskContext(session: TranscriptSession, task: CompiledTask) async throws -> TaskContextPanelContent {
        content
    }
}

private struct FailingTaskContextCompiler: TaskContextCompiling {
    let message: String

    func prepareTaskContext(session: TranscriptSession, task: CompiledTask) async throws -> TaskContextPanelContent {
        throw TaskContextCompilerStubError(message: message)
    }
}

private actor ControlledTaskContextCompiler: TaskContextCompiling {
    private var pendingRequests: [CheckedContinuation<TaskContextPanelContent, Error>] = []

    func prepareTaskContext(session: TranscriptSession, task: CompiledTask) async throws -> TaskContextPanelContent {
        try await withCheckedThrowingContinuation { continuation in
            pendingRequests.append(continuation)
        }
    }

    func completeNext(with content: TaskContextPanelContent) {
        guard !pendingRequests.isEmpty else {
            return
        }

        let continuation = pendingRequests.removeFirst()
        continuation.resume(returning: content)
    }

    func pendingRequestCount() -> Int {
        pendingRequests.count
    }
}

private struct TaskContextCompilerStubError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

private func waitForPanelState(
    _ controller: TaskContextController,
    matches predicate: @escaping (TaskContextPanelState) -> Bool,
    attempts: Int = 40
) async throws -> TaskContextPanelState {
    for _ in 0..<attempts {
        let state = await MainActor.run { controller.panelState }
        if predicate(state) {
            return state
        }

        try await Task.sleep(for: .milliseconds(25))
    }

    return await MainActor.run { controller.panelState }
}

private func waitForPendingRequestCount(
    _ expectedCount: Int,
    compiler: ControlledTaskContextCompiler,
    attempts: Int = 40
) async throws {
    for _ in 0..<attempts {
        let pendingCount = await compiler.pendingRequestCount()
        if pendingCount >= expectedCount {
            return
        }

        try await Task.sleep(for: .milliseconds(25))
    }

    #expect(await compiler.pendingRequestCount() >= expectedCount)
}

private func sampleSession() -> TranscriptSession {
    TranscriptSession(
        startedAt: Date(timeIntervalSince1970: 0),
        endedAt: Date(timeIntervalSince1970: 12),
        duration: 12,
        status: .completed,
        modelName: "ggml-base.en",
        appVersion: "1.0",
        segments: [
            TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2, text: "We should prepare a context packet."),
            TranscriptSegment(source: .system, startedAt: 3, endedAt: 4, text: "The side panel should stay visible."),
            TranscriptSegment(source: .mic, startedAt: 5, endedAt: 6, text: "That keeps the transcript easy to review.")
        ]
    )
}

private func sampleTask(id: String, title: String) -> CompiledTask {
    CompiledTask(
        id: id,
        title: title,
        details: "Use the right-side panel to build task context.",
        type: .feature,
        assigneeHint: "Product engineer",
        evidenceSegmentIDs: [],
        evidenceExcerpt: "The side panel should stay visible."
    )
}

private func sampleContent(
    for task: CompiledTask,
    session: TranscriptSession? = nil
) -> TaskContextPanelContent {
    let sourceSession = session ?? sampleSession()

    return TaskContextPanelContent(
        task: task,
        goal: "Make task context readable before the agent is spawned.",
        whyItMatters: "The user needs enough detail to trust the next step.",
        implementationNotes: [
            "Keep the transcript visible while the context panel is open.",
            "Keep the controller in memory only for this pass."
        ],
        acceptanceCriteria: [
            "The panel opens for one selected task.",
            "The panel can show a final Spawn agent button area."
        ],
        risks: [
            "The panel could crowd the transcript if it becomes too tall."
        ],
        suggestedSkills: [
            "SwiftUI",
            "Task cancellation",
            "Structured output"
        ],
        evidence: [
            TaskContextEvidence(
                id: "evidence-1",
                label: "Transcript evidence",
                excerpt: sourceSession.segments[1].text,
                segmentIDs: [sourceSession.segments[1].id]
            )
        ]
    )
}
