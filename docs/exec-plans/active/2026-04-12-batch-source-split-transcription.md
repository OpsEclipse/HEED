# Batch Source-Split Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace live transcript streaming with file-backed recording and post-stop transcription, then render separate `MIC` and `SYSTEM` transcript panels without losing longer speech during capture.

**Architecture:** Keep capture simple and durable by writing converted `16 kHz` mono audio into per-source temp files during recording. After stop, run a batch transcription pipeline [a flow that processes saved audio after recording instead of while recording] that reads those files, generates source-specific transcript segments, and stores them in a split session model that still exposes a merged compatibility view for exports and the current task flow.

**Tech Stack:** SwiftUI, AVFoundation, ScreenCaptureKit, JSON session storage, bundled Whisper helper process

---

## Goal

Heed should behave like a reliable recorder first and a transcriber second. During recording, it should capture `MIC` and `SYSTEM` audio into separate source files with no live transcript text on screen. After the user clicks `Stop`, the app should automatically transcribe both sources, show clear per-source processing status, and then render two side-by-side transcript panels. Existing saved sessions should continue to load, and rollback to the old app should stay possible.

## Scope

- Change the recording path in [`heed/Controllers/RecordingController.swift`](../../../heed/Controllers/RecordingController.swift) from live chunk transcription to file-backed capture plus post-stop transcription.
- Add one file writer component under [`heed/Audio/`](../../../heed/Audio/) for per-source temp audio capture.
- Add one batch transcription coordinator under [`heed/Transcription/`](../../../heed/Transcription/) that reads saved source files after stop.
- Change [`heed/Models/TranscriptSession.swift`](../../../heed/Models/TranscriptSession.swift) to store split source segments while preserving a merged compatibility view.
- Update [`heed/Storage/SessionStore.swift`](../../../heed/Storage/SessionStore.swift) for migration [how old saved data becomes new saved data], temp-file recovery, and rollback-safe writes.
- Replace the mixed transcript canvas with split source panels in [`heed/UI/TranscriptCanvasView.swift`](../../../heed/UI/TranscriptCanvasView.swift) and related UI files.
- Keep export and task analysis working through a derived merged transcript view instead of redesigning those features in this plan.
- Update tests and docs that describe recording, transcription, storage, export, and UI behavior.

## Non-Goals

- Restoring live transcript text during recording
- Adding a settings toggle between live mode and batch mode
- Redesigning the OpenAI task flow
- Replacing the bundled Whisper helper binary
- Changing permissions, entitlements, or deployment target
- Shipping a merged transcript UI view

## Risks

- Writing only the new split schema could break rollback to the current app version if old builds only know about `segments`.
- Running one huge transcription request per full meeting could exceed practical Whisper limits, slow down badly, or fail on long recordings.
- Temp source files could leak disk usage if cleanup is incomplete.
- The UI could feel frozen after stop if processing status is not explicit and source-specific.
- Recovery logic could duplicate or lose work if a crashed recording session leaves behind partial files and partial JSON.

## Open Questions

- None for implementation start. This plan makes the following choices now so work can proceed without more design churn:
  - Keep exports using a derived merged transcript view.
  - Keep the current task-analysis flow using that same derived merged view.
  - Use post-stop file-backed chunking, not one giant Whisper call for the entire meeting.

## File Map

### Create

- [`heed/Audio/SourceRecordingFileWriter.swift`](../../../heed/Audio/SourceRecordingFileWriter.swift)
  Append converted PCM frames into a per-source file inside the active session folder.
- [`heed/Transcription/BatchSourceTranscriber.swift`](../../../heed/Transcription/BatchSourceTranscriber.swift)
  Read a saved source PCM file after stop, reuse chunking off the capture path, and return source-specific transcript segments plus processing status.
- [`heed/UI/SourceTranscriptPanelsView.swift`](../../../heed/UI/SourceTranscriptPanelsView.swift)
  Render two smaller transcript panels with source labels, empty states, and failed-source states.
- [`heedTests/SessionStoreMigrationTests.swift`](../../../heedTests/SessionStoreMigrationTests.swift)
  Cover legacy JSON decode, rollback-safe encode, and recovery from saved source files.
- [`heedTests/BatchSourceTranscriberTests.swift`](../../../heedTests/BatchSourceTranscriberTests.swift)
  Cover post-stop chunking and long-speech batch behavior.

### Modify

- [`heed/Controllers/RecordingController.swift`](../../../heed/Controllers/RecordingController.swift)
- [`heed/Models/RecordingState.swift`](../../../heed/Models/RecordingState.swift)
- [`heed/Models/TranscriptSession.swift`](../../../heed/Models/TranscriptSession.swift)
- [`heed/Storage/SessionStore.swift`](../../../heed/Storage/SessionStore.swift)
- [`heed/Storage/TranscriptExport.swift`](../../../heed/Storage/TranscriptExport.swift)
- [`heed/UI/TranscriptCanvasView.swift`](../../../heed/UI/TranscriptCanvasView.swift)
- [`heed/UI/WorkspaceShell.swift`](../../../heed/UI/WorkspaceShell.swift)
- [`heed/UI/UtilityRailView.swift`](../../../heed/UI/UtilityRailView.swift)
- [`heedTests/heedTests.swift`](../../../heedTests/heedTests.swift)
- [`heedTests/WorkspaceShellTests.swift`](../../../heedTests/WorkspaceShellTests.swift)
- [`README.md`](../../../README.md)
- [`docs/ARCHITECTURE.md`](../../ARCHITECTURE.md)
- [`docs/FRONTEND.md`](../../FRONTEND.md)
- [`docs/RELIABILITY.md`](../../RELIABILITY.md)

## Implementation Phases

### Phase 1: Make Session Storage Split-Aware Without Breaking Rollback

- Add `micSegments` and `systemSegments` to `TranscriptSession`.
- Keep `segments` as a derived compatibility property [a value the app computes from other stored values] that merges and sorts both arrays.
- Add a custom decoder that accepts both:
  - old sessions with only `segments`
  - new sessions with `micSegments` and `systemSegments`
- Keep the encoder rollback-safe by writing:
  - `micSegments`
  - `systemSegments`
  - `segments` as a merged compatibility field for one transition release
- Update `SessionStore.loadSessions()` so recovered legacy sessions still decode and save cleanly in the new format.
- Add migration tests before changing implementation.

### Phase 2: Persist Raw Source Audio During Recording

- Add `SourceRecordingFileWriter` to write little-endian `Int16` PCM frames into session-local files:
  - `mic.pcm`
  - `system.pcm`
- Create the session directory at recording start and hand the source file URLs to the writers.
- Replace the live `SourcePipeline.ingest(frames:)` path with append-only file writes during recording.
- Keep one-source survival behavior. If `SYSTEM` fails but `MIC` is still recording, keep writing `MIC`.
- Add tests for:
  - frame append order
  - empty write rejection
  - stop flush
  - one-source-only survival

### Phase 3: Move Chunking To Post-Stop Batch Transcription

- Keep `AudioChunker` but move it off the live capture path.
- Add `BatchSourceTranscriber` that:
  - reads a saved PCM file in buffered slices
  - feeds those frames through `AudioChunker`
  - sends resulting chunks to `WhisperWorker`
  - re-tags all returned segments with the owning source
- Do not send one full meeting file to Whisper in one call.
- Preserve chunk overlap and dedupe behavior in `WhisperWorker` so long speech still stitches cleanly.
- Add tests that prove a long saved speech sample becomes transcript output after stop even though no live segments were ever emitted.

### Phase 4: Add A Real Post-Stop Processing State

- Extend `RecordingState` with an explicit transcription-processing case instead of overloading `stopping`.
- Track per-source status:
  - queued
  - processing
  - done
  - failed
- In `RecordingController.stopRecording()`:
  - stop capture first
  - finalize file writers
  - transition to processing
  - launch post-stop transcription for each available source file
  - build the completed split session when both sources finish or fail
- Keep partial success behavior. If one source fails transcription, still save the successful source transcript.
- Update startup recovery so an interrupted recording with surviving source files can be retried or automatically recovered on relaunch before deletion.

### Phase 5: Replace The Mixed Canvas With Split Panels

- Keep the overall shell and floating transport.
- Change `TranscriptCanvasView` so it renders:
  - empty prompt when nothing has been recorded yet
  - no live transcript during recording
  - explicit per-source processing state after stop
  - side-by-side `MIC` and `SYSTEM` panels for completed or recovered sessions
- Add `SourceTranscriptPanelsView` for the final review layout.
- Keep the task appendix below the split panels for now, backed by the merged compatibility `segments` view.
- Update shell tests to verify:
  - no live text while recording
  - processing state after stop
  - split panels after completion

### Phase 6: Keep Export And Task Review Stable

- Keep `TranscriptExport` working by reading the merged compatibility `segments` property.
- Keep the current task-analysis and task-context flows reading `session.segments`.
- Add tests showing export output still contains both sources in time order even though the stored session is split.
- Document that UI is split, but export and tasks still use a merged derived view.

### Phase 7: Docs, Cleanup, And Verification

- Update docs so they describe:
  - batch post-stop transcription
  - source temp files
  - split panel review UI
  - new saved session schema and compatibility path
- Verify temp files are deleted after successful completion and after handled failures.
- Verify recovered sessions with split data and legacy sessions with mixed `segments` both render correctly.

## Validation Steps

### Build And Test

- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`
- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test`

### Manual Product Checks

- Start recording and confirm the canvas shows no live transcript rows.
- Speak into the mic for at least one longer sentence and confirm nothing is shown live.
- Stop recording and confirm the UI moves into a per-source processing state instead of returning directly to `Ready to record`.
- Confirm `MIC` and `SYSTEM` each show `queued`, then `processing`, then `done` or `failed`.
- Confirm a successful recording ends with two panels, one per source.
- Confirm a mic-only or system-only partial session still saves and renders one successful panel plus one empty or failed panel.
- Confirm `Copy text` still exports both sources in time order.
- Confirm `Compile tasks` still works for a newly split session.
- Relaunch the app with an older mixed session on disk and confirm it still loads.
- Relaunch the app after an interrupted recording with `mic.pcm` or `system.pcm` present and confirm recovery behavior does not delete those files before trying to recover.

### Failure Checks

- Force one source capture failure mid-recording and confirm the surviving source still records and transcribes.
- Simulate a transcription failure for one source and confirm the other source still renders and saves.
- Create a legacy `session.json` with only `segments` and confirm decode, save, and re-open all work.
- Confirm temp PCM files are removed after a successful completion path.
- Confirm temp PCM files are removed after a handled failed session path.

## Observable Acceptance Criteria

- Recording no longer streams transcript text into the UI while capture is in progress.
- Heed writes separate source audio files during recording and transcribes them only after stop.
- After stop, the app shows clear per-source processing status before final results appear.
- Completed and recovered sessions render two separate transcript panels labeled `MIC` and `SYSTEM`.
- Old sessions with only mixed `segments` still load.
- New sessions save split source transcripts and also preserve rollback compatibility for older builds.
- Export and task compilation still work on the migrated model through a merged compatibility view.

## Progress

- 2026-04-12: Approved the batch source-split design.
- 2026-04-12: Wrote this `ExecPlan` with a file-backed capture path, split session schema, and rollback-safe transition strategy.
- 2026-04-12: Implemented file-backed source capture, post-stop batch transcription, split session storage, split transcript panels, and matching test coverage.
- 2026-04-12: Updated `README.md`, `docs/ARCHITECTURE.md`, `docs/FRONTEND.md`, and `docs/RELIABILITY.md` to match the shipped flow.

## Surprises & Discoveries

- 2026-04-12: `TranscriptSession` is currently very small, which makes split-schema migration straightforward, but many consumers assume `segments` is stored directly.
- 2026-04-12: The current OpenAI task flow can likely survive this change unchanged if `segments` becomes a derived merged property instead of a stored field.
- 2026-04-12: Sending one entire meeting file to Whisper would be risky for long sessions, so "batch" needs to mean "after stop" rather than "one giant inference call."

## Decision Log

- 2026-04-12: Chose file-backed per-source capture instead of in-memory buffering so long meetings are safer under memory pressure.
- 2026-04-12: Chose automatic post-stop transcription instead of a manual `Transcribe recording` button.
- 2026-04-12: Chose two source panels only and rejected a merged transcript panel in the UI.
- 2026-04-12: Chose to keep `segments` as a derived compatibility property and write it during the transition release so rollback to older app builds stays viable.
- 2026-04-12: Chose to keep export and task-analysis flows on the merged compatibility view to avoid expanding scope.
- 2026-04-12: Chose post-stop chunking from saved files instead of one giant Whisper request so long sessions remain practical.

## Outcomes & Retrospective

- 2026-04-12: The planned recording change shipped in the local app code. Recording now stays blank while capture runs, then shows split `MIC` and `SYSTEM` panels after automatic post-stop transcription.
- 2026-04-12: Session storage now keeps `micSegments` and `systemSegments` while still encoding the merged `segments` field for export compatibility and rollback safety.
- 2026-04-12: The main follow-up after this plan is making recovery from interrupted temp source files feel more first-class, instead of merely preserving rollback-safe data on disk.
