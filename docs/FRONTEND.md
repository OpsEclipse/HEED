# Frontend

## Current UI Surface

The app still has one main macOS window today.

- App launch opens one window from [`../heed/heedApp.swift`](../heed/heedApp.swift).
- That window renders [`../heed/ContentView.swift`](../heed/ContentView.swift).
- The root view renders `WorkspaceShell`, which opens into a brutalist terminal-first shell [a stark interface style built from hard edges, visible structure, and little decoration].
- The primary canvas is black with high-contrast white borders.
- The full-width top nav holds the sidebar toggle, disabled search field, `Open IDE` menu, and settings button.
- The left sidebar lists `tasks`, `new session`, projects, branches, and branch-specific tabs.
- The center pane shows terminal tabs for the selected branch.
- The right pane shows unstaged changed files and readable summaries, not raw code editing.
- The recording and transcript flow remains available through `new session`.
- When `newSession` mode is active, the existing transcript canvas, floating record button, utility rail, compile flow, and task-prep workspace continue to use the existing controllers.
- The window opens at a fixed default size and hides the normal macOS title bar controls.
- The bottom utility rail appears in `newSession` mode and keeps the center transport clear. It keeps `Compile tasks`, `Set API key`, `Copy text`, and `Full screen` on the right when the selected session is eligible for task review.
- `Set API key` opens one sheet for both OpenAI and Composio API keys.
- The controller still has `.txt` and `.md` file export code, but those file export actions are not surfaced in the current terminal shell.
- While recording, the canvas shows capture state only. It does not stream transcript text live.
- After stop, the shell switches into a processing state while both sources are transcribed.
- Finished sessions show two transcript panels, one for `MIC` and one for `SYSTEM`.
- `Prepare context` replaces the transcript canvas with a split task-prep workspace after tasks are compiled from a transcript.

## Current Implemented States

- `idle`
  In `newSession` mode, the app shows the transcript workspace and one empty-state prompt.
- `ready to record`
  In `newSession` mode, the app can request recording on the next `Record` click.
- `recording`
  In `newSession` mode, the timer runs while mic and system audio are captured into separate temp files. The canvas does not show live transcript rows.
- `stopping`
  In `newSession` mode, the app keeps the same screen while it stops capture and moves into post-stop work.
- `processing`
  In `newSession` mode, the app shows per-source transcription progress after stop. This is the main wait state before the finished transcript appears.
- `error`
  In `newSession` mode, the shell shows a blocked status. Detailed recovery text is tracked in the controller, but the refreshed shell does not render that full message yet. Partial transcripts still stay visible when they exist.
- `post-transcript task review`
  A completed transcript with real text can show an inline `Suggested tasks` appendix after the user clicks `Compile tasks`.
- `task prep workspace`
  A selected compiled task opens a split workspace with a left chat pane and a right context brief pane. Assistant turns stream into the chat. The brief panel pins a stable draft only after the turn completes.

## Refresh Status

The shell refresh is now implemented in the app code. The main remaining gaps are polish, discoverability, and UI automation stability.

The current shell now uses:

- a brutalist black shell with high-contrast white borders
- a full-width top nav with sidebar, search, `Open IDE`, and settings controls
- a compact left sidebar for tasks, new session, projects, branches, and branch-specific tabs
- a center terminal workspace with branch-scoped terminal tabs
- a right changed-files pane with readable file summaries
- the existing transcript canvas, utility rail, and floating record button inside `newSession` mode

## Current Main Surfaces

### Terminal Shell

This is the default visual focus.

- The shell fills the window with a black background.
- White borders divide the top nav, sidebar, center pane, and right pane.
- The top nav spans the full width and holds the sidebar toggle, search field, `Open IDE`, and settings.
- The sidebar can be toggled on and off.
- The sidebar lists `tasks`, `new session`, projects, branches, and branch-specific tabs.
- The selected branch controls the center terminal tabs and the changed-file summaries.
- The center pane shows terminal tabs for the selected branch.
- The right pane shows unstaged changed files and short readable summaries. It does not expose raw code editing.

### New Session Transcript Canvas

This remains the recording and transcript surface.

- `new session` opens the transcript flow from the left sidebar.
- The transcript canvas fills the main workspace with a black background.
- The transcript sits in a centered reading column.
- Saved and live sessions use the same main reading surface.
- When there is no transcript yet, the canvas shows only `Press record to begin the full transcript`.
- When task review is present, it renders as one inline appendix below the transcript instead of replacing the screen.
- Source jumps from the appendix scroll back to the matching transcript segment and briefly highlight it.

### Sidebar

The sidebar remains important, but it is optional in the layout.

- It sits on the left edge of the window.
- It can be toggled on and off.
- It feels like a compact project tree that belongs to the shell, not a floating drawer.
- It lists `tasks` and `new session` actions above the project tree.
- It lists projects, branches, and branch-specific side tabs.
- It uses narrow rows and a left accent for the selected branch.

### Floating Transport

The main record or stop action is one flat floating button in `newSession` mode.

- Preferred location: bottom center
- Fallback location: top right below narrow widths
- The button stays compact
- It uses a yellow fill
- It keeps square corners, with no visible border radius

### Utility Rail

The bottom rail stays visually quiet in `newSession` mode.

- It sits flush with the bottom edge of the window.
- It keeps the record button centered without extra status copy around it.
- It keeps text-only actions, including the fullscreen toggle, on the right side.
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

- Before spawn approval, it shows the selected task title at the top.
- It shows streamed GPT-5.4 replies as text deltas [small text pieces that arrive one after another].
- It shows user follow-up messages between assistant turns.
- The input row stays disabled while a turn is streaming.
- Interrupted turns keep their partial text and mark the assistant bubble as interrupted.
- After a successful spawn approval, the left pane becomes a plain embedded terminal canvas [the visible area where terminal text appears and keyboard input is sent].
- The terminal canvas takes direct keyboard input. It does not show a separate `Type into Codex` field or Send button.
- The terminal canvas sizes its text view to the visible pane width so Codex output wraps like normal terminal text instead of one character per line.

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

1. App launches into the terminal shell.
2. The top nav, project and branch sidebar, center terminal tabs, and right changed-files pane get visual priority.
3. The user can toggle the sidebar from the top nav.
4. The user can select projects, branches, and branch-specific tabs from the sidebar.
5. Selecting a terminal tab keeps the center pane focused on that branch terminal.
6. Selecting the changes tab focuses the changed-files pane.
7. The user opens the recording flow from `new session` in the sidebar.
8. Before recording starts, the transcript canvas shows only `Press record to begin the full transcript`.
9. The user starts recording from the floating yellow button.
10. The app records mic and system audio into separate temp files.
11. The user can copy transcript text or toggle fullscreen from the bottom utility rail while in `newSession` mode.
12. The user stops recording from the same floating button.
13. The shell enters a processing state while it batch-transcribes both sources.
14. The finished transcript stays in place for review instead of switching to a different screen.
15. Finished sessions show two transcript panels, one for `MIC` and one for `SYSTEM`.
16. If the finished transcript has usable text, the user can click `Compile tasks`.
17. The review result opens inline below the transcript and keeps the transcript visible during loading, retry, and recompile states.
18. The user can click `Prepare context` on one compiled transcript task.
19. The app swaps the transcript canvas into the split prep workspace.
20. The first assistant turn streams into the left chat pane.
21. If the model asks for more evidence, the service uses a read-only transcript tool for the selected session only.
22. If a Composio API key is saved, the service also gives the prep agent Gmail, Google Calendar, and Google Drive tools through Composio MCP [a remote tool server protocol].
23. The right panel pins a stable brief after the turn completes.
24. If the model asks to spawn, the right panel shows the approval request and the user can click `Approve spawn`.
25. A successful approval turns the left pane into an integrated terminal and starts `codex --model gpt-5.2-codex --no-alt-screen` with a compressed handoff.
26. Closing the workspace, switching sessions, or starting prep for another task clears the prep chat, brief, and terminal output because they are intentionally temporary.

## Current UI Behavior

### Idle Or Ready

- This behavior applies inside `newSession` mode.
- Keep the screen sparse.
- Show only the prompt `Press record to begin the full transcript`.
- Keep the floating button visible so the next action is obvious.

### Recording

- This behavior applies inside `newSession` mode.
- Keep the transcript area calm while capture is running.
- Make recording state obvious through the button label.
- Do not add live transcript rows above or below the capture surface.

### Processing

- This behavior applies inside `newSession` mode.
- Keep the same layout.
- Show that the app is transcribing both sources after stop.
- Keep source-level status visible until both transcripts are ready.

### Stopping

- This behavior applies inside `newSession` mode.
- Keep the same layout.
- Freeze major controls except the state needed for clear feedback.
- Show that the app is finishing work without replacing the transcript surface.

### Error Or Permission Block

- This behavior applies inside `newSession` mode.
- Show a clear blocked state in the shell.
- Do not pretend detailed guidance is visible until the shell actually renders `errorMessage`.
- Preserve the overall layout so the app does not feel like it jumped into a different mode.

### Reviewing A Saved Session

- This behavior applies inside `newSession` mode.
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
- `TopNavView`
  Renders the full-width top nav with sidebar toggle, search, `Open IDE`, and settings controls.
- `ProjectBranchSidebarView`
  Renders `tasks`, `new session`, projects, branches, and branch-specific tabs.
- `TerminalWorkspaceView`
  Renders the selected branch terminal tabs and terminal body.
- `ChangedFilesPane`
  Renders unstaged changed files and readable summaries.
- `TranscriptCanvasView`
  Owns the `newSession` black canvas, centered reading column, and recording or processing states.
- `SourceTranscriptPanelsView`
  Renders the split `MIC` and `SYSTEM` transcript panels for completed sessions.
- `TaskAnalysisSectionView`
  Renders the inline `Suggested tasks` appendix inside the transcript column.
- `TaskPrepWorkspaceView`
  Renders the split prep layout.
- `TaskPrepChatView`
  Renders the streamed chat thread and follow-up input row.
- `TaskPrepTerminalView`
  Renders the direct embedded terminal canvas after spawn approval.
- `TaskPrepContextPanelView`
  Renders the right-side stable brief and spawn approval state.
- `SessionSidebarView`
  Still exists in code for the older session-list surface, but the current shell uses `ProjectBranchSidebarView`.
- `UtilityRailView`
  Renders quiet status text and text-only utility actions at the bottom edge in `newSession` mode.
- `FloatingTransportView`
  Renders the one floating record or stop button in `newSession` mode.
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
