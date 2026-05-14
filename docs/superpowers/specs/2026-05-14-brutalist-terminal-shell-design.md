# Brutalist Terminal Shell Design

Date: 2026-05-14

## Goal

Revamp Heed into a brutalist, terminal-first macOS app shell.

The app should feel like a focused IDE [integrated development environment, an app where developers edit code, run terminals, and inspect project state]. The primary color is black. Borders use white at about 60% opacity.

The new center of the app is a tabbed terminal workspace. A terminal is a text interface for running commands. Each terminal belongs to a selected project and branch. A branch is a separate line of work in Git.

## Scope

This design covers the app shell only.

It includes:

- A brutalist black visual system.
- A top nav bar.
- A left project and branch sidebar.
- Branch-scoped side tabs.
- A center terminal tab workspace.
- A right changed-files pane.
- A path for keeping existing recording, transcript, task compile, and task prep behavior available inside the new shell.

## Non-Goals

This does not add real Git branch management yet.

This does not add real multi-project workspace persistence [saving workspace state across app launches].

This does not change transcript storage.

This does not change permissions, entitlements [signed app capability flags], API key storage, or OpenAI behavior.

This does not make the right pane a full code editor. It shows changed files and readable change summaries, not raw code editing.

## Visual Direction

The UI should be stark and useful.

- Background: black.
- Panels: black or near black.
- Borders: white at 60% opacity.
- Secondary dividers: white at 30% opacity.
- Text: white, with dimmed white for secondary labels.
- Type: mostly monospaced.
- Corners: square or almost square.
- Decoration: none.

This should feel like a terminal and source-control desk, not a marketing app.

## Top Nav

The top nav runs across the full window.

It contains:

- Sidebar minimize icon.
- Center search bar.
- `Open IDE` button with a dropdown.
- Settings button.

The top nav uses hard borders. It replaces the current floating sidebar toggle.

Search can start as visual-only. If search is not implemented in the first pass, it should be disabled or inert in a way that does not imply broken behavior.

`Open IDE` can start as a menu stub [a visible control with limited first behavior]. It should be wired later to open the selected project in the user's IDE.

## Left Sidebar

The sidebar lists:

```text
tasks
new session
--
project name
    branch name
        terminal 1
        terminal 2
        unstaged changes
        task prep
    branch name
        terminal 1
        changes
project name
    branch name
```

The sidebar should support nested branch side tabs. This means each branch can show its own children, like terminals and changes.

The selected project, branch, and tab should be visually obvious through border, inverse fill, or left accent.

For v1, project and branch data can be fixture UI state [temporary local sample data used to build the interface] until real project discovery is designed.

## Center Terminal Workspace

The center pane is the main workspace.

It shows terminal tabs for the selected project and branch.

Example tabs:

- `heed / ui-revamp / terminal 1`
- `terminal 2`
- `task prep`
- `+`

The current active terminal fills the center.

The terminal should use a black background, white text, and monospaced type. It can start as a shell view mock if the current terminal integration is not ready to support multiple sessions.

The existing task-prep terminal should inform this design. Do not move process launching logic into SwiftUI views.

## Branch Side Tabs

Each branch owns its side tabs.

Expected side tabs:

- Terminals.
- Unstaged changes.
- Task prep.
- Tasks.

The side tabs can appear nested in the sidebar first. A later pass can add a small vertical rail beside the terminal if the nested sidebar becomes crowded.

This is like a workbench where each branch has its own set of drawers. Switching branches changes the drawers you see.

## Right Changed-Files Pane

The right pane shows branch-specific changed files.

It includes:

- A header like `UNSTAGED CHANGES`.
- A changed file list.
- A readable summary for the selected file.

It should not show a full code editor yet.

It may show simple diff-like lines [lines marked as added or removed] as a visual summary. The goal is to help the user understand the current work, not edit code directly.

## Existing Heed Features

The current recording and transcript flow must stay available.

Initial mapping:

- `new session` starts or focuses the meeting transcript flow.
- `tasks` opens the compiled task list for the selected transcript or branch context.
- `task prep` opens the existing task-prep workspace for a selected task.
- The record action should remain easy to find while a transcript session is active.

The redesign should not let `ContentView` become the control center. The shell can route state, but capture, transcription, persistence, and task prep stay in their existing modules.

## Architecture

Create or refactor SwiftUI views around these roles:

- `WorkspaceShell`: root shell composition.
- `TopNavView`: sidebar toggle, search, Open IDE, settings.
- `ProjectSidebarView`: tasks, new session, projects, branches, branch tabs.
- `TerminalTabsView`: selected branch terminal tabs.
- `BranchTerminalPane`: terminal display area.
- `ChangedFilesPane`: changed file list and summary.

Use value state [plain stored data] for mock project, branch, and terminal selection in the first UI pass.

Do not add persistence until a separate plan describes schema [data shape], migration [how old saved data becomes new saved data], and rollback path.

## Data Flow

The selected sidebar item drives the center pane and right pane.

Flow:

1. User selects a project branch.
2. Sidebar marks that branch active.
3. Center shows terminal tabs for that branch.
4. Right pane shows changed files for that branch.
5. If the user selects `task prep`, the center uses the existing prep workspace path.

For the first implementation, branch and change data can be local fixtures. Later, a Git service can replace fixtures.

## Error Handling

The first UI pass should avoid fake failures.

If a feature is not wired yet:

- Show a disabled state.
- Or show a short empty state.
- Do not pretend real branch or file data exists when it is static.

Existing recording, permission, transcript, API key, and task-prep errors should keep their current controller-owned behavior.

## Testing

Add focused tests for:

- Sidebar visibility and selection state.
- Top nav action presence.
- Terminal workspace visibility.
- Right changed-files pane visibility.
- Existing UI-test identifiers that must remain stable, such as `record-button`, `compile-tasks`, and `task-prep-workspace`.

Manual visual checks should cover:

- 1280 by 840 default window.
- Narrower window behavior.
- Long project names.
- Long branch names.
- Empty changed-file state.

## Acceptance Criteria

The redesign is acceptable when:

- The first screen clearly reads as a brutalist terminal-first IDE shell.
- The sidebar matches the requested structure.
- The top nav includes the requested controls.
- The center uses terminal tabs as the primary surface.
- The right pane shows changed files and summaries.
- Existing recording and task-prep flows are still reachable.
- No persistence, permission, entitlement, or saved-data format changes are introduced.

## Open Questions

- Should `Open IDE` target Xcode first, the user's default editor, or a configurable IDE list?
- Should the record action live in the top nav, in the `new session` view, or as a fixed bottom control only during transcript sessions?
- Should the right pane later support staging files [choosing which changes to include in a commit], or stay read-only?
