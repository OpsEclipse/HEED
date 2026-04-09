# Heed

Heed is a planned macOS app for live meeting transcription. The intended product is simple: capture microphone audio and system audio, turn it into text on-device, and keep a durable session history you can review or export.

Today, the repo contains the first real v1 path. The app has a brutalist recording UI, local permission gating, source-specific audio pipelines, Whisper-backed local transcription through a bundled helper tool, JSON session autosave, relaunch recovery, and text or Markdown export.

## What Exists Today

- App entry point: [`heed/heedApp.swift`](heed/heedApp.swift)
- Root view: [`heed/ContentView.swift`](heed/ContentView.swift)
- Unit test target: [`heedTests/heedTests.swift`](heedTests/heedTests.swift)
- UI test target: [`heedUITests/`](heedUITests/)
- Xcode project settings: [`heed.xcodeproj/project.pbxproj`](heed.xcodeproj/project.pbxproj)

Important current facts:

- The app is a single `WindowGroup`.
- The UI shows a sessions sidebar, live transcript timeline, export actions, and a large `Record` or `Stop` control.
- The project uses generated Info.plist values, not a checked-in `Info.plist`.
- The app target deploys to macOS `14.0`.
- App Sandbox [a macOS restriction layer] and Hardened Runtime [extra macOS runtime protections] are enabled.
- A build step bundles `WhisperChunkCLI` and downloads `ggml-base.en.bin` into the app bundle so the installed app works offline.

## Run It

Open the project in Xcode:

```sh
open heed.xcodeproj
```

Build from the command line:

```sh
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build
```

List the available target and scheme names:

```sh
xcodebuild -list -project heed.xcodeproj
```

Note:

- The first build downloads the Whisper model from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin` and caches it in DerivedData [Xcode’s build-output folder].

## Product Direction

The planned product path in this repo is:

1. Keep permission handling and recovery clear.
2. Improve real-world capture robustness across device changes.
3. Tune first-chunk and steady-state Whisper latency.
4. Add more manual smoke coverage for meeting apps.
5. Harden recovery and interruption behavior.

That direction is now captured in the docs set below so a new engineer does not need hidden chat context.

## Read Next

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): system map and boundaries
- [`docs/FRONTEND.md`](docs/FRONTEND.md): UI surface and states
- [`docs/PRODUCT_SENSE.md`](docs/PRODUCT_SENSE.md): user jobs and product heuristics [simple decision rules]
- [`docs/PLANS.md`](docs/PLANS.md): lightweight plans vs `ExecPlan`
- [`docs/RELIABILITY.md`](docs/RELIABILITY.md): failure modes and trust gaps
- [`docs/SECURITY.md`](docs/SECURITY.md): security-critical surfaces
- [`AGENTS.md`](AGENTS.md): short repo guide for coding agents
- [`.agents/PLAN.md`](.agents/PLAN.md): full `ExecPlan` standard

## Main Folders

- `heed/`: macOS app source and assets
- `heedTests/`: unit tests using `Testing`
- `heedUITests/`: UI tests using `XCTest`
- `docs/`: engineering and product docs

## Current Risks

- Real-world audio route changes still need deeper manual coverage.
- The bundled model is downloaded at build time, so source integrity checks rely on the recorded URL and checksum instead of a checked-in asset.
- The app has automated tests, but it still needs more long-run capture validation outside demo mode.
