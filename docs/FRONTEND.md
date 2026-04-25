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
- `Prepare context` now replaces the transcript canvas with a split task-prep workspace.

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
  A completed transcript with real text can show an inline `Suggested tasks` appendix after the user clicks `Compile tasks`.
- `task prep workspace`
  A selected compiled task opens a split workspace with a left chat pane and a right context brief pane. Assistant turns stream into the chat. The brief panel pins a stable draft only after the turn completes.

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

### Task Prep Workspace

`Prepare context` opens a separate workspace inside the main shell.

- The workspace is a split layout [a screen divided into two side-by-side areas].
- The left pane is the prep chat.
- The right pane is a fixed-width context brief panel.
- The transcript canvas is hidden while this workspace is open.
- The sidebar toggle still stays available in the shell chrome.
- A close button in the right panel resets prep state and returns the shell to the transcript canvas.

### Left Prep Chat And Terminal

The left pane is the live conversation surface before spawn approval. After approval, it becomes the integrated Codex terminal.

- It shows the selected task title at the top.
- It shows streamed GPT-5.4 replies as text deltas [small text pieces that arrive one after another].
- It shows user follow-up messages between assistant turns.
- The input row stays disabled while a turn is streaming.
- Interrupted turns keep their partial text and mark the assistant bubble as interrupted.
- After a successful spawn approval, it shows terminal output and a terminal input row.

### Right Context Brief Panel

The right pane is the stable handoff draft.

- It shows `Summary`, `Goal`, `Constraints`, `Acceptance`, `Risks`, `Open questions`, and `Evidence`.
- If there is no stable brief yet, it can render the latest pending brief while the first turn is streaming.
- If a stable brief already exists, it keeps showing that stable brief during later turns and adds `Updating brief...` while the new pending draft is still in flight.
- It promotes that pending brief to the stable brief only after the controller receives a completed turn.
- It shows `Updating brief...` when a new draft arrives during a later turn.
- It includes a `Spawn approval` section that explains whether the model has asked to spawn and whether the user approved it.
- It shows `Approve spawn` only when a spawn request is blocked waiting for approval.
- A successful approval starts the integrated Codex terminal in the left pane.
- If that handoff fails, the section stays visible and offers `Retry spawn`.

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
16. The app swaps the main canvas into the split prep workspace.
17. The first assistant turn streams into the left chat pane.
18. If the model asks for more evidence, the service uses a read-only transcript tool for the selected session only.
19. The right panel pins a stable brief after the turn completes.
20. If the model asks to spawn, the right panel shows the approval request and the user can click `Approve spawn`.
21. A successful approval turns the left pane into an integrated terminal and starts `codex` with a compressed handoff.
22. Closing the workspace, switching sessions, or starting prep for another task clears the prep chat, brief, and terminal output because they are intentionally temporary.

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
- Reset task-prep state when the user switches sessions or recompiles tasks.

### Running Task Prep

- Open one prep workspace for one task at a time.
- Stream assistant text into the left pane instead of waiting for one full message.
- Switch the left pane into terminal mode after approved spawn.
- Keep the latest stable brief visible on the right while a follow-up turn is in flight.
- Do not persist the prep chat or prep brief to disk.
- Do not persist terminal output to disk.
- Keep spawn blocked until the user explicitly approves it.
- Do not add extra success UI after the terminal starts. Failure states can stay visible because they need recovery.

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
- `TaskPrepWorkspaceView`
  Renders the split prep layout.
- `TaskPrepChatView`
  Renders the streamed chat thread and follow-up input row.
- `TaskPrepContextPanelView`
  Renders the right-side stable brief and spawn approval state.
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
- The fixed right prep panel can squeeze the left chat pane on smaller window widths.
- Permission and error states still need to feel first-class, even inside a very quiet layout.
- The controller stores richer error text than the current shell renders, so blocked recovery still feels under-explained on screen.
- The prep workspace is intentionally temporary, so users can lose unsaved prep context when they close it or switch sessions.
- Local macOS UI automation is still somewhat flaky. The functional task-prep test exists, but launch-performance coverage stays skipped because the harness is not stable enough there.
- Local macOS accessibility authorization can still block UI automation before the inline review or prep path finishes running.
- Session titles are derived from transcript text instead of stored session metadata, so the label rule should stay consistent until a real title field exists.
- File export still exists below the UI, so the team should decide whether to surface it again or keep the shell intentionally copy-first.
- The processing state needs to stay explicit or the app will feel frozen after stop.

## Where To Look

- Current root view: [`../heed/ContentView.swift`](../heed/ContentView.swift)
- Current app scene: [`../heed/heedApp.swift`](../heed/heedApp.swift)
- Current shell: [`../heed/UI/WorkspaceShell.swift`](../heed/UI/WorkspaceShell.swift)
- Prep workspace: [`../heed/UI/TaskPrepWorkspaceView.swift`](../heed/UI/TaskPrepWorkspaceView.swift)
- Prep chat: [`../heed/UI/TaskPrepChatView.swift`](../heed/UI/TaskPrepChatView.swift)
- Prep brief panel: [`../heed/UI/TaskPrepContextPanelView.swift`](../heed/UI/TaskPrepContextPanelView.swift)
- Product rules: [`PRODUCT_SENSE.md`](PRODUCT_SENSE.md)
