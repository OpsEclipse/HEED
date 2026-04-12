# Batch Source-Split Transcription Design

## Goal

Replace the current live transcript flow with a batch transcription flow. Heed should record microphone audio and system audio into separate temporary files during the meeting, show no transcript text while recording, automatically transcribe both sources after the user clicks `Stop`, and then render two separate transcript panels: one for `MIC` and one for `SYSTEM`.

## Why This Change

The current live path is optimized for speed, but it is brittle for longer speech. The new design optimizes for capture completeness first. It treats recording like a tape recorder and transcription like a post-processing step instead of trying to do both at once.

## Chosen User Flow

1. The user clicks `Record`.
2. Heed requests permissions as it does today.
3. If recording starts, Heed opens one temp audio file for `MIC` and one temp audio file for `SYSTEM`.
4. During recording, the main canvas shows no transcript text.
5. The floating transport and utility rail still show recording state and elapsed time.
6. The user clicks `Stop`.
7. Heed stops both capture sources first.
8. Heed automatically starts transcription for the saved `MIC` file and saved `SYSTEM` file.
9. The UI enters a post-stop processing state until both source transcripts are ready.
10. When processing finishes, the main canvas renders two smaller transcript panels side by side.
11. The left panel shows `MIC transcript`.
12. The right panel shows `SYSTEM transcript`.

## Explicit Non-Goals

- No live transcript text during recording.
- No merged timeline [a single time-ordered transcript that mixes both sources together] in this design.
- No attempt to keep the current chunk-by-chunk live Whisper flow as a fallback.
- No change to the OpenAI task pass in this design. That flow can be adapted later once the new transcript shape is stable.

## UI Design

### Recording State

- Keep the current shell layout, floating transport, and utility rail.
- Remove live transcript rows from the recording state.
- Keep the recording screen minimal instead of showing placeholder transcript text.

### Processing State

- After `Stop`, the canvas should switch to a clear processing state.
- The user should understand that capture is complete and transcription is now running.
- The processing state should always show source-level status for both inputs:
  - `MIC: queued`, `processing`, `done`, or `failed`
  - `SYSTEM: queued`, `processing`, `done`, or `failed`

### Review State

- Replace the current centered mixed transcript view with two smaller panels.
- Each panel should scroll independently.
- Each panel should keep its own source label and transcript body.
- Empty-source results should be shown clearly, for example:
  - `No microphone transcript captured`
  - `No system audio transcript captured`

## Architecture

### Capture Layer

The current capture managers already convert audio into the app's `16 kHz` mono format. Instead of sending frames into a live chunker, each source should append converted frames into a dedicated temp audio file while recording.

Recommended file ownership:

- `MicCaptureManager`
  Still captures and converts mic frames.
- `SystemAudioCaptureManager`
  Still captures and converts system frames.
- New per-source writer component
  Owns appending converted frames into temp files.

This keeps capture focused on getting clean source audio onto disk reliably.

### Transcription Layer

After recording stops, Heed should transcribe each saved source file in one batch pass.

Recommended shape:

- New source-file transcription path that takes one temp file and one source label.
- The current `AudioChunker` [logic that splits audio into speech-sized pieces] should no longer sit on the main recording path.
- The current `SourcePipeline` can be replaced or heavily simplified so it handles post-stop batch transcription instead of live ingestion.

This change reduces moving parts during recording. It shifts complexity from "capture while transcribing" to "capture first, transcribe second."

### Recording Controller

`RecordingController` should change from:

- start capture
- stream frames into chunkers
- stream partial transcript segments into the UI

to:

- start capture
- stream frames into temp source files
- stop capture
- launch post-stop transcription jobs
- publish one split transcript result object when each source finishes

The controller should own a new processing state between `recording` and `ready`.

## Data Model And Persistence

This is the largest structural change in the design.

Today, sessions store one mixed list of `TranscriptSegment` values. The new design needs source-separated transcript results. There are two reasonable shapes:

1. Keep a shared session object, but replace the single mixed segment list with:
   - `micSegments`
   - `systemSegments`
2. Keep `segments`, but add a new grouped view model [a UI-focused data shape] that derives source panels from that list.

Recommendation:

Use explicit source-separated arrays in the saved session format:

- `micSegments`
- `systemSegments`

This matches the new product directly. It avoids rebuilding split panels from a mixed timeline later.

Because this changes saved session schema [the saved data shape], this work needs an `ExecPlan` [a multi-step implementation plan for risky work] before implementation. The plan must define:

- migration [how old saved sessions become the new shape]
- rollback path [how we safely back out if the new format fails]
- how old mixed sessions render in the new UI

## Failure Handling

- If one source records successfully and the other fails, Heed should still keep the successful source file and transcribe it.
- If one source transcribes successfully and the other fails, the UI should show one completed panel and one failed panel state.
- Temp files should be cleaned up after transcription succeeds or after the session is marked failed.
- If the app crashes during recording, recovery should keep the source temp files under the session folder and attempt post-relaunch recovery from those files before deleting anything.

## Export Impact

The current export helpers assume one mixed transcript. This design does not decide final export behavior yet. The follow-up implementation plan must choose one of these:

1. Export two separate source transcripts.
2. Export a synthetic merged transcript built only at export time.
3. Temporarily disable export for new split-format sessions until the export shape is final.

## Testing Focus

- Recording writes frames to the correct source temp file.
- Long speech does not disappear before transcription starts.
- Stop transitions into processing instead of trying to publish live rows.
- One-source failure does not erase the other source result.
- Saved sessions can load after the data-format migration.
- The review UI renders separate `MIC` and `SYSTEM` panels.

## Main Risks

- Saved session format changes will touch storage, UI, export, and tests together.
- Post-stop transcription may feel slower if the processing state is not clear.
- Long recordings can create large temp files, so cleanup rules must be reliable.
- The current OpenAI task flow assumes one transcript shape and will need a follow-up design update.

## Recommendation Summary

This design is a good fit if the main product goal is "capture everything first, then transcribe reliably." It trades live feedback for higher confidence in the final transcript. That is the right trade if longer speech is currently being lost.
