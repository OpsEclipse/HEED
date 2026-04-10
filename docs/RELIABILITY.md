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
  Medium. `MicCaptureManager` exists and converts input to `16 kHz` mono floats.
- Best next step:
  Add device-change handling and fixture recordings [saved test recordings used to verify behavior].

## System Audio Capture

- Why it matters:
  This is the other half of the meeting.
- Main failure modes:
  No app audio captured, stream interruption, route changes with AirPods, app-specific capture quirks.
- Current confidence:
  Medium. `SystemAudioCaptureManager` now keeps the `ScreenCaptureKit` stream close to its native audio format, converts inside the app, and lets the controller keep a mic-only session alive if system audio dies mid-recording.
- Best next step:
  Treat interruptions and reconnect logic as first-class behavior, not polish.

## Mixing And Chunking

- Why it matters:
  Bad mixing can erase speech or create distortion.
- Main failure modes:
  Clipping, drift between sources, silence detection splitting one thought too early, or memory growth during long speech.
- Current confidence:
  Medium. Per-source utterance chunking now waits for speech to end, keeps a short silence hold so brief pauses stay inside one utterance, and flushes any in-progress speech when recording stops.
- Best next step:
  Add structured logs for chunk timing and validate long sessions for memory growth.

## Transcription

- Why it matters:
  Slow or unstable inference kills the live experience.
- Main failure modes:
  First chunk delay, backlog growth, model missing, helper timeouts, UI stalls.
- Current confidence:
  Medium. The app uses background `WhisperWorker` actors and a bundled helper process. The helper `stderr` pipe is drained, response waits are bounded, and recording startup now has a watchdog [a timer that fails fast when no usable audio or text arrives] so the session clock does not run forever with a dead pipeline.
- Best next step:
  Measure first-chunk latency on supported Apple Silicon hardware and consider prewarm if needed.

## Persistence

- Why it matters:
  A finished meeting is useless if the transcript disappears.
- Main failure modes:
  Crash before save, partial writes, incompatible future format changes.
- Current confidence:
  Medium-high. `SessionStore` autosaves atomically on every new segment, recovers incomplete sessions on relaunch, and now deletes empty failed sessions so retries do not leave junk behind.
- Best next step:
  Add save-failure coverage and document migration [how old saved data becomes new saved data] before changing format.

## Recording Control

- Why it matters:
  If stop or startup hangs, the whole app feels broken even when capture code is partly working.
- Main failure modes:
  Timer keeps running, `Record` never becomes clickable again, or the session gets stuck after one source dies.
- Current confidence:
  Medium. The controller now stops the timer as soon as stop begins, keeps recording if only one source fails, and cleans up interrupted state so the next recording attempt is not blocked.
- Best next step:
  Manually test device changes, denied permissions, and one-source-only startup on a clean machine, then surface richer blocked or recovery text in the shell.

## Export

- Why it matters:
  Export is the handoff point to the user’s real workflow.
- Main failure modes:
  Truncated output, incorrect ordering, overwritten files, unclear success state.
- Current confidence:
  Medium. Deterministic text and Markdown exporters exist, plus clipboard copy in the current shell. The file export paths still exist in the controller, but the refreshed UI does not surface them right now.
- Best next step:
  Decide whether file export should return to the shell, then add a clearer success state for copy or file-save actions.

## Current Trust Summary

The repo is now trustworthy enough for a first end-to-end local path in development. The biggest remaining gap is not basic wiring. It is deeper real-world validation across permission resets, device changes, and live meeting apps, especially around degraded single-source recording after one capture path fails.

## Practices That Would Improve Trust

- Add structured logging [consistent machine-readable logs] around permissions, capture start and stop, chunk delivery, and save events.
- Keep short manual smoke tests [small real-world checks] for Zoom, Meet, and device switching.
- Save known-good sample outputs during development.
- Keep crash-safe autosave and add more save-failure coverage before polishing export.
- Write one long-run soak test [a test that runs for a long time to catch stability issues] once capture works.
