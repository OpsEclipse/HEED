# Frontend

## Current UI Surface

The app still has one main macOS window today.

- App launch opens one window from [`../heed/heedApp.swift`](../heed/heedApp.swift).
- That window renders [`../heed/ContentView.swift`](../heed/ContentView.swift).
- The root view now renders a transcript-first shell with a centered transcript canvas.
- The sessions list is in a hidden-by-default left sidebar column with a compact tree-style treatment.
- The main record or stop action lives in one floating yellow button.
- The window opens at a fixed default size and hides the normal macOS title bar controls.
- The bottom utility rail shows quiet status text plus `Copy as text` and `Full screen` actions.

## Current Implemented States

- `idle`
  The app shows the transcript workspace and one empty-state prompt.
- `ready to record`
  The app can request recording on the next `Record` click.
- `recording`
  The timer runs and new `MIC` or `SYSTEM` rows stream into the transcript.
- `stopping`
  The app keeps the same screen while it flushes pending work.
- `error`
  The app shows inline recovery guidance or runtime errors. Partial transcripts stay visible.

## Refresh Status

The shell refresh described below is now mostly implemented in the app code. The remaining gaps are polish and test stability, not the main layout direction.

The current shell now uses:

- a centered transcript column
- a compact left sidebar column that reads like a file tree
- a muted bottom utility rail with text actions
- one empty-state prompt inside the transcript area
- a floating bottom-center yellow record or stop button

## Current Main Surfaces

### Transcript Canvas

This becomes the default visual focus.

- The canvas fills the window with a black background.
- The transcript sits in a centered reading column.
- Saved and live sessions use the same main reading surface.
- The transcript should still feel raw and direct, but less like a table.
- When there is no transcript yet, show only `Press record to begin the full transcript`.

### Sidebar

The sidebar remains important, but it becomes optional in the layout.

- It sits on the left edge of the window.
- It can be toggled on and off.
- It should feel like a compact file-tree panel that belongs to the shell, not a floating drawer.
- The first implementation should prefer the collapsed state when the user is focused on active transcription.
- It should list only session titles taken from the first transcript line.
- It should use narrow rows, small icons, and a left accent for the selected row, while keeping the shared app palette and type scale.

### Floating Transport

The main record or stop action should be one flat floating button.

- Preferred location: bottom center
- Fallback location: top right if transcript selection or readability suffers
- The button should stay compact
- Use a yellow fill close to the reference `Create` button
- Keep the corners square, with no visible border radius

### Utility Rail

The bottom rail is back in the shell, but it stays visually quiet.

- It sits flush with the bottom edge of the window.
- It shows compact status text like recording state and elapsed time.
- It keeps text-only actions on the right side.
- It currently exposes `Copy as text` and a fullscreen toggle.

## Current Interaction Pattern

1. App launches into the main transcript canvas.
2. The transcript surface gets the visual priority, not the sessions list.
3. The user can open the sidebar when they want session history or secondary actions.
4. Opening the sidebar shifts the transcript workspace to the right instead of covering it.
5. The user sees session titles only, without timestamps or badges in the sidebar.
6. Before recording starts, the main canvas shows only `Press record to begin the full transcript`.
7. The user starts recording from the floating yellow button.
8. Live transcript rows append into the centered column.
9. The user can copy transcript text or toggle fullscreen from the bottom-right utility rail.
10. The user stops recording from the same floating button.
11. The finished transcript stays in place for review instead of switching to a different screen.

## Current UI Behavior

### Idle Or Ready

- Keep the screen sparse.
- Show only the prompt `Press record to begin the full transcript`.
- Keep the floating button visible so the next action is obvious.

### Recording

- Keep the transcript anchored as the main object.
- Make recording state obvious through the button label alone.
- Do not add extra status copy above or below the transcript.

### Stopping

- Keep the same layout.
- Freeze major controls except the button state needed for clear feedback.
- Show that the app is finishing work without replacing the transcript surface.

### Error Or Permission Block

- Show guidance inside the main canvas.
- Keep the message plain and specific.
- Preserve the overall layout so the app does not feel like it jumped into a different mode.

### Reviewing A Saved Session

- Reuse the same transcript canvas.
- Keep copy and fullscreen available in the bottom rail.
- Let the sidebar support browsing without becoming the main focus.

## Current Modules

These modules are now in code.

- `WorkspaceShell`
  Owns the high-level window layout.
- `TranscriptCanvas`
  Owns the main black canvas and centered reading column.
- `TranscriptColumn`
  Renders transcript content for live and saved sessions.
- `SidebarHost`
  Owns sidebar show or hide state and presentation.
- `SessionSidebar`
  Shows session titles inside the sidebar host.
- `UtilityRail`
  Renders quiet status text and text-only utility actions at the bottom edge.
- `FloatingTransport`
  Renders the one floating record or stop button.

## Frontend Risks

- A hidden sidebar can hurt discoverability [how easy something is to notice] if the toggle is too subtle.
- A floating transport can block transcript text selection if it sits too low or too wide.
- Extreme minimalism can remove useful feedback if status text becomes too faint.
- Long transcripts can still feel heavy if the centered column is too wide or too cramped.
- Permission and error states still need to feel first-class, even inside a very quiet layout.
- The current macOS UI automation around the transport state transition is still somewhat flaky.
- Session titles are derived from transcript text instead of stored session metadata, so the label rule should stay consistent until a real title field exists.

## Where To Look

- Current root view: [`../heed/ContentView.swift`](../heed/ContentView.swift)
- Current app scene: [`../heed/heedApp.swift`](../heed/heedApp.swift)
- Planned visual rules: [`DESIGN.md`](DESIGN.md)
- Planned implementation work: [`exec-plans/active/minimalist-ui-refresh.md`](exec-plans/active/minimalist-ui-refresh.md)
- Product rules: [`PRODUCT_SENSE.md`](PRODUCT_SENSE.md)
