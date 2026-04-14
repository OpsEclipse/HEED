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
  This is the new post-meeting action path, so failures here directly shape whether users trust the app’s AI layer.
- Main failure modes:
  Missing API key, network failure, malformed structured output, one deliverable being split into too many tasks, stale pass 1 results landing on the wrong session, or stale pass 2 results landing on the wrong task.
- Current confidence:
  Medium. The app now uses an explicit two-pass OpenAI flow, keeps pass 2 temporary in memory, resets task context on session changes and recompiles, and has tests for structured decoding plus stale task-context requests. Pass 1 now returns grouped tasks only with the types `Feature`, `Bug fix`, and `Miscellaneous`.
- Best next step:
  Add request logging with request IDs, manual network-off checks, and one test double for malformed OpenAI output at the shell level.

## Export

- Why it matters:
  Export is the handoff point to the user’s real workflow.
- Main failure modes:
  Truncated output, incorrect ordering, overwritten files, unclear success state.
- Current confidence:
  Medium. Deterministic text and Markdown exporters exist, plus clipboard copy in the current shell. Export now reads the merged compatibility `segments` view, so it still works even though storage is split into `micSegments` and `systemSegments`.
- Best next step:
  Decide whether file export should return to the shell, then add a clearer success state for copy or file-save actions.

## Current Trust Summary

The repo is now trustworthy enough for a first end-to-end local path in development plus an explicit post-meeting AI path. The biggest remaining gaps are deeper real-world validation across permission resets, device changes, live meeting apps, and failure handling around the new network task pipeline.

## Practices That Would Improve Trust

- Add structured logging [consistent machine-readable logs] around permissions, capture start and stop, chunk delivery, and save events.
- Keep short manual smoke tests [small real-world checks] for Zoom, Meet, and device switching.
- Save known-good sample outputs during development.
- Keep crash-safe autosave and add more save-failure coverage before polishing export.
- Write one long-run soak test [a test that runs for a long time to catch stability issues] once capture works.
