# Frontend

## Current UI Surface

The app still has one main macOS window today.

- App launch opens one window from [`../heed/heedApp.swift`](../heed/heedApp.swift).
- That window renders [`../heed/ContentView.swift`](../heed/ContentView.swift).
- The root view renders `WorkspaceShell`, which is a transcript-first shell with a centered transcript canvas.
- The sessions list is in a hidden-by-default left sidebar column with a compact tree-style treatment.
- The main record or stop action lives in one floating yellow button.
- The window opens at a fixed default size and hides the normal macOS title bar controls.
- The bottom utility rail keeps the center transport clear, puts `Full screen` on the left, and keeps `Compile tasks`, `Set API key`, and `Copy text` on the right when the selected session is eligible for task review.
- The controller still has `.txt` and `.md` file export code, but those file export actions are not surfaced in the current shell.
- While recording, the canvas shows capture state only. It does not stream transcript text live.
- After stop, the shell switches into a processing state while both sources are transcribed.
- Finished sessions show two transcript panels, one for `MIC` and one for `SYSTEM`.

## Current Implemented States

- `idle`
  The app shows the transcript workspace and one empty-state prompt.
- `ready to record`
  The app can request recording on the next `Record` click.
- `recording`
  The timer runs while mic and system audio are captured into separate temp files. The canvas does not show live transcript rows.
- `stopping`
  The app keeps the same screen while it stops capture and moves into post-stop work.
- `processing`
  The app shows per-source transcription progress after stop. This is the main wait state before the finished transcript appears.
- `error`
  The shell shows a blocked status. Detailed recovery text is tracked in the controller, but the refreshed shell does not render that full message yet. Partial transcripts still stay visible when they exist.
- `post-transcript task review`
  A completed transcript with real text can show an inline `Suggested tasks` appendix after the user clicks `Compile tasks`. One task can then open a separate right-side context panel.

## Refresh Status

The shell refresh is now implemented in the app code. The main remaining gaps are polish, discoverability, and UI automation stability.

The current shell now uses:

- a centered transcript column
- a compact left sidebar column that reads like a file tree
- a muted bottom utility rail with sparse text actions
- one empty-state prompt inside the transcript area
- a floating bottom-center yellow record or stop button

## Current Main Surfaces

### Transcript Canvas

This is the default visual focus.

- The canvas fills the window with a black background.
- The transcript sits in a centered reading column.
- Saved and live sessions use the same main reading surface.
- When there is no transcript yet, the canvas shows only `Press record to begin the full transcript`.
- When task review is present, it renders as one inline appendix below the transcript instead of replacing the screen.
- Source jumps from the appendix scroll back to the matching transcript segment and briefly highlight it.
- When task context is present, it renders in a right-side panel while the transcript stays visible.

### Sidebar

The sidebar remains important, but it becomes optional in the layout.

- It sits on the left edge of the window.
- It can be toggled on and off.
- It feels like a compact file-tree panel that belongs to the shell, not a floating drawer.
- It lists only session titles taken from the first transcript line.
- It uses narrow rows, small icons, and a left accent for the selected row.

### Floating Transport

The main record or stop action is one flat floating button.

- Preferred location: bottom center
- Fallback location: top right below narrow widths
- The button stays compact
- It uses a yellow fill
- It keeps square corners, with no visible border radius

### Utility Rail

The bottom rail stays visually quiet.

- It sits flush with the bottom edge of the window.
- It keeps the record button centered without extra status copy around it.
- It puts the fullscreen toggle on the left side.
- It keeps text-only actions on the right side.
- It exposes `Compile tasks` only for completed sessions with transcript text.
- It exposes `Set API key` as a plain-text action.
- It keeps `Copy text` visible beside that action.

### Inline Task Review

The transcript review flow stays in the same reading surface.

- `Compile tasks` expands a collapsible `Suggested tasks` section below the transcript.
- The section shows quiet status text while OpenAI pass 1 is running.
- `Tasks` are the only returned result type and support checkbox selection.
- Each task is labeled as `Feature`, `Bug fix`, or `Miscellaneous`.
- The compiler should keep one deliverable as one task instead of splitting one feature into many smaller tasks.
- Each row can use `Show source` to jump back to evidence in the transcript.
- Each task row now uses `Prepare context` instead of the old placeholder `Spawn agent` action.
- The current shipped build uses real OpenAI calls in the normal app and fixture data only for UI-test mode.

### Task Context Panel

- `Prepare context` runs a second OpenAI pass for one task.
- The panel opens on the right side of the shell.
- The panel shows loading, retry, and loaded states.
- The real `Spawn agent` button now lives inside that panel.
- The current `Spawn agent` action is still only a placeholder state change. Final handoff wiring is still pending.

## Current Interaction Pattern

1. App launches into the main transcript canvas.
2. The transcript surface gets the visual priority, not the sessions list.
3. The user can open the sidebar when they want session history.
4. Opening the sidebar shifts the transcript workspace to the right instead of covering it.
5. Before recording starts, the main canvas shows only `Press record to begin the full transcript`.
6. The user starts recording from the floating yellow button.
7. The app records mic and system audio into separate temp files.
8. The user can copy transcript text or toggle fullscreen from the bottom utility rail.
9. The user stops recording from the same floating button.
10. The shell enters a processing state while it batch-transcribes both sources.
11. The finished transcript stays in place for review instead of switching to a different screen.
12. Finished sessions show two transcript panels, one for `MIC` and one for `SYSTEM`.
13. If the finished transcript has usable text, the user can click `Compile tasks`.
14. The review result opens inline below the transcript and keeps the transcript visible during loading, retry, and recompile states.
15. The user can click `Prepare context` on one task.
16. The app opens a right-side task-context panel and keeps the transcript visible.
17. The final `Spawn agent` action is available only inside that panel.

## Current UI Behavior

### Idle Or Ready

- Keep the screen sparse.
- Show only the prompt `Press record to begin the full transcript`.
- Keep the floating button visible so the next action is obvious.

### Recording

- Keep the transcript area calm while capture is running.
- Make recording state obvious through the button label.
- Do not add live transcript rows above or below the capture surface.

### Processing

- Keep the same layout.
- Show that the app is transcribing both sources after stop.
- Keep source-level status visible until both transcripts are ready.

### Stopping

- Keep the same layout.
- Freeze major controls except the state needed for clear feedback.
- Show that the app is finishing work without replacing the transcript surface.

### Error Or Permission Block

- Show a clear blocked state in the shell.
- Do not pretend detailed guidance is visible until the shell actually renders `errorMessage`.
- Preserve the overall layout so the app does not feel like it jumped into a different mode.

### Reviewing A Saved Session

- Reuse the same transcript canvas.
- Keep copy and fullscreen available in the bottom rail.
- Let the sidebar support browsing without becoming the main focus.
- Show `Compile tasks` only when the saved session is completed and has non-empty transcript text.
- Show split `MIC` and `SYSTEM` panels for completed sessions.
- Keep the `Suggested tasks` appendix tied to the selected session instead of making it a global panel.
- Reset temporary task context when the user switches sessions or recompiles tasks.

## Current Modules

These modules are now in code.

- `WorkspaceShell`
  Owns the high-level window layout.
- `TranscriptCanvasView`
  Owns the main black canvas, centered reading column, and recording or processing states.
- `SourceTranscriptPanelsView`
  Renders the split `MIC` and `SYSTEM` transcript panels for completed sessions.
- `TaskAnalysisSectionView`
  Renders the inline `Suggested tasks` appendix inside the transcript column.
- `TaskContextPanelView`
  Renders the temporary right-side task context panel.
- `SessionSidebarView`
  Shows session titles and selection state.
- `UtilityRailView`
  Renders quiet status text and text-only utility actions at the bottom edge.
- `FloatingTransportView`
  Renders the one floating record or stop button.
- `WindowAccessView`
  Resolves the backing `NSWindow` so the shell can drive fullscreen state and hide standard window controls.

## Frontend Risks

- A hidden sidebar can hurt discoverability [how easy something is to notice] if the toggle is too subtle.
- A floating transport can block transcript text selection if it sits too low or too wide.
- Extreme minimalism can remove useful feedback if status text becomes too faint.
- Long transcripts can still feel heavy if the centered column is too wide or too cramped.
- The inline task appendix can get dense if long evidence text or many items stack below the transcript.
- The right-side task panel can squeeze the transcript on smaller window widths.
- Permission and error states still need to feel first-class, even inside a very quiet layout.
- The controller stores richer error text than the current shell renders, so blocked recovery still feels under-explained on screen.
- The current macOS UI automation around the transport state transition is still somewhat flaky.
- Local macOS accessibility authorization can block UI automation before the new inline review path finishes running.
- Session titles are derived from transcript text instead of stored session metadata, so the label rule should stay consistent until a real title field exists.
- File export still exists below the UI, so the team should decide whether to surface it again or keep the shell intentionally copy-first.
- The final `Spawn agent` destination is still undefined, so the current panel stops at review plus placeholder spawn state.
- The processing state needs to stay explicit or the app will feel frozen after stop.

## Where To Look

- Current root view: [`../heed/ContentView.swift`](../heed/ContentView.swift)
- Current app scene: [`../heed/heedApp.swift`](../heed/heedApp.swift)
- Current shell: [`../heed/UI/WorkspaceShell.swift`](../heed/UI/WorkspaceShell.swift)
- Planned visual rules: [`DESIGN.md`](DESIGN.md)
- UI refresh record: [`exec-plans/completed/minimalist-ui-refresh.md`](exec-plans/completed/minimalist-ui-refresh.md)
- Product rules: [`PRODUCT_SENSE.md`](PRODUCT_SENSE.md)
