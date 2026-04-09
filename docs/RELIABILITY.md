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
  Medium. `SystemAudioCaptureManager` now keeps the `ScreenCaptureKit` stream close to its native audio format and converts inside the app, which is more stable than forcing `16 kHz` mono at stream setup time.
- Best next step:
  Treat interruptions and reconnect logic as first-class behavior, not polish.

## Mixing And Chunking

- Why it matters:
  Bad mixing can erase speech or create distortion.
- Main failure modes:
  Clipping, drift between sources, chunk seams cutting words, memory growth.
- Current confidence:
  Medium. Per-source chunking exists with 5-second windows and 1-second overlap.
- Best next step:
  Add structured logs for chunk timing and validate long sessions for memory growth.

## Transcription

- Why it matters:
  Slow or unstable inference kills the live experience.
- Main failure modes:
  First chunk delay, backlog growth, model missing, UI stalls.
- Current confidence:
  Medium. The app uses background `WhisperWorker` actors and a bundled helper process.
- Best next step:
  Measure first-chunk latency on supported Apple Silicon hardware and consider prewarm if needed.

## Persistence

- Why it matters:
  A finished meeting is useless if the transcript disappears.
- Main failure modes:
  Crash before save, partial writes, incompatible future format changes.
- Current confidence:
  Medium-high. `SessionStore` autosaves atomically on every new segment and recovers incomplete sessions on relaunch.
- Best next step:
  Autosave during recording and document migration [how old saved data becomes new saved data] before changing format.

## Export

- Why it matters:
  Export is the handoff point to the user’s real workflow.
- Main failure modes:
  Truncated output, incorrect ordering, overwritten files, unclear success state.
- Current confidence:
  Medium. Deterministic text and Markdown exports exist, plus clipboard copy.
- Best next step:
  Make exported output deterministic [always producing the same result from the same input] and easy to preview.

## Current Trust Summary

The repo is now trustworthy enough for a first end-to-end local path in development. The biggest remaining gap is not basic wiring. It is deeper real-world validation across permission resets, device changes, and live meeting apps.

## Practices That Would Improve Trust

- Add structured logging [consistent machine-readable logs] around permissions, capture start and stop, chunk delivery, and save events.
- Keep short manual smoke tests [small real-world checks] for Zoom, Meet, and device switching.
- Save known-good sample outputs during development.
- Add crash-safe autosave before polishing export.
- Write one long-run soak test [a test that runs for a long time to catch stability issues] once capture works.
