# Reliability

## Reliability-Critical Areas

## Permissions

- Why it matters:
  Recording cannot start without microphone and screen-capture access.
- Main failure modes:
  Prompt never appears, permission is denied, or UI state goes stale after system changes.
- Current confidence:
  Medium. `PermissionsManager` exists and the app blocks recording when access is missing.
- Best next step:
  Add manual checks for first-run, denied, and later-granted flows on a clean machine.

## Microphone Capture

- Why it matters:
  Missing mic audio makes the transcript incomplete.
- Main failure modes:
  Wrong input device, input changes during a call, sample conversion errors.
- Current confidence:
  Medium. `MicCaptureManager` exists and writes microphone audio into a temporary source file during recording.
- Best next step:
  Add device-change handling, temp-file cleanup checks, and fixture recordings [saved test recordings used to verify behavior].

## System Audio Capture

- Why it matters:
  This is the other half of the meeting.
- Main failure modes:
  No app audio captured, stream interruption, route changes with AirPods, app-specific capture quirks.
- Current confidence:
  Medium. `SystemAudioCaptureManager` now keeps the `ScreenCaptureKit` stream close to its native audio format, converts inside the app, and writes system audio into its own temporary file during recording.
- Best next step:
  Treat interruptions, reconnect logic, and temp-file cleanup as first-class behavior, not polish.

## Source Recording And Batch Transcription

- Why it matters:
  If capture drops or file handoff fails, the app loses the raw meeting source.
- Main failure modes:
  File write errors, temp-file cleanup failures, missing source audio after stop, or long sessions that create large temp files.
- Current confidence:
  Medium. The app now writes mic and system audio to separate temp files during recording, then batch-transcribes both sources after stop and shows a processing state while that work runs.
- Best next step:
  Add structured logs for stop-to-processing timing and validate long sessions for temp-file growth and cleanup.

## Transcription

- Why it matters:
  Slow or unstable inference kills the post-stop wait.
- Main failure modes:
  Batch start delay, helper timeouts, model missing, transcription backlog growth, or UI stalls while processing.
- Current confidence:
  Medium. The app uses background `WhisperWorker` actors and a bundled helper process. The helper `stderr` pipe is drained, response waits are bounded, and recording now hands off to a batch transcriber after stop instead of streaming text live.
- Best next step:
  Measure post-stop transcription latency on supported Apple Silicon hardware and consider prewarm if needed.

## Persistence

- Why it matters:
  A finished meeting is useless if the transcript disappears.
- Main failure modes:
  Crash before save, partial writes, incompatible future format changes.
- Current confidence:
  Medium-high. `SessionStore` autosaves atomically on every update, recovers incomplete sessions on relaunch, and now keeps `TranscriptSession` split into `micSegments` and `systemSegments` while preserving a merged compatibility `segments` view for exports and rollback.
- Best next step:
  Add save-failure coverage and document migration [how old saved data becomes new saved data] before changing the session format again.

## Recording Control

- Why it matters:
  If stop or startup hangs, the whole app feels broken even when capture code is partly working.
- Main failure modes:
  Timer keeps running, `Record` never becomes clickable again, or the session gets stuck in processing after one source dies.
- Current confidence:
  Medium. The controller now stops the timer as soon as stop begins, keeps the UI in a clear processing state while both sources are transcribed, and cleans up interrupted state so the next recording attempt is not blocked.
- Best next step:
  Manually test device changes, denied permissions, and one-source-only startup on a clean machine, then surface richer blocked or processing text in the shell.

## OpenAI Task Compilation

- Why it matters:
  This is the first AI step after a transcript is ready.
- Main failure modes:
  Missing API key, network failure, malformed structured output, one deliverable being split into too many tasks, or stale compile results landing on the wrong session.
- Current confidence:
  Medium. The app uses an explicit pass-1 compile flow, returns grouped tasks only with the types `Feature`, `Bug fix`, and `Miscellaneous`, and resets prep state when the selected session changes or the user recompiles.
- Best next step:
  Add request logging with request IDs and manual network-off checks.

## Task-Prep Workspace

- Why it matters:
  This is the live handoff-prep surface after task compilation. It is where users decide whether the task has enough context to move forward.
- Main failure modes:
  A streamed turn ends before completion, the parser drops partial text, a stale turn lands on the wrong task, the transcript tool reads from the wrong session, the brief pins too early, the spawn approval state leaks across tasks, Terminal automation is denied or fails after approval, or users lose work because the prep workspace is intentionally not persisted.
- Current confidence:
  Medium. `TaskPrepController` cancels stale turns, ignores late events from older turns, keeps interrupted partial text visible, promotes the brief only after a completed event, resets on session changes, blocks spawn until explicit approval, and now launches the approved Codex handoff through a dedicated launcher. Tests cover streamed message assembly, transcript-tool submission, malformed streamed events, interrupted turns, stale-turn protection, the approval guard, and the launched brief contents.
- Best next step:
  Add more end-to-end checks against real network turns, then add manual smoke coverage for Terminal permission denial and retry behavior.

## Export

- Why it matters:
  Export is the handoff point to the user’s real workflow.
- Main failure modes:
  Truncated output, incorrect ordering, overwritten files, unclear success state.
- Current confidence:
  Medium. Deterministic text and Markdown exporters exist, plus clipboard copy in the current shell. Export now reads the merged compatibility `segments` view, so it still works even though storage is split into `micSegments` and `systemSegments`.
- Best next step:
  Decide whether file export should return to the shell, then add a clearer success state for copy or file-save actions.

## UI Test Harness

- Why it matters:
  The shipped task-prep workspace now depends on macOS UI coverage for confidence in the end-to-end flow.
- Main failure modes:
  Local accessibility authorization blocks the run, window activation races on launch, or the harness flakes intermittently [fails some runs but not others] even when the app is fine.
- Current confidence:
  Medium-low. There is a real UI test for the record, compile, and prep flow, but the local macOS harness is still not stable enough for launch-performance coverage, which stays skipped on purpose.
- Best next step:
  Keep the functional prep test, keep fixture timing simple, and continue treating local UI-test flakes as a separate harness problem instead of silent product truth.

## Current Trust Summary

The repo is trustworthy enough for a first end-to-end local transcript path plus a shipped task-prep workspace. The biggest remaining gaps are deeper real-world validation across permission resets, device changes, live meeting apps, and more real-network validation for the streamed prep flow.

## Practices That Would Improve Trust

- Add structured logging [consistent machine-readable logs] around permissions, capture start and stop, batch transcription timing, streamed prep turns, and save events.
- Keep short manual smoke tests [small real-world checks] for Zoom, Meet, device switching, and the task-prep workspace.
- Save known-good sample outputs during development.
- Keep crash-safe autosave and add more save-failure coverage before polishing export.
- Write one long-run soak test [a test that runs for a long time to catch stability issues] once capture works.
