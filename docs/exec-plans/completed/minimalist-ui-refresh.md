# Minimalist UI Refresh

## Goal

Refresh Heed into a calmer transcript-first macOS window. The shipped result is a sparse black canvas with a centered transcript column, a collapsible left sidebar, one floating record or stop button, and a quiet bottom utility rail.

## Scope

- Redesign the main window layout in [`heed/ContentView.swift`](../../../heed/ContentView.swift) and the supporting views under [`heed/UI/`](../../../heed/UI/).
- Replace the always-visible split layout with a transcript-first shell.
- Add a toggleable left sidebar for sessions.
- Move record or stop into a floating transport.
- Define the first shared design token layer in [`heed/UI/HeedTheme.swift`](../../../heed/UI/HeedTheme.swift).
- Update the docs that describe front-end behavior and visual direction.

## Non-Goals

- Changing capture, transcription, storage, or export logic
- Adding new persistence formats
- Adding cloud features or network services
- Building a full settings screen
- Rebranding the product with a new logo or marketing site

## Shipped File Shape

- [`heed/ContentView.swift`](../../../heed/ContentView.swift)
  Thin composition root for the app window.
- [`heed/UI/HeedTheme.swift`](../../../heed/UI/HeedTheme.swift)
  Shared tokens for color, spacing, type, and motion.
- [`heed/UI/WorkspaceShell.swift`](../../../heed/UI/WorkspaceShell.swift)
  High-level layout, sidebar state, utility rail, fullscreen handling, and floating transport placement.
- [`heed/UI/SessionSidebarView.swift`](../../../heed/UI/SessionSidebarView.swift)
  Sidebar content and session selection.
- [`heed/UI/TranscriptCanvasView.swift`](../../../heed/UI/TranscriptCanvasView.swift)
  Centered transcript column and empty state.
- [`heed/UI/FloatingTransportView.swift`](../../../heed/UI/FloatingTransportView.swift)
  Floating record or stop button.
- [`heed/UI/UtilityRailView.swift`](../../../heed/UI/UtilityRailView.swift)
  Quiet status line with copy and fullscreen actions.
- [`heed/UI/WindowAccessView.swift`](../../../heed/UI/WindowAccessView.swift)
  `NSWindow` bridge for fullscreen state and hidden window controls.
- [`heed/Support/TimeInterval+Heed.swift`](../../../heed/Support/TimeInterval+Heed.swift)
  Shared time formatting for the shell.

## Risks

- The quiet shell can hide secondary actions too well.
- The floating transport can block transcript reading or text selection if spacing drifts.
- A collapsed sidebar can make saved sessions harder to discover.
- The current shell only surfaces clipboard copy, so file export may feel missing even though the code still exists.
- macOS UI automation around this shell is still flaky.

## Validation Steps

- Build the app with `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`.
- Run the unit tests with `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests`.
- Verify the app opens into a transcript-first canvas with the sidebar collapsed by default.
- Verify the sidebar can open and close without breaking transcript scroll or selection.
- Verify the floating transport stays visible and usable in idle, recording, stopping, and error states.
- Verify the empty transcript state shows only the one prompt sentence.
- Verify the utility rail keeps status readable and exposes copy plus fullscreen.

## Observable Acceptance Criteria

- The main window feels transcript-first instead of split-pane-first.
- The sessions list is available from a left sidebar that can be shown or hidden.
- The primary record or stop action lives in one floating yellow button instead of a heavy header bar.
- The refresh keeps the current local transcription behavior and session review flow intact.
- The docs and the shipped layout describe the same product truth.

## Progress

- 2026-04-09: Created this `ExecPlan` before implementation started.
- 2026-04-09: Added `HeedTheme`, `WorkspaceShell`, `SessionSidebarView`, `TranscriptCanvasView`, `FloatingTransportView`, `UtilityRailView`, `WindowAccessView`, and `TimeInterval+Heed`.
- 2026-04-09: Replaced the old split-view shell with the new transcript-first layout.
- 2026-04-09: Updated UI coverage for the new shell, though local macOS UI automation is still somewhat flaky.
- 2026-04-09: Moved this plan to `completed` once the shipped layout and docs matched again.

## Decision Log

- 2026-04-09: Chose a transcript-first canvas so the product feels closer to a focused writing surface than an admin dashboard.
- 2026-04-09: Chose a collapsible left sidebar so session history stays available without permanently splitting the screen.
- 2026-04-09: Chose a docked sidebar instead of an overlay so it feels like part of the window shell.
- 2026-04-09: Chose to derive sidebar titles from the first non-empty transcript line until a real stored session title field exists.
- 2026-04-09: Chose a flat yellow floating button as the primary action so the record or stop state stays obvious with less chrome.
- 2026-04-09: Kept a quiet utility rail because status and fullscreen still mattered after the minimal pass.

## Outcomes & Retrospective

- The main shell overhaul shipped successfully.
- The app window now matches the transcript-first direction in layout and control placement.
- The biggest remaining UI gaps are discoverability, exact visual polish, and flaky macOS UI automation.
