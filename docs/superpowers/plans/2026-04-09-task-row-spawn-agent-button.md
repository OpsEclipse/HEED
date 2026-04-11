# Task Row Spawn Agent Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compact `Spawn agent` button to each compiled task row so users can trigger a task-specific agent action from the inline task review UI.

**Architecture:** Keep the new action scoped to task rows inside the existing task analysis section. Reuse the current floating transport visual language by extracting a shared button style with size variants, then wire the new row action through `TaskAnalysisController` so the row view stays presentational [focused on display, not business logic].

**Tech Stack:** SwiftUI, Swift Testing, XCTest UI tests

---

### Task 1: Define the row action surface and style reuse

**Files:**
- Modify: `heed/UI/FloatingTransportView.swift`
- Modify: `heed/UI/TaskAnalysisSectionView.swift`
- Test: `heedTests/WorkspaceShellTests.swift`

- [ ] **Step 1: Write the failing test**

Add a view-level assertion in `heedTests/WorkspaceShellTests.swift` that proves the task-analysis shell now keeps a spawn-agent path in the row UI surface. Use reflection only if needed for shell ownership, but prefer a direct small view test if an existing pattern is easy to follow.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/WorkspaceShellTests`
Expected: FAIL because no spawn-agent action or reusable compact transport style exists yet.

- [ ] **Step 3: Write minimal implementation**

Extract the current transport button styling in `heed/UI/FloatingTransportView.swift` into a shared button style or helper that supports at least two sizes:
- regular: current record button sizing
- compact: smaller font, height, and horizontal padding for task rows

Then update `TaskRowView` in `heed/UI/TaskAnalysisSectionView.swift` so each task row can render:
- existing checkbox
- task title and metadata
- a right-aligned compact `Spawn agent` button
- a trailing chevron icon like `chevron.right`

Keep `Record` visually primary. The compact row action should feel related, but smaller and quieter.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/WorkspaceShellTests`
Expected: PASS


### Task 2: Wire the action through task analysis state

**Files:**
- Modify: `heed/Analysis/TaskAnalysisController.swift`
- Modify: `heed/UI/TaskAnalysisSectionView.swift`
- Test: `heedTests/heedTests.swift`

- [ ] **Step 1: Write the failing test**

Add a unit test in `heedTests/heedTests.swift` that creates a compiled task-analysis state, triggers the new spawn-agent row action, and verifies the controller exposes enough observable state for the UI to react. A minimal first slice can assert that the tapped task ID is recorded as the most recent spawn request.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/heedTests`
Expected: FAIL because the controller does not yet expose or update spawn-agent request state.

- [ ] **Step 3: Write minimal implementation**

Add a focused controller surface for the new action, such as:
- a published `lastSpawnedTaskID` or similarly clear property
- a `handleSpawnAgent(for:)` entry point

Thread that action into `TaskAnalysisSectionView.swift` so `TaskRowView` stays dumb [simple and display-only] and the controller owns the action handling.

Do not add real agent-launch infrastructure in this change. This feature is just the UI action surface plus controller state for now.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/heedTests`
Expected: PASS


### Task 3: Cover the end-to-end UI behavior

**Files:**
- Modify: `heedUITests/heedUITests.swift`
- Modify: `heed/UI/TaskAnalysisSectionView.swift` (only if accessibility hooks are still missing)
- Test: `heedUITests/heedUITests.swift`

- [ ] **Step 1: Write the failing test**

Extend the inline task-compilation UI test so it waits for the new row action and checks:
- the `Spawn agent` button exists for at least one compiled task row
- the button has a stable accessibility identifier, such as `task-row-spawn-agent-<task-id>`

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testCompileTasksFlowAppearsInlineAfterRecordingStops`
Expected: FAIL because the button is not present yet or lacks accessibility wiring.

- [ ] **Step 3: Write minimal implementation**

Add any missing accessibility identifiers in `TaskAnalysisSectionView.swift` and keep the new button discoverable in UI tests.

If there is room, make the row button disable briefly when tapped and expose a simple label change like `Spawning...` only if it can be tested cleanly without adding fake async complexity [extra complexity from pretending work is happening]. Otherwise keep this first pass to a stable clickable button.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testCompileTasksFlowAppearsInlineAfterRecordingStops`
Expected: PASS


### Task 4: Run focused verification

**Files:**
- Modify: none
- Test: `heedTests/WorkspaceShellTests.swift`
- Test: `heedTests/heedTests.swift`
- Test: `heedUITests/heedUITests.swift`

- [ ] **Step 1: Run the focused unit and UI checks**

Run: `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/WorkspaceShellTests -only-testing:heedTests/heedTests -only-testing:heedUITests/heedUITests/testCompileTasksFlowAppearsInlineAfterRecordingStops`
Expected: PASS

- [ ] **Step 2: Review changed files**

Confirm the final diff stays scoped to:
- shared transport-style reuse
- task row button UI
- controller action plumbing
- tests and accessibility hooks

- [ ] **Step 3: Note risks**

If no real spawn-agent backend exists yet, report clearly that this change adds the task-row affordance [a visible control that suggests an action] and controller hook, not a full agent workflow.
