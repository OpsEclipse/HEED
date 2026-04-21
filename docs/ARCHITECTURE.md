# Architecture

## Current Snapshot

Heed is now a real macOS SwiftUI app with a shipped local transcript path and a shipped task-prep workspace.

- App entry: [`../heed/heedApp.swift`](../heed/heedApp.swift)
- Root scene: a single `WindowGroup` that shows `ContentView`
- Root UI: [`../heed/ContentView.swift`](../heed/ContentView.swift)
- Recording control layer: [`../heed/Controllers/RecordingController.swift`](../heed/Controllers/RecordingController.swift)
- Audio capture: [`../heed/Audio/`](../heed/Audio/)
- Permissions: [`../heed/Permissions/PermissionsManager.swift`](../heed/Permissions/PermissionsManager.swift)
- Transcription bridge: [`../heed/Transcription/`](../heed/Transcription/)
- Task analysis and prep flow: [`../heed/Analysis/`](../heed/Analysis/)
- Session storage and export: [`../heed/Storage/`](../heed/Storage/)
- Unit tests: [`../heedTests/`](../heedTests/)
- UI tests: [`../heedUITests/`](../heedUITests/)
- Build settings: [`../heed.xcodeproj/project.pbxproj`](../heed.xcodeproj/project.pbxproj)

The app now has a shared domain model, microphone capture, system-audio capture, file-backed source recording, post-stop batch transcription, a Whisper helper process, JSON session persistence, export helpers, an OpenAI-backed task-analysis pass, a GPT-5.4 task-prep workspace with streamed replies, Keychain-backed API-key storage, and demo-mode UI hooks for UI testing.

## Folder Ownership

- `heed/`
  App source. It contains the app entry point, recording UI, task-analysis and prep controllers, capture code, transcription bridge, models, storage, and assets.
- `heedTests/`
  Unit-test target. It covers transcript ordering, export formatting, session recovery, streaming task-prep state, transcript tool round-trips, and spawn approval guards.
- `heedUITests/`
  UI-test target. It covers launch behavior, a demo-mode recording smoke test, inline task compilation, and the main task-prep workspace flow.
- `Tools/WhisperChunkCLI/`
  Local helper package that wraps `SwiftWhisper` and stays bundled inside the app.
- `docs/`
  Human and agent docs for product, planning, quality, reliability, and security.

## Build And Platform Facts

These are real project settings today.

- macOS deployment target: `14.0`
- App Sandbox [a macOS restriction layer]: enabled
- Hardened Runtime [extra macOS runtime protections]: enabled
- Generated Info.plist: enabled
- Default Swift actor isolation [the thread-safety rule Swift uses for code access]: `MainActor`
- Privacy usage strings for microphone, screen capture, and system audio: present
- Checked-in entitlements: App Sandbox, microphone input, and outbound network client access; screen recording still relies on the macOS permission flow instead of a separate entitlement
- User-selected file write access for exports: enabled

Those settings live in [`../heed.xcodeproj/project.pbxproj`](../heed.xcodeproj/project.pbxproj).

## Current System Shape

The current product pipeline has two big paths.

1. `PermissionsManager`
   Owns microphone and screen-capture permission state.
2. `MicCaptureManager`
   Pulls microphone audio from `AVAudioEngine`.
3. `SystemAudioCaptureManager`
   Pulls system audio from `ScreenCaptureKit`, converts the stream’s native audio format into the app’s `16 kHz` mono pipeline, and reports unexpected stream failures back to the controller.
4. `SourceRecordingFileWriter`
   Writes each source into its own temporary local file during recording.
5. `BatchSourceTranscriber`
   Reads the saved source files after stop and turns them into source-specific transcript segments on a background actor [a Swift unit that protects data from race conditions].
6. `SessionStore`
   Saves transcript sessions as local JSON and keeps crash loss small.
7. `TaskAnalysisController`
   Runs the first OpenAI pass only after the user clicks `Compile tasks`. This pass returns grouped tasks with the types `Feature`, `Bug fix`, and `Miscellaneous`.
8. `TaskPrepController`
   Owns the second pass after the user clicks `Prepare context`. It tracks chat messages, streamed turn state, a pending brief, a stable brief, and the spawn approval state for one selected task.
9. `OpenAITaskPrepConversationService`
   Uses the Responses API with streaming [a reply that arrives in small pieces over one connection], reuses the previous response ID for follow-up turns, and exposes three tools: read-only `get_meeting_transcript`, `update_context_draft`, and guarded `spawn_agent`.
10. `WorkspaceShell`
    Shows the transcript-first shell by default, then swaps the main canvas to a split prep workspace while task prep is active.
11. Export layer
    Builds clipboard, text-file, and Markdown-file transcript output from the merged compatibility `segments` view. The current shell surfaces clipboard copy. File export still lives below the UI.

## Task-Prep Workspace Boundaries

These boundaries matter for the shipped prep flow.

- The chat pane owns streamed conversation display. It does not own network calls.
- The right-side brief panel renders controller state. It does not build the draft itself.
- The prep service may read transcript text only through `get_meeting_transcript`.
- The transcript tool must stay scoped to the selected session. It must not browse all saved sessions.
- `update_context_draft` can update the pending brief during a turn, but the controller should pin that brief as stable only after the turn completes.
- `spawn_agent` is advisory in the current shipped UI. The model can request it, but the app still requires explicit user approval before the request becomes ready.
- Prep chat state is memory-only. It is not written into the saved transcript session format.

## Important Boundaries

These broader boundaries should stay clear as the app grows.

- UI should render state, not own audio capture.
- Capture code should not know about export or session history.
- Transcription should consume source-specific chunks, not reach into the UI.
- Persistence should own the saved session format.
- Permission checks should live in one place so the app has one answer for “can we record?”
- The OpenAI task layer should stay on-demand and must not upload transcript text unless the user clicked a task action.
- The task-prep workspace should remain clearly temporary until the team chooses a real saved format and migration [how old saved data becomes new saved data].

## Invariants

These invariants [rules that should always stay true] are either already true or should stay true.

- The app must never start recording without required user permissions.
- Heavy audio and transcription work must not block the main UI thread.
- Transcript sessions should survive normal app restarts.
- New sessions should store split `micSegments` and `systemSegments`, while the merged `segments` view stays available for exports and rollback compatibility.
- Export should not mutate the saved source session.
- If the product claims local transcription, raw meeting audio should not silently leave the machine.
- The prep workspace must reset when the user closes it, switches sessions, or starts prep for a different task.
- Prep chat messages and prep briefs must stay in memory until the team explicitly approves persistence work.
- Spawn requests must stay blocked until the user explicitly approves them in the UI.

## Cross-Cutting Concerns

These cross-cutting concerns [things that affect many parts] matter across the whole app.

- Privacy
  The product touches microphone audio, system audio, saved transcripts, and user-triggered network task analysis.
- Latency
  The post-stop transcript pass and the streamed prep turn both need fast, clear progress.
- Recoverability
  A crash during recording should not erase the whole session, and a failed prep turn should not corrupt saved transcript data.
- Platform constraints
  Screen capture and microphone capture have different permission flows and failure modes.
- Cancellation
  A stale streamed turn must not overwrite a newer task or session. The controller now treats turn identity as a guardrail [a built-in safety check].
- Version support
  The app targets macOS 14, but the build still uses the current macOS 26 SDK from Xcode 26.3.

## Where To Look First

- Start at [`../heed/heedApp.swift`](../heed/heedApp.swift) to see app boot.
- Read [`../heed/ContentView.swift`](../heed/ContentView.swift) to confirm the current shell wiring.
- Read [`../heed/UI/WorkspaceShell.swift`](../heed/UI/WorkspaceShell.swift) to see when the transcript canvas swaps into the prep workspace.
- Read [`../heed/Analysis/TaskPrepController.swift`](../heed/Analysis/TaskPrepController.swift) to see turn state, brief promotion, and approval gating.
- Read [`../docs/RELIABILITY.md`](RELIABILITY.md) before changing capture, autosave, or streaming behavior.
- Read [`../docs/SECURITY.md`](SECURITY.md) before adding permissions, storage, export, or new task-prep tools.
