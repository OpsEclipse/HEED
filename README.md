# Heed

Heed is a macOS app for local meeting transcription and task prep. It captures microphone audio and system audio into separate local temp files during recording, transcribes both sources on-device after stop, saves transcript sessions locally, and can turn a finished transcript into compiled tasks plus a streamed task-prep workspace.

Today, the repo contains a real first v1 path. The app has a transcript-first window, a collapsible sessions sidebar, a floating record or stop button, local permission gating, separate source capture files, batch transcription after stop, Whisper-backed local transcription through a bundled helper tool, JSON session autosave, relaunch recovery, clipboard copy, a Keychain-backed OpenAI API key setting, a `Compile tasks` flow, and a split task-prep workspace that opens from `Prepare context`.

The prep workspace has two panes. The left side is a chat thread with streamed GPT-5.4 replies [replies that arrive in small pieces while they are generated]. The right side is a context brief panel that pins a stable structured draft after each completed turn. The model can ask for more transcript detail through a read-only `get_meeting_transcript` tool that is scoped to the selected session. If the model asks to spawn an agent, the app blocks that request until the user gives explicit approval. The prep chat and prep brief do not persist [stay saved] to disk.

## What Exists Today

- App entry point: [`heed/heedApp.swift`](heed/heedApp.swift)
- Root view: [`heed/ContentView.swift`](heed/ContentView.swift)
- Main shell views: [`heed/UI/`](heed/UI/)
- Recording control layer: [`heed/Controllers/RecordingController.swift`](heed/Controllers/RecordingController.swift)
- Task analysis and prep flow: [`heed/Analysis/`](heed/Analysis/)
- Unit test target: [`heedTests/`](heedTests/)
- UI test target: [`heedUITests/`](heedUITests/)
- Xcode project settings: [`heed.xcodeproj/project.pbxproj`](heed.xcodeproj/project.pbxproj)

Important current facts:

- The app is a single `WindowGroup`.
- The default shell is still transcript-first. `Prepare context` swaps the main canvas into the task-prep workspace.
- While recording, the app shows capture status instead of live transcript text.
- After stop, the app enters a processing state while it batch-transcribes both sources.
- Finished sessions render separate `MIC` and `SYSTEM` transcript panels.
- `Compile tasks` stays inline below the transcript. `Prepare context` opens the split prep workspace.
- The left prep pane shows streamed assistant turns and follow-up input. The right prep pane shows a fixed context brief with summary, goal, constraints, acceptance, risks, open questions, evidence, and spawn approval state.
- The transcript tool reads only from the selected session and returns formatted transcript lines when the model asks for them.
- Spawn stays blocked until the user clicks `Approve spawn`. The current shipped UI records that approval state, but it does not launch a final external handoff yet.
- Prep chat state is memory-only. Closing the workspace, switching sessions, or preparing a different task resets it.
- The bottom utility rail keeps the record button centered, puts a fullscreen toggle on the left, and keeps `Set API key` plus `Copy text` on the right. It also shows `Compile tasks` when the selected session is eligible.
- The project uses generated Info.plist values, not a checked-in `Info.plist`.
- The app target deploys to macOS `14.0`.
- App Sandbox [a macOS restriction layer] and Hardened Runtime [extra macOS runtime protections] are enabled.
- The app has outbound network access for explicit OpenAI task-analysis and task-prep calls.
- A build step bundles `WhisperChunkCLI` and downloads `ggml-base.en.bin` into the app bundle so the installed app works offline after build and install.

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

- The first build downloads the Whisper model from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin` and caches it in DerivedData [Xcode's build-output folder].

## Product Direction

The current near-term product path in this repo is:

1. Keep permission handling and recovery clear.
2. Improve real-world capture robustness across device changes.
3. Tune post-stop Whisper latency for long sessions.
4. Keep the task-prep workspace clear about what is temporary and what is saved.
5. Decide how an approved spawn request should turn into a real external handoff.
6. Add more manual smoke coverage for meeting apps and the prep workspace.
7. Harden recovery and interruption behavior across both capture and streaming prep turns.

That direction is captured in the docs set below so a new engineer does not need hidden chat context.

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
- The refreshed shell exposes clipboard copy, but file export actions are not currently visible in the UI even though the export code still exists.
- The prep workspace is intentionally temporary, so users can lose unsaved prep context when they close it or switch sessions.
- The macOS UI harness still has some local flake [a test that fails intermittently], so functional coverage is useful but not a full release signal by itself.
