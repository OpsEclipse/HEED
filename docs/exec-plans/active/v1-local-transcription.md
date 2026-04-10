# Heed V1 Local Transcription

## Goal

Build Heed into a macOS 14+ app that records microphone audio and system audio after the user clicks `Record`, transcribes both sources locally with Whisper, shows a live transcript-first shell with clear `MIC` and `SYSTEM` labels, and saves the finished session as a structured JSON file when the user clicks `Stop`. The app must work offline after install and must not keep raw audio after the session ends.

## Scope

- Replace the placeholder UI in [`heed/ContentView.swift`](../../../heed/ContentView.swift) with a real recording and transcript screen.
- Add a recording controller that owns permissions, capture start and stop, transcript updates, and session finalization.
- Add microphone capture with `AVAudioEngine`.
- Add system-audio capture with `ScreenCaptureKit` [Apple’s screen and system-audio capture framework].
- Normalize both sources to `16 kHz` mono PCM [raw audio samples].
- Keep mic and system audio separate through capture and transcription.
- Run local Whisper transcription with one bundled English model.
- Merge transcript segments into one live timeline while preserving source labels and timing order.
- Autosave transcript sessions as structured JSON under Application Support.
- Add `Copy as text`, `.txt` export, and `.md` export.
- Add required privacy strings and the needed capture permissions, plus the microphone sandbox entitlement [a signed capability flag].
- Align the app target with the chosen macOS 14+ floor.

## Non-Goals

- True diarization [automatic speaker identity separation]. V1 only labels by source: `MIC` or `SYSTEM`.
- Cloud sync, remote transcription, or any server dependency for the core path.
- Menu bar mode.
- Multi-window flows.
- Raw audio retention after a session ends.
- Multilingual transcription in v1.
- Editing transcript text inside the app.

## Current State

- The app now has a live transcript shell in [`heed/ContentView.swift`](../../../heed/ContentView.swift) and orchestration in [`heed/Controllers/RecordingController.swift`](../../../heed/Controllers/RecordingController.swift).
- The repo contains microphone capture, system-audio capture, per-source chunking, Whisper helper workers, JSON session storage, and export helpers.
- The project now deploys to macOS `14.0` with generated Info.plist privacy strings in place, plus the microphone sandbox entitlement. Screen recording still uses the macOS permission flow instead of a separate entitlement.
- The bundled Whisper model is downloaded at build time and copied into the app bundle, so the installed app works offline after build and install.

## Implementation Plan

### 1. Project And Platform Setup

- Lower the app target to macOS 14+ in [`heed.xcodeproj/project.pbxproj`](../../../heed.xcodeproj/project.pbxproj).
- Add privacy usage strings for microphone and screen capture.
- Add the required microphone entitlement and the needed screen-recording privacy strings.
- Keep generated Info.plist values unless there is a strong reason to check in a real `Info.plist`.
- Keep App Sandbox and Hardened Runtime enabled.

### 2. App Control Layer

- Add `RecordingController` as the main orchestrator [the part that coordinates the flow].
- Add `RecordingState` with at least:
  - `idle`
  - `requestingPermissions`
  - `ready`
  - `recording`
  - `stopping`
  - `error`
- Add `PermissionsManager` with one source of truth for microphone and screen-recording state.
- Request permissions only when the user tries to start recording.
- Prevent recording start until both permissions are granted.

### 3. Audio Capture

- Add `MicCaptureManager` with `AVAudioEngine`.
- Install an input tap on the input node and convert samples to `16 kHz`, mono PCM.
- Add `SystemAudioCaptureManager` with an audio-enabled, video-disabled `SCStream`.
- Choose the main display as the capture anchor because ScreenCaptureKit needs a share target even though audio is the product target here.
- Convert system-audio frames to the same `16 kHz`, mono PCM format.
- Chunk each source independently by speech-until-silence, with a short silence hold so brief pauses stay inside one utterance and a safety max length so very long speech does not become one giant transcription request.
- Timestamp every chunk relative to session start.

### 4. Local Whisper Transcription

- Bundle one English Whisper model in the app, using `ggml-base.en` as the default.
- Add two source-specific transcription workers: one for `MIC`, one for `SYSTEM`.
- Run both workers off the main thread on background actors [Swift units that protect state from race conditions].
- Emit `TranscriptSegment` values with:
  - `id`
  - `source`
  - `startedAt`
  - `endedAt`
  - `text`
- Trim repeated leading text if one long utterance still needs to be split into more than one transcription request.
- Do not mix the audio before Whisper. Mixing would erase clean source labels, like pouring two paint colors into one bucket and losing the original colors.

### 5. Transcript Timeline And UI

- Build one main transcript screen in the existing app window.
- Use a transcript-first UI with strong contrast and clear source labels.
- Main visible controls:
  - floating `Record` / `Stop` button
  - session timer and status in a quiet utility rail
  - live transcript list
  - clear `MIC` and `SYSTEM` labels
  - per-segment timestamps
- Merge segment streams into one ordered timeline by `startedAt`, then `source`, then insertion order.
- If both sources speak at the same time, keep both rows. Overlap is allowed.
- Auto-scroll while the user is at the bottom. If the user scrolls away, stop forcing scroll until they return.
- After stop, keep the same window and switch into a simple review state with export actions.
- The current refreshed shell still exposes clipboard copy in the UI. File export code remains implemented in the controller, but the shell does not surface it right now.
- While capture is active, keep the live session selected so the detail pane stays aligned with the recording in progress.

### 6. Persistence And Export

- Use structured JSON as the canonical session format.
- Save session folders at:
  - `~/Library/Application Support/Heed/Sessions/<session-id>/`
- Save the canonical file as:
  - `session.json`
- Session JSON should include at least:
  - `id`
  - `startedAt`
  - `endedAt`
  - `duration`
  - `status`
  - `modelName`
  - `appVersion`
  - `segments`
- Autosave `session.json` every time a new transcript segment is appended.
- Mark sessions as `recording` while live and `completed` after a clean stop.
- On relaunch, load prior sessions and keep incomplete ones visible as partial recoveries.
- Add derived exports:
  - `Copy as text`
  - `heed-<session-id>.txt`
  - `heed-<session-id>.md`
- Do not retain raw audio after stop completes.

## Public Interfaces

- `enum AudioSource { mic, system }`
- `enum RecordingState { idle, requestingPermissions, ready, recording, stopping, error }`
- `struct TranscriptSegment`
- `struct TranscriptSession`
- `PermissionsManager`
- `RecordingController`
- `MicCaptureManager`
- `SystemAudioCaptureManager`
- `WhisperWorker`
- `TranscriptTimelineStore`
- `SessionStore`

These names can shift slightly during implementation, but the ownership seams [the boundaries between responsibilities] should stay the same.

## Risks

- ScreenCaptureKit permission and stream setup may behave differently from microphone permission flow.
- Audio-device changes during a call can break source continuity.
- Whisper startup time may delay the first visible transcript chunk.
- A helper stall can trap the stop flow unless response time is bounded and interrupted state is cleaned up.
- Separate source pipelines can drift in timing if timestamps are not anchored to one session clock.
- Silence detection can end an utterance too early or too late if thresholds are tuned poorly.
- Autosave bugs could lose partial transcripts after a crash.
- Lowering the deployment target may expose framework compatibility issues if the current project uses newer defaults.

## Open Questions

- None are blocking for v1 planning.
- If implementation finds that `ggml-base.en` is too slow for acceptable live latency on the target hardware, the fallback decision should be to test a smaller English model before changing the UI or storage design.

## Validation Steps

### Build And Project Checks

- Run:
  - `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`
- Confirm the app launches on a macOS 14+ machine.
- Confirm the final target settings include the needed privacy strings and entitlements.

### Manual Behavior Checks

- Launch the app fresh and click `Record`.
- Confirm microphone permission is requested if missing.
- Confirm screen-recording permission is requested if missing.
- Confirm the UI clearly blocks recording until both permissions are granted.
- Speak only into the mic and confirm `MIC` rows appear.
- Play remote audio through the Mac and confirm `SYSTEM` rows appear.
- Alternate speech between local mic and remote system audio and confirm timing order feels correct.
- Speak over remote audio and confirm overlapping rows are still shown separately.
- Click `Stop` during active transcription and confirm the last pending text is flushed before save.
- Click `Stop` during a bad or stalled transcription run and confirm the timer stops right away and the app returns control instead of freezing.
- Force-quit during an active session, relaunch, and confirm the partial session can still be loaded from autosave.
- Export `.txt` and `.md` and confirm ordering, labels, and timestamps are preserved as expected.

### Failure Checks

- Deny one permission and confirm the app shows a clear blocked state and recovery instructions.
- Remove or rename the bundled model and confirm the app shows a model-missing error instead of hanging.
- Start recording, then change audio devices, and confirm the app either recovers cleanly or shows an explicit interruption state.

## Observable Acceptance Criteria

- The user can click `Record` and begin live local transcription after granting permissions.
- The first transcript text appears within one chunk cycle plus model time. Target: under 8 seconds on supported Apple Silicon hardware.
- Every transcript row is visibly marked `MIC` or `SYSTEM`.
- Clicking `Stop` ends capture, flushes pending transcript work, and writes `session.json`.
- Relaunching the app shows prior saved sessions, including incomplete recovered sessions.
- The app works offline after install.
- The app stores transcript data and derived text exports, but not raw audio after the session ends.

## Progress

- 2026-04-08: Created the initial ExecPlan from the agreed product direction and implementation choices.
- 2026-04-08: Lowered the app target to macOS `14.0`, added privacy strings, enabled export-safe sandbox access, and bundled a Whisper helper build step.
- 2026-04-08: Implemented `RecordingController`, `PermissionsManager`, `MicCaptureManager`, `SystemAudioCaptureManager`, per-source chunking, `WhisperWorker`, `SessionStore`, `TranscriptTimelineStore`, and export helpers.
- 2026-04-08: Replaced the placeholder UI with a first working sessions-plus-transcript workspace and added demo-mode hooks for UI testing.
- 2026-04-09: Refreshed that first shell into the current transcript-first layout with a collapsible sidebar, floating transport, and quiet utility rail.
- 2026-04-08: Added unit coverage for timeline ordering, export formatting, and session recovery, plus UI coverage for launch and demo-mode recording.
- 2026-04-08: Verified `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`.
- 2026-04-08: Verified `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test`.
- 2026-04-09: Hardened `SystemAudioCaptureManager` after real runtime logs showed `ScreenCaptureKit` and Core Audio instability when the stream was forced to `16 kHz` mono at setup time.
- 2026-04-09: Reviewed the whole v1 path against the plan without rerunning tests. Fixed three code gaps found in review: screen-capture permission state now stays `unknown` until the app actually asks, unexpected system-audio failures now surface as app errors, and the Whisper helper now drains `stderr` so long error output does not stall the child process.
- 2026-04-09: Tightened the main UI controls so the primary button is disabled while permissions are in flight or stop is flushing, and export actions stay off during active capture but remain available for partial sessions after an interruption.
- 2026-04-09: Added bounded Whisper response waits, a startup watchdog for “recording but no text” cases, partial single-source survival when one capture path dies, and cleanup that deletes empty failed sessions so the next `Record` attempt is not blocked.
- 2026-04-09: Hardened recording startup after real runs still stalled with a live timer but no transcript. The controller now starts mic and system audio independently, keeps recording if one source survives, closes interrupted sessions immediately instead of leaving them active, and fails fast when a session receives no usable audio or text during startup.
- 2026-04-09: Re-verified `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build` and `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests` after the startup hardening changes.
- 2026-04-09: Added a shared audio-energy gate before Whisper chunk transcription so silent or near-silent chunks are dropped instead of turning into filler text like repeated `you`, especially on the `SYSTEM` path.
- 2026-04-09: Replaced the rolling 3-second overlap chunker with speech-until-silence chunking. The pipeline now waits for speech, keeps a short silence hold so quick pauses stay grouped, and flushes one utterance-sized chunk into Whisper after speech ends.
- 2026-04-09: Reworked the bundled Whisper helper to call `whisper.cpp` directly so it can suppress non-speech tokens and drop low-confidence segment text from pure background noise before the app shows it.

## Surprises & Discoveries

- 2026-04-08: The current Xcode project target is macOS `26.2`, which does not match the chosen v1 support floor.
- 2026-04-08: The repo still uses a generated Info.plist, so privacy strings may be added through build settings instead of a checked-in plist file.
- 2026-04-08: Keeping source labels requires separate transcription pipelines. A single mixed audio stream would not preserve clear `MIC` vs `SYSTEM` transcript rows.
- 2026-04-08: The project uses file-system-synchronized root groups, so new files under `heed/` compiled without any source-file `.pbxproj` edits.
- 2026-04-08: A bundled helper package was easier than hand-editing Xcode Swift package references, and it still keeps the shipped app offline after install.
- 2026-04-08: Atomic file writes were enough for `session.json` once the session directory existed.
- 2026-04-08: Demo-mode launch arguments made UI tests stable without needing real permissions or live audio devices.
- 2026-04-09: `ScreenCaptureKit` still behaves like a display-bound stream even in this audio-first flow, so the app still anchors capture to a real display even though it now consumes only audio output samples.
- 2026-04-09: Forcing `sampleRate = 16_000` and `channelCount = 1` in `SCStreamConfiguration` produced lower-level Core Audio errors on real runs. Letting the stream keep its native format and converting inside the app is safer.
- 2026-04-09: `CGPreflightScreenCaptureAccess()` does not tell us whether screen recording was never requested or was already denied. The app now tracks whether it has asked before so the first-launch guidance stays honest.
- 2026-04-09: Piping the Whisper helper `stderr` into an unread pipe can deadlock [freeze because an OS buffer fills up] a long-running child process. Draining that pipe is required for stable local transcription sessions.
- 2026-04-09: A session can look alive even when text generation is dead if the UI clock starts before we prove audio and transcription are healthy. A startup watchdog and immediate interrupted-session finalization make that failure visible instead of leaving the UI in limbo.

## Decision Log

- 2026-04-08: Chose macOS 14+ as the support floor to keep implementation simpler and allow newer platform APIs.
- 2026-04-08: Chose structured JSON as the canonical session format because it is transparent, debuggable, and not tied to one Apple persistence framework.
- 2026-04-08: Chose a bundled English Whisper model to keep the app offline-first and avoid first-run download complexity.
- 2026-04-08: Chose one main window for v1 to keep lifecycle and state simpler.
- 2026-04-08: Chose separate source-specific transcription instead of pre-mixing audio so transcript rows can stay labeled by source.
- 2026-04-08: Chose transcript-only retention after stop to reduce privacy exposure and disk usage.
- 2026-04-08: Chose `~/Library/Application Support/Heed/Sessions/<session-id>/session.json` as the canonical session path so saved data stays local and inspectable.
- 2026-04-08: Chose stable relative timestamps in exports, with `MIC` sorting before `SYSTEM` when segment start times match.
- 2026-04-08: Chose to keep export helpers pure and deterministic so they can be reused by copy, `.txt`, and `.md` output paths.
- 2026-04-08: Chose a bundled helper package built from `Tools/WhisperChunkCLI` instead of editing Xcode Swift package references by hand.
- 2026-04-08: Chose build-time model download into the app bundle to keep the installed app offline-ready without checking a large binary into git.
- 2026-04-08: Chose demo-mode launch arguments for UI tests so the test target can verify real UI flows without real capture permissions.
- 2026-04-09: Chose to keep `ScreenCaptureKit` close to its native audio output and convert after capture instead of forcing `16 kHz` mono in the stream configuration, because the forced format caused real runtime instability.
- 2026-04-09: Chose to treat unexpected system-audio capture stops as user-visible errors instead of silent logs, because the plan requires an explicit interruption state if capture breaks mid-session.
- 2026-04-09: Chose to keep exports disabled only while capture is active or flushing, so a partial session can still be copied or exported after an interruption.
- 2026-04-09: Chose to start microphone and system capture independently and keep the session alive when one source fails, because a flaky system-audio path should not erase a usable mic transcript.

## Outcomes & Retrospective

- The plan is implemented as a first working v1 path in the repo: permissions, capture, local Whisper transcription, live labeled transcript UI, autosave, relaunch recovery, and export all exist in code.
- The shipped shell no longer matches the original brutalist draft. It now uses the later transcript-first refresh, while still preserving the same underlying capture and session behaviors.
- The main compromise was packaging: the app bundles a helper executable and downloads the model during build instead of storing the model binary in git.
- The latest startup hardening changes were re-verified with a clean build and the `heedTests` unit suite.
- The main remaining gap is real-world validation, not missing product wiring. Device changes, long-run stability, and first-chunk latency still need more manual coverage on target hardware.
