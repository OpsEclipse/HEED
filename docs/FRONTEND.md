# Frontend

## Current UI Surface

The app has one route-like surface today.

- App launch opens one macOS window from [`../heed/heedApp.swift`](../heed/heedApp.swift).
- That window renders [`../heed/ContentView.swift`](../heed/ContentView.swift).
- The root view uses a split layout with a sessions sidebar on the left and the live transcript workspace on the right.

## Current States

- `idle`
  The app shows the transcript workspace, export controls, and permission guidance.
- `ready to record`
  The app can request recording on the next `Record` click.
- `recording`
  The timer runs and new `MIC` or `SYSTEM` rows stream into the transcript.
- `stopping`
  The app keeps the same screen while it flushes pending work.
- `error`
  The app shows blocked-state guidance in the header.

## Current Screens

These screens now exist in one main window:

- `live transcript`
  Record or stop, show timer, show status, stream transcript rows.
- `sessions list`
  Browse saved recording sessions.
- `session detail`
  Review one transcript and export it.
- `error states`
  Permission guidance and runtime errors appear inline in the header.

## Planned Interaction Pattern

The current front-end flow is:

1. App launches.
2. Permission state is checked.
3. The user grants required access.
4. Recording starts.
5. New transcript segments append to the live feed.
6. Recording stops and pending chunks flush.
7. The session stays visible and can be copied or exported.

## API Surfaces Used By The UI

There are no HTTP API endpoints in this repo today.

The planned UI will talk to local managers and frameworks instead:

- `PermissionsManager`
- `MicCaptureManager`
- `SystemAudioCaptureManager`
- `WhisperWorker`
- `SessionStore`
- Export helpers for clipboard and file writes

This matters because the front end is expected to be mostly local-first [working on the machine itself instead of calling a server].

## Major Modules To Expect

These modules are present in the app today.

- `RecordingController`
  Top-level window state and recording orchestration.
- `TranscriptWorkspace`
  Main live transcript screen.
- `TranscriptList`
  Scrollable transcript rows with auto-scroll.
- `SessionSidebar`
  Past sessions.
- `HeaderBar`
  Record button, timer, state, and guidance.
- `FooterBar`
  Export and permission refresh actions.

## Key UI States To Handle Well

- `idle`
- `requesting permissions`
- `ready to record`
- `recording`
- `processing latest chunk`
- `permission denied`
- `capture interrupted`
- `model unavailable`
- `autosave warning`
- `export success`
- `export failure`

## Frontend Risks

- A live feed that does not auto-scroll will feel broken.
- A slow first transcript chunk still depends on model load and hardware speed.
- Weak error copy around permissions will strand new users.
- Demo-mode hooks for UI tests must stay clearly separate from real capture mode.

## Where To Look

- Current root view: [`../heed/ContentView.swift`](../heed/ContentView.swift)
- Current app scene: [`../heed/heedApp.swift`](../heed/heedApp.swift)
- Design intent: [`DESIGN.md`](DESIGN.md)
- Product rules: [`PRODUCT_SENSE.md`](PRODUCT_SENSE.md)
