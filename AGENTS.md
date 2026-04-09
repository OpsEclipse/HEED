# Agent Guide

Read in this order:

1. [`README.md`](README.md)
2. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
3. [`docs/FRONTEND.md`](docs/FRONTEND.md)
4. [`docs/PLANS.md`](docs/PLANS.md)
5. [`docs/RELIABILITY.md`](docs/RELIABILITY.md)
6. [`docs/SECURITY.md`](docs/SECURITY.md)

## Current Repo Reality

- Treat this repo as an early scaffold.
- Shipped code is only the app shell in [`heed/heedApp.swift`](heed/heedApp.swift) and [`heed/ContentView.swift`](heed/ContentView.swift).
- The meeting-transcript product is the intended direction, not current behavior.
- Mark planned behavior clearly. Do not describe it as implemented unless the code exists.

## Planning Rules

- Use a lightweight plan for small, low-risk, single-area changes.
- Use an `ExecPlan` for work with multiple steps, risk, persistence changes, permission changes, or cross-cutting impact [impact across many parts].
- Store deeper plans under `docs/exec-plans/`.
- Put active work in `docs/exec-plans/active/` and finished work in `docs/exec-plans/completed/` when those folders are needed.
- Follow the full standard in [`.agents/PLAN.md`](.agents/PLAN.md).

## Repo-Specific Rules

- The app target uses generated Info.plist values. Privacy strings may live in build settings until a real `Info.plist` is checked in.
- The app target currently defaults Swift code to `MainActor` [a Swift rule that keeps code on the UI thread]. Move heavy audio and transcription work off the main thread on purpose.
- Keep capture, mixing, transcription, persistence, and UI in separate modules once they exist. Do not let `ContentView` become the app’s control center.
- No database exists yet. If you add saved session data, document the schema [data shape], migration [how old saved data becomes new saved data], and rollback path in an `ExecPlan` first.
- Planned capture work will rely on Apple frameworks with unusual rules. ScreenCaptureKit needs screen-recording permission, and microphone capture needs microphone permission.

## Safe Reading Order For Product Work

1. Confirm current UI state in [`heed/ContentView.swift`](heed/ContentView.swift).
2. Confirm app wiring in [`heed/heedApp.swift`](heed/heedApp.swift).
3. Confirm build settings in [`heed.xcodeproj/project.pbxproj`](heed.xcodeproj/project.pbxproj).
4. Read the matching risk docs before changing permissions, persistence, or export behavior.

## Workflow Constraints

- Keep docs and code in sync.
- If the code and the plan disagree, document the mismatch.
- Do not change deployment targets, entitlements, or saved-data format without updating the docs set in the same change.
