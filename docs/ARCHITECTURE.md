# Architecture

## Current Snapshot

Heed is now a real macOS SwiftUI app with a first end-to-end local transcript path.

- App entry: [`../heed/heedApp.swift`](../heed/heedApp.swift)
- Root scene: a single `WindowGroup` that shows `ContentView`
- Root UI: [`../heed/ContentView.swift`](../heed/ContentView.swift)
- Recording control layer: [`../heed/Controllers/RecordingController.swift`](../heed/Controllers/RecordingController.swift)
- Audio capture: [`../heed/Audio/`](../heed/Audio/)
- Permissions: [`../heed/Permissions/PermissionsManager.swift`](../heed/Permissions/PermissionsManager.swift)
- Transcription bridge: [`../heed/Transcription/`](../heed/Transcription/)
- Session storage and export: [`../heed/Storage/`](../heed/Storage/)
- Unit tests: [`../heedTests/heedTests.swift`](../heedTests/heedTests.swift)
- UI tests: [`../heedUITests/`](../heedUITests/)
- Build settings: [`../heed.xcodeproj/project.pbxproj`](../heed.xcodeproj/project.pbxproj)

The app now has a shared domain model, microphone capture, system-audio capture, chunking, a Whisper helper process, JSON persistence, export helpers, and demo-mode UI hooks for UI testing.

## Folder Ownership

- `heed/`
  App source. It now contains the app entry point, recording UI, orchestration layer, capture code, transcription bridge, models, storage, and assets.
- `heedTests/`
  Unit-test target. It covers transcript ordering, export formatting, and session recovery.
- `heedUITests/`
  UI-test target. It covers launch behavior and a demo-mode recording smoke test.
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
- User-selected file write access for exports: enabled

Those settings live in [`../heed.xcodeproj/project.pbxproj`](../heed.xcodeproj/project.pbxproj).

## Current System Shape

The current local meeting-transcript pipeline is:

1. `PermissionsManager`
   Owns microphone and screen-capture permission state.
2. `MicCaptureManager`
   Pulls microphone audio from `AVAudioEngine`.
3. `SystemAudioCaptureManager`
   Pulls system audio from `ScreenCaptureKit` and converts the stream’s native audio format into the app’s `16 kHz` mono pipeline.
4. Per-source chunk buffer
   Holds short rolling audio chunks for transcription.
5. `WhisperWorker`
   Sends one source at a time into the bundled Whisper helper on a background actor [a Swift unit that protects data from race conditions].
6. Session store
   Saves transcript sessions and keeps crash loss small.
7. Export layer
   Copies or writes transcript output as text or Markdown.

## Important Boundaries

These boundaries should stay clear as the app grows.

- UI should render state, not own audio capture.
- Capture code should not know about export or session history.
- Transcription should consume source-specific chunks, not reach into the UI.
- Persistence should own saved session format.
- Permission checks should live in one place so the app has one answer for “can we record?”

## Invariants

These invariants [rules that should always stay true] are either already true or should become true as the product is built.

- The app must never start recording without required user permissions.
- Heavy audio and transcription work must not block the main UI thread.
- Transcript sessions should survive normal app restarts.
- Export should not mutate the saved source session.
- If the product claims local transcription, raw meeting audio should not silently leave the machine.

## Cross-Cutting Concerns

These cross-cutting concerns [things that affect many parts] matter across the whole app.

- Privacy
  The product touches microphone audio, system audio, and saved transcripts.
- Latency
  Live transcript value drops fast if chunking or model work stalls.
- Recoverability
  A crash during recording should not erase the whole session.
- Platform constraints
  Screen capture and microphone capture have different permission flows and failure modes.
- Version support
  The app now targets macOS 14, but the build still uses the current macOS 26 SDK from Xcode 26.3.

## Where To Look First

- Start at [`../heed/heedApp.swift`](../heed/heedApp.swift) to see app boot.
- Read [`../heed/ContentView.swift`](../heed/ContentView.swift) to confirm current UI state.
- Read [`../docs/RELIABILITY.md`](RELIABILITY.md) before building capture or autosave.
- Read [`../docs/SECURITY.md`](SECURITY.md) before adding permissions, storage, or export.
