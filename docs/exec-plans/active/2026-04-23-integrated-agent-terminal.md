# Integrated Agent Terminal

## Goal

Replace the Terminal.app spawn handoff with an integrated terminal inside the task-prep workspace. After the user clicks `Approve spawn`, the left chat pane should become a real interactive Codex terminal, seeded with compressed task context.

## Scope

- Add an in-app terminal mode to the task-prep workspace.
- Add a PTY-backed [pseudo-terminal-backed, meaning a real terminal interface for a child process] Codex session launcher.
- Change spawn approval so it starts the in-app terminal instead of driving Terminal.app on the happy path.
- Compress the handoff prompt instead of copying the sidepanel or full transcript verbatim.
- Update unit tests and docs for the new integrated terminal flow.
- Keep prep state and terminal output in memory only.

## Non-Goals

- Persist terminal logs, prep chat, prep briefs, or spawn history.
- Change the saved transcript session format.
- Add multiple concurrent agent terminals.
- Add repo selection or workspace management.
- Remove the existing approval gate.
- Add a full transcript tool for Codex in this step.

## Risks

- PTY handling can be brittle because terminal apps expect precise input, output, and resize behavior.
- App Sandbox [a macOS restriction layer] blocks the integrated terminal from launching Homebrew/NPM `codex` reliably. The current developer build disables App Sandbox so the in-app PTY can run local tools in the repo.
- A terminal view can become hard to use if keyboard focus, text selection, and scrolling are not handled carefully.
- The old Terminal.app automation code may still be needed as a fallback until the embedded path is stable.
- Sending too little context could make the spawned Codex session weaker than the current full transcript handoff.

## Open Questions

- Which PTY implementation should the app use: a small local wrapper around Darwin APIs [macOS system calls], or a dependency such as SwiftTerm [a Swift terminal emulator library]?
- Should the first integrated version keep Terminal.app launch as a debug fallback behind code, or remove it from the user path immediately?
- Resolved for this slice: the default launcher starts in the checked-out repo root derived from the source file path. A later packaged app still needs a user-selected project folder flow.

## Validation Steps

- Run `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/TaskPrepAgentHandoffTests`.
- Run `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/TaskPrepControllerTests`.
- Run `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/TaskPrepPresentationTests`.
- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`.
- Manual check:
  Open `Prepare context`, wait for a spawn request, click `Approve spawn`, and confirm the left pane becomes a terminal running Codex.
- Manual failure check:
  Temporarily run without `codex` on `PATH` and confirm the terminal pane shows a clear retryable error.

## Observable Acceptance Criteria

- The `Approve spawn` button no longer opens Terminal.app on the normal path.
- The left prep pane switches from chat to terminal after approval.
- The terminal is interactive and accepts user input.
- Codex starts inside the terminal.
- The initial prompt is compressed and does not paste the full transcript by default.
- The right-side brief remains visible during the terminal session.
- Closing the prep workspace stops the terminal session and clears in-memory output.
- Tests cover prompt compression, controller state, terminal launch success, and terminal launch failure.

## Progress

- 2026-04-23: User clarified that spawn should turn the chat pane into a literal integrated terminal, inspired by a workbench-style UI.
- 2026-04-23: Drafted the product design in `docs/superpowers/specs/2026-04-23-integrated-agent-terminal-design.md`.
- 2026-04-23: Started this active ExecPlan because the change crosses UI, process launch, prompt construction, and security boundaries.
- 2026-04-23: Added the controller/model seam for terminal mode: terminal status, terminal output, injectable terminal launcher, launch success and failure state, exit handling, and reset teardown.
- 2026-04-23: Updated `TaskPrepAgentHandoffPromptBuilder` so it builds a compressed handoff, keeps cited evidence snippets, and omits the full transcript by default.
- 2026-04-23: Added `TaskPrepTerminalView` and switched the left prep pane from chat to terminal after spawn approval.
- 2026-04-23: Replaced the first process-pipe launcher with a PTY-backed launcher using `openpty`, so `codex` sees a real terminal.
- 2026-04-23: Changed prompt injection to bracketed paste so multiline compressed context is delivered as one pasted block instead of many submitted terminal lines.
- 2026-04-24: Fixed the observed `env: codex: Operation not permitted` failure by removing App Sandbox from the developer app target and checked-in entitlements.
- 2026-04-24: Verified `xcodebuild build` succeeds and `xcodebuild -showBuildSettings` reports `ENABLE_APP_SANDBOX = NO`.
- 2026-04-25: Added terminal output filtering for ANSI/CSI control sequences [terminal commands for cursor movement, color, and modes], cursor-position responses, and disabled PTY echo for the child terminal.
- 2026-04-25: Changed the integrated launcher to start `codex --model gpt-5.2-codex --no-alt-screen` with the compressed prompt as the prompt argument, avoiding a post-launch paste that could leave the pane stuck at `Starting Codex...` and avoiding unsupported newer model defaults from local Codex config.
- 2026-04-25: Fixed the terminal canvas layout so the AppKit text view tracks the pane width instead of wrapping output at one character per line.
- 2026-04-25: Set the PTY launch size to 120 columns by 40 rows so Codex formats output for a normal terminal width instead of a zero-width terminal.

## Surprises & Discoveries

- 2026-04-23: The current handoff prompt includes the full transcript. The new desired behavior is compressed context by default.
- 2026-04-23: There are already local uncommitted edits in Terminal launch and chat presentation files. Future implementation must preserve them.
- 2026-04-23: This slice keeps the old Terminal.app handoff initializer as a compatibility adapter, but the normal app wiring now uses the terminal session launcher.
- 2026-04-23: A sandboxed app launches child processes inside the same sandbox. Real testing showed `/usr/bin/env codex` failed with `Operation not permitted`, so the developer build now disables App Sandbox for the integrated terminal path.
- 2026-04-23: Sending a multiline prompt to an interactive terminal as raw text can submit partial lines. Bracketed paste is safer for the initial handoff.
- 2026-04-23: The visible `^[[200~` prompt dump happened because `codex` never started. The PTY echoed the pasted prompt after `/usr/bin/env` failed.
- 2026-04-25: Codex can emit control sequences before a full terminal renderer exists. The current app strips those sequences from visible text and answers cursor-position queries so the pane stays readable.
- 2026-04-25: Even bracketed paste can be fragile in an embedded terminal because the app may write before the TUI is ready to accept input. Passing the prompt through the supported Codex prompt argument removes that timing race.

## Decision Log

- 2026-04-23: Choose a real PTY-backed terminal over a fake terminal UI. Fake terminals look cheaper at first, but Codex and similar CLIs expect real terminal behavior.
- 2026-04-23: Keep the right-side brief visible while the terminal runs. It acts like a compact mission card beside the live work area.
- 2026-04-23: Do not paste the full transcript into Codex by default. Use compressed context first to avoid a context dump and reduce sensitive text exposure.
- 2026-04-25: The left pane should behave like a Conductor-style embedded terminal. It renders one terminal canvas and sends keyboard input directly to the PTY instead of showing a separate command row. ANSI rendering [terminal color and cursor control handling] can still be a follow-up.
- 2026-04-25: Answer cursor-position requests from terminal TUIs with a simple cursor report so Codex does not time out waiting for `ESC [ 6 n` [a terminal command that asks where the cursor is].
- 2026-04-25: Until the app has a full terminal emulator [software that fully interprets terminal drawing commands], sanitize control sequences from display text instead of showing raw codes such as `^[[200~` or `[?2004h`.
- 2026-04-25: Use `--no-alt-screen` for the embedded Codex process so the simple text canvas can keep visible scrollback instead of trying to mirror an alternate terminal screen.

## Implementation Plan

### Task 1: Add Terminal State To Prep Models

Files:

- Modify `heed/Analysis/TaskPrepModels.swift`
- Modify `heedTests/TaskPrepControllerTests.swift`

Steps:

1. Add `TaskPrepTerminalStatus` with states for idle, launching, running, failed, and ended.
2. Add terminal fields to `TaskPrepViewState`.
3. Add a controller test that expects terminal status to move to launching after approved spawn.

Expected shape:

```swift
enum TaskPrepTerminalStatus: Equatable, Sendable {
    case idle
    case launching
    case running
    case failed(String)
    case ended(Int32?)
}
```

### Task 2: Compress The Spawn Prompt

Files:

- Modify `heed/Analysis/TaskPrepAgentHandoff.swift`
- Modify `heedTests/TaskPrepAgentHandoffTests.swift`

Steps:

1. Add a prompt-builder test that feeds transcript segments containing unique full-transcript text.
2. Expect the compressed prompt to include task title, goal, constraints, acceptance, open questions, and evidence.
3. Expect the compressed prompt not to include unrelated transcript-only text.
4. Replace the current full-transcript section with a compressed handoff section.

Expected assertion style:

```swift
#expect(prompt.contains("Compressed handoff"))
#expect(prompt.contains("Fix spawn handoff"))
#expect(prompt.contains("Carry every important detail into the handoff."))
#expect(!prompt.contains("Unrelated transcript detail that should not be pasted."))
```

### Task 3: Add A Terminal Session Protocol

Files:

- Create `heed/Analysis/TaskPrepTerminalSession.swift`
- Modify `heedTests/TaskPrepControllerTests.swift`

Steps:

1. Add `TaskPrepTerminalSessionLaunching`.
2. Add a fake launcher for controller tests.
3. Change `TaskPrepController` to depend on the terminal launcher.

Expected shape:

```swift
@MainActor
protocol TaskPrepTerminalSessionLaunching {
    func launch(prompt: String) throws -> TaskPrepTerminalSessionHandle
}

@MainActor
protocol TaskPrepTerminalSessionHandle: AnyObject {
    func write(_ input: String)
    func stop()
}
```

### Task 4: Wire Approval Into Terminal Mode

Files:

- Modify `heed/Analysis/TaskPrepController.swift`
- Modify `heedTests/TaskPrepControllerTests.swift`

Steps:

1. Replace the happy-path call to `TaskPrepTerminalHandoffLauncher` with the new terminal launcher.
2. Store the active terminal handle.
3. Set `terminalStatus` to `.running` after launch succeeds.
4. Set `terminalStatus` to `.failed(message)` if launch throws.
5. Stop the terminal handle in `reset()`.

### Task 5: Build The Terminal View

Files:

- Create `heed/UI/TaskPrepTerminalView.swift`
- Modify `heed/UI/TaskPrepWorkspaceView.swift`
- Modify `heedTests/TaskPrepPresentationTests.swift`

Steps:

1. Add a terminal view that renders output from controller state.
2. Add an input area or representable terminal surface for keyboard input.
3. Switch `TaskPrepWorkspaceView` so the left pane renders chat before spawn and terminal after spawn.
4. Add accessibility identifiers:
   - `task-prep-chat`
   - `task-prep-terminal`
   - `task-prep-terminal-status`

### Task 6: Implement The PTY Launcher

Files:

- Modify `heed/Analysis/TaskPrepTerminalSession.swift`
- Add focused tests if the PTY layer can be tested without launching real Codex.

Steps:

1. Use `Process` plus a PTY file descriptor [a small integer handle for an open system resource] to start `codex`.
2. Set the working directory to the project path used by Heed during development.
3. Write the compressed prompt followed by Return after launch.
4. Stream terminal output back into controller state.
5. Close file descriptors on exit.

### Task 7: Update Docs And Remove Terminal.app Happy Path

Files:

- Modify `README.md`
- Modify `docs/ARCHITECTURE.md`
- Modify `docs/FRONTEND.md`
- Modify `docs/RELIABILITY.md`
- Modify `docs/SECURITY.md`
- Update or complete `docs/exec-plans/active/2026-04-21-terminal-spawn-handoff.md`

Steps:

1. Document that spawn uses the integrated terminal.
2. Document that Terminal.app automation is no longer the normal path.
3. Document that prep and terminal state remain memory-only.
4. Document that the full transcript is not pasted by default.

## Outcomes & Retrospective

- 2026-04-23: In progress. Core prompt, controller, PTY launcher, terminal pane, and developer-build sandbox posture are implemented. Real-Codex smoke checks still remain.
