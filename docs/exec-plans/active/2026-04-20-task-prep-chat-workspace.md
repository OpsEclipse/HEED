# Task Prep Chat Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current one-shot task context panel with a streamed prep chat that builds live task context and can hand off to `spawn_agent` after explicit user approval.

**Architecture:** Keep the existing pass-1 `Compile tasks` flow, but replace pass 2 with a dedicated `TaskPrepController` and a two-pane workspace inside `WorkspaceShell`. Use the OpenAI Responses API with streaming [sending small pieces of the reply as they are generated] plus custom tools for `get_meeting_transcript` and guarded `spawn_agent`.

**Tech Stack:** SwiftUI, Swift Concurrency, OpenAI Responses API, server-sent events [a network response that delivers typed events over time], XCTest UI tests, `Testing`

---

## Scope

- Add a left-side prep chat workspace that opens from `Prepare context`.
- Keep a right-side context panel at about `30%` width and update it from the chat.
- Add streamed GPT-5.4 prep replies.
- Add a read-only transcript tool and a guarded `spawn_agent` tool path.
- Keep prep chat state in memory only.
- Update unit tests, UI tests, and docs for the shipped behavior.

## Non-Goals

- Saving prep chat history or prep context to disk.
- Auto-spawning without user approval.
- Changing transcript session storage.
- Supporting multiple prep chats at once.
- Replacing the existing pass-1 task compilation flow.

## Risks

- Streaming event handling can be brittle if the parser drops partial text or tool-call arguments.
- The new split layout can squeeze the transcript shell if we do not keep the panel widths steady.
- A stale streamed turn can land on the wrong task if cancellation is incomplete.
- Tool calling can become unsafe if `spawn_agent` is not blocked in app code as well as the prompt.
- UI-test fixture behavior can drift from the real controller behavior if the fake stream is too simple.

## Open Questions

- None for v1. The approved spec fixed the main product decisions.

## File Structure

### Create

- `heed/Analysis/TaskPrepModels.swift`
  Shared task-prep types for chat messages, live context draft, tool calls, and turn state.
- `heed/Analysis/TaskPrepController.swift`
  Main state owner for the prep workspace.
- `heed/Analysis/TaskPrepConversationService.swift`
  Protocol plus real and fixture services for streamed prep turns.
- `heed/Analysis/OpenAIResponsesStream.swift`
  Streaming transport and event parser support for the Responses API.
- `heed/UI/TaskPrepWorkspaceView.swift`
  Two-pane composition for chat plus context.
- `heed/UI/TaskPrepChatView.swift`
  Left chat thread and input row.
- `heed/UI/TaskPrepContextPanelView.swift`
  Right structured context panel for the new prep flow.
- `heedTests/TaskPrepControllerTests.swift`
  Controller tests for streamed turns, guardrails, and resets.
- `heedTests/OpenAIResponsesStreamTests.swift`
  Parser tests for streamed text and tool events.

### Modify

- `heed/ContentView.swift`
  Instantiate the prep controller and wire fixture vs real services.
- `heed/UI/WorkspaceShell.swift`
  Swap the old pass-2 panel path for the prep workspace path.
- `heed/UI/TaskAnalysisSectionView.swift`
  Keep the `Prepare context` trigger, but route it into the new prep controller.
- `heed/Analysis/OpenAIResponsesClient.swift`
  Share request-building pieces with the streaming path.
- `heed/Analysis/TaskAnalysisFixtureCompiler.swift`
  Keep current pass-1 fixture behavior untouched unless a shared helper extraction is needed.
- `heedTests/WorkspaceShellTests.swift`
  Assert the shell observes the prep controller and shows the expected action layout.
- `heedUITests/heedUITests.swift`
  Replace the old static-panel assertions with prep-workspace assertions.
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`

### Likely Retire Or Shrink

- `heed/Analysis/TaskContextController.swift`
- `heed/Analysis/TaskContextModels.swift`
- `heed/UI/TaskContextPanelPresentation.swift`
- `heed/UI/TaskContextPanelView.swift`

Retire these only after the new prep flow is green and all references are removed.

## Validation Steps

### Build And Tests

- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`
- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test`

### Manual Checks

- Record a short demo session and compile tasks.
- Click `Prepare context` and confirm the left chat plus right context workspace appears.
- Confirm the first assistant reply streams into the chat instead of appearing all at once.
- Send one user reply and confirm the next assistant turn streams too.
- Confirm the right context panel updates only after each assistant turn completes.
- Confirm the assistant can suggest readiness before spawning.
- Confirm `spawn_agent` is blocked until the user explicitly approves.
- Confirm the transcript tool reads only from the selected session.
- Switch sessions during a streamed turn and confirm stale text does not appear in the new workspace.

### Failure Checks

- Remove the API key and confirm the prep workspace shows a clear setup error.
- Interrupt the network and confirm the failed turn stays retryable without losing prior chat history.
- Force a malformed stream event in tests and confirm the parser reports failure cleanly.

## Observable Acceptance Criteria

- `Prepare context` opens a split task-prep workspace instead of the old static right-side summary.
- The left workspace shows streamed GPT-5.4 chat replies.
- The right workspace shows a stable structured context brief that updates after completed turns.
- The assistant can suggest “we have enough context” without spawning automatically.
- The model can call `get_meeting_transcript`, but that tool is read-only and scoped to the selected session.
- The model cannot call `spawn_agent` successfully until the user gives explicit approval.
- Prep state resets when the user switches sessions or prepares a different task.

## Progress

- 2026-04-20: Approved the design spec in `docs/superpowers/specs/2026-04-20-task-prep-chat-workspace-design.md`.
- 2026-04-20: Wrote this active execution plan.
- 2026-04-20: Completed Task 1 by adding the new prep domain model, the minimal controller and service seam, and the first streaming-turn controller test.

## Surprises & Discoveries

- 2026-04-20: The existing code already has a clean pass-2 seam, but it is built around a one-shot summary controller rather than a turn-based chat controller.
- 2026-04-20: The current UI test already covers `Prepare context`, which gives us a stable path to upgrade instead of creating a new end-to-end test from scratch.
- 2026-04-20: Official OpenAI docs confirm that the Responses API supports streaming and function calling, which fits the approved prep-chat design. Sources: https://platform.openai.com/docs/guides/streaming-responses and https://platform.openai.com/docs/api-reference/responses/retrieve

## Decision Log

- 2026-04-20: Use a new `TaskPrepController` instead of stretching `TaskContextController` into a chat owner, because the old controller models one request while the new flow models many turns.
- 2026-04-20: Keep pass 1 intact and change only the `Prepare context` path for this plan.
- 2026-04-20: Keep prep state in memory only to avoid persistence and migration work.
- 2026-04-20: Enforce spawn approval twice: once in the prompt and once in app code.

## Outcomes & Retrospective

- 2026-04-20: Task 1 is complete; the prep domain model and controller seam now exist, but later prep-chat tasks are still in flight.

## Task 1: Lock The New Prep Domain Model

**Files:**
- Create: `heed/Analysis/TaskPrepModels.swift`
- Modify: `heed/Analysis/TaskContextModels.swift` or remove references later
- Test: `heedTests/TaskPrepControllerTests.swift`

- [x] **Step 1: Write the failing controller test for the first streamed turn**

```swift
@Test func firstPrepareContextRequestStartsStreamingAssistantTurn() async throws {
    let service = ControlledTaskPrepConversationService()
    let controller = await MainActor.run {
        TaskPrepController(service: service)
    }

    await MainActor.run {
        controller.start(task: sampleTask(), in: sampleSession())
    }

    #expect(await service.pendingTurnCount() == 1)
    let state = await MainActor.run { controller.viewState }
    #expect(state.messages.count == 1)
    #expect(state.messages[0].role == .assistant)
    #expect(state.messages[0].text.isEmpty)
    #expect(state.turnState == .streaming)
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests/TaskPrepControllerTests/firstPrepareContextRequestStartsStreamingAssistantTurn`

Expected: FAIL because `TaskPrepController`, `ControlledTaskPrepConversationService`, and `viewState` do not exist yet.

- [x] **Step 3: Write the minimal shared task-prep types**

```swift
enum TaskPrepMessageRole: Sendable {
    case user
    case assistant
    case system
}

struct TaskPrepMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: TaskPrepMessageRole
    var text: String
    var isInterrupted: Bool = false
}

struct TaskPrepContextDraft: Equatable, Sendable {
    var summary: String = ""
    var goal: String = ""
    var constraints: [String] = []
    var acceptanceCriteria: [String] = []
    var risks: [String] = []
    var openQuestions: [String] = []
    var evidence: [TaskPrepEvidence] = []
    var readyToSpawn: Bool = false
}

enum TaskPrepTurnState: Equatable, Sendable {
    case idle
    case streaming
    case failed(String)
    case completed
}
```

- [x] **Step 4: Run the focused test again**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests/TaskPrepControllerTests/firstPrepareContextRequestStartsStreamingAssistantTurn`

Expected: FAIL later because the controller still does not exist.

- [x] **Step 5: Commit**

```bash
git add heed/Analysis/TaskPrepModels.swift heedTests/TaskPrepControllerTests.swift
git commit -m "feat: add task prep domain models" -m "start the new prep chat flow with shared message and context draft types"
```

## Task 2: Add Streaming Service And Parser Support

**Files:**
- Create: `heed/Analysis/OpenAIResponsesStream.swift`
- Create: `heed/Analysis/TaskPrepConversationService.swift`
- Modify: `heed/Analysis/OpenAIResponsesClient.swift`
- Test: `heedTests/OpenAIResponsesStreamTests.swift`
- Test: `heedTests/OpenAITaskCompilersTests.swift`

- [ ] **Step 1: Write the failing stream-parser test**

```swift
@Test func parserEmitsTextAndFunctionArgumentDeltasInOrder() throws {
    let payload = [
        "event: response.output_text.delta",
        "data: {\"delta\":\"Hello\"}",
        "",
        "event: response.function_call_arguments.delta",
        "data: {\"delta\":\"{\\\"approval\\\":true}\"}",
        ""
    ].joined(separator: "\n")

    let events = try OpenAIResponsesStreamParser().parse(payload)

    #expect(events == [
        .textDelta("Hello"),
        .functionArgumentsDelta("{\"approval\":true}")
    ])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests/OpenAIResponsesStreamTests/parserEmitsTextAndFunctionArgumentDeltasInOrder`

Expected: FAIL because the parser types do not exist.

- [ ] **Step 3: Add the minimal stream parser and prep service protocol**

```swift
enum OpenAIStreamEvent: Equatable {
    case textDelta(String)
    case functionArgumentsDelta(String)
    case completed
    case failed(String)
}

protocol TaskPrepConversationServicing: Sendable {
    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error>
}

enum TaskPrepConversationEvent: Sendable {
    case assistantTextDelta(String)
    case contextDraft(TaskPrepContextDraft)
    case transcriptToolRequest(TaskPrepTranscriptRequest)
    case spawnAgentRequest(TaskPrepSpawnRequest)
    case completed
}
```

- [ ] **Step 4: Refactor request building so the streaming path can reuse it**

```swift
extension OpenAIResponsesClient {
    func makeJSONRequestBody(
        model: String,
        input: [[String: Any]],
        tools: [[String: Any]],
        stream: Bool
    ) throws -> Data {
        // shared request body builder for one-shot and streamed calls
    }
}

struct OpenAITaskPrepConversationService: TaskPrepConversationServicing {
    private let client: OpenAIResponsesClient

    init(client: OpenAIResponsesClient = OpenAIResponsesClient(model: "gpt-5.4")) {
        self.client = client
    }
}
```

- [ ] **Step 5: Run the focused parser tests**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests/OpenAIResponsesStreamTests`

Expected: PASS for the parser tests. Existing compiler tests may still fail until later tasks wire the service fully.

- [ ] **Step 6: Commit**

```bash
git add heed/Analysis/OpenAIResponsesClient.swift heed/Analysis/OpenAIResponsesStream.swift heed/Analysis/TaskPrepConversationService.swift heedTests/OpenAIResponsesStreamTests.swift heedTests/OpenAITaskCompilersTests.swift
git commit -m "feat: add streaming support for task prep turns" -m "parse streamed response events and expose a service seam for prep chat"
```

## Task 3: Build The Prep Controller With Guardrails

**Files:**
- Create: `heed/Analysis/TaskPrepController.swift`
- Test: `heedTests/TaskPrepControllerTests.swift`

- [ ] **Step 1: Write failing tests for streamed assembly, stable-draft promotion, transcript reads, and spawn blocking**

```swift
@Test func spawnRequestIsBlockedBeforeExplicitApproval() async throws {
    let service = ImmediatePrepService(events: [
        .assistantTextDelta("I can spawn now."),
        .spawnAgentRequest(.init(reason: "ready"))
    ])
    let controller = await MainActor.run { TaskPrepController(service: service) }

    await MainActor.run {
        controller.start(task: sampleTask(), in: sampleSession())
    }

    let state = try await waitForPrepState(controller) { $0.turnState == .completed }
    #expect(state.spawnStatus == .blockedWaitingForApproval)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests/TaskPrepControllerTests`

Expected: FAIL because the controller logic does not exist yet.

- [ ] **Step 3: Implement the minimal controller**

```swift
@MainActor
final class TaskPrepController: ObservableObject {
    @Published private(set) var viewState = TaskPrepViewState()

    func start(task: CompiledTask, in session: TranscriptSession) {
        // seed task, clear old state, create empty assistant message, and begin first streamed turn
    }

    func sendUserMessage(_ text: String) {
        // append the user message and begin the next streamed turn
    }

    func approveSpawn() {
        // set a flag that allows the next spawn tool request to succeed
    }

    func reset() {
        // cancel in-flight work and clear temporary state
    }
}
```

- [ ] **Step 4: Add transcript-tool and spawn-tool handling**

```swift
private func handle(_ event: TaskPrepConversationEvent, session: TranscriptSession) {
    switch event {
    case .assistantTextDelta(let delta):
        appendAssistantDelta(delta)
    case .contextDraft(let draft):
        pendingDraft = draft
    case .transcriptToolRequest(let request):
        service.submitTranscript(scope: request, session: session)
    case .spawnAgentRequest(let request):
        processSpawnRequest(request)
    case .completed:
        promotePendingDraft()
    }
}
```

- [ ] **Step 5: Run controller tests**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests/TaskPrepControllerTests`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add heed/Analysis/TaskPrepController.swift heedTests/TaskPrepControllerTests.swift
git commit -m "feat: add task prep controller" -m "manage streamed prep turns, live context drafts, and spawn guardrails"
```

## Task 4: Replace The Old Pass-2 UI With The Prep Workspace

**Files:**
- Create: `heed/UI/TaskPrepWorkspaceView.swift`
- Create: `heed/UI/TaskPrepChatView.swift`
- Create: `heed/UI/TaskPrepContextPanelView.swift`
- Modify: `heed/UI/WorkspaceShell.swift`
- Modify: `heed/UI/TaskAnalysisSectionView.swift`
- Modify: `heed/ContentView.swift`
- Test: `heedTests/WorkspaceShellTests.swift`

- [ ] **Step 1: Write failing shell tests for controller observation and workspace visibility**

```swift
@Test @MainActor
func shellShowsTaskPrepWorkspaceWhenASelectedTaskIsActive() {
    let shell = makeShellWithPrepState(.active)
    let labels = Mirror(reflecting: shell).children.compactMap(\.label)

    #expect(labels.contains("_taskPrepController"))
    #expect(shell.isTaskPrepWorkspaceVisible == true)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests/WorkspaceShellTests`

Expected: FAIL because the shell does not know about the prep controller.

- [ ] **Step 3: Implement the new workspace views**

```swift
struct TaskPrepWorkspaceView: View {
    @ObservedObject var controller: TaskPrepController

    var body: some View {
        HStack(spacing: 0) {
            TaskPrepChatView(controller: controller)
                .frame(maxWidth: .infinity)

            TaskPrepContextPanelView(controller: controller)
                .frame(width: 340)
        }
    }
}
```

- [ ] **Step 4: Wire `Prepare context` into the prep controller and swap the shell layout**

```swift
onPrepareContext: {
    guard let displayedSession else { return }
    taskPrepController.start(task: task, in: displayedSession)
}
```

```swift
if isTaskPrepWorkspaceVisible {
    TaskPrepWorkspaceView(controller: taskPrepController)
        .transition(.move(edge: .trailing).combined(with: .opacity))
}
```

- [ ] **Step 5: Run shell tests**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests/WorkspaceShellTests`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add heed/ContentView.swift heed/UI/WorkspaceShell.swift heed/UI/TaskAnalysisSectionView.swift heed/UI/TaskPrepWorkspaceView.swift heed/UI/TaskPrepChatView.swift heed/UI/TaskPrepContextPanelView.swift heedTests/WorkspaceShellTests.swift
git commit -m "feat: add task prep workspace UI" -m "replace the old pass two panel with a streamed chat and live context layout"
```

## Task 5: Add Fixture Streaming For UI Tests

**Files:**
- Modify: `heed/ContentView.swift`
- Modify: `heed/Analysis/TaskPrepConversationService.swift`
- Modify: `heedUITests/heedUITests.swift`

- [ ] **Step 1: Write the failing UI test expectations for streamed prep chat**

```swift
let prepareContextButton = app.buttons["task-row-prepare-context-verify-audio-paths"]
prepareContextButton.click()

XCTAssertTrue(app.textViews["task-prep-chat-thread"].waitForExistence(timeout: uiTimeout))
XCTAssertTrue(app.staticTexts["I think we have enough context to proceed."].waitForExistence(timeout: uiTimeout))
XCTAssertTrue(app.staticTexts["Acceptance criteria"].exists)
```

- [ ] **Step 2: Run the UI test to verify it fails**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedUITests/heedUITests/testCompileTasksFlowAppearsInlineAfterRecordingStops`

Expected: FAIL because the prep workspace and stream fixture are not complete yet.

- [ ] **Step 3: Add a deterministic fixture stream**

```swift
if processInfo.arguments.contains("--heed-ui-test") {
    service = TaskPrepFixtureConversationService(processInfo: processInfo)
} else {
    service = OpenAITaskPrepConversationService()
}
```

```swift
struct TaskPrepFixtureConversationService: TaskPrepConversationServicing {
    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.assistantTextDelta("I think we have enough context to proceed. "))
            continuation.yield(.assistantTextDelta("Do you want me to spawn the agent now?"))
            continuation.yield(.contextDraft(.fixtureReady))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}
```

- [ ] **Step 4: Run the focused UI test again**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedUITests/heedUITests/testCompileTasksFlowAppearsInlineAfterRecordingStops`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add heed/ContentView.swift heed/Analysis/TaskPrepConversationService.swift heedUITests/heedUITests.swift
git commit -m "test: add task prep streaming fixtures" -m "make the new prep workspace deterministic in UI test mode"
```

## Task 6: Update Docs And Remove Old Pass-2 Surface

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/FRONTEND.md`
- Modify: `docs/RELIABILITY.md`
- Modify: `docs/SECURITY.md`
- Modify or delete: `heed/Analysis/TaskContextController.swift`
- Modify or delete: `heed/Analysis/TaskContextModels.swift`
- Modify or delete: `heed/UI/TaskContextPanelPresentation.swift`
- Modify or delete: `heed/UI/TaskContextPanelView.swift`

- [ ] **Step 1: Write the failing cleanup check as a build step**

Run: `rg -n "TaskContextController|TaskContextPanelView|TaskContextPanelPresentation" heed heedTests heedUITests`

Expected: existing matches that should shrink to zero or to compatibility-only references by the end of this task.

- [ ] **Step 2: Update docs to reflect the shipped prep workspace**

```md
- `Prepare context` now opens a streamed prep chat on the left and a live context brief on the right.
- The prep flow can suggest readiness, but it still requires explicit user approval before `spawn_agent`.
- The prep model may read the selected transcript through a read-only tool.
```

- [ ] **Step 3: Remove or retire the old pass-2 files once nothing references them**

```bash
git rm heed/Analysis/TaskContextController.swift heed/Analysis/TaskContextModels.swift heed/UI/TaskContextPanelPresentation.swift heed/UI/TaskContextPanelView.swift
rg -n "TaskContextController|TaskContextPanelView|TaskContextPanelPresentation" heed heedTests heedUITests
```

- [ ] **Step 4: Run the full project test suite**

Run: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add docs/ARCHITECTURE.md docs/FRONTEND.md docs/RELIABILITY.md docs/SECURITY.md heed/Analysis/TaskContextController.swift heed/Analysis/TaskContextModels.swift heed/UI/TaskContextPanelPresentation.swift heed/UI/TaskContextPanelView.swift
git commit -m "docs: update task prep workspace behavior" -m "document the streamed prep chat and retire the old static pass two panel"
```
