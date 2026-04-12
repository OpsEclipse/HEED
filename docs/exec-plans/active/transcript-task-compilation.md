# Transcript Task And Agent Context Pipeline

## Goal

Turn Heed's current task-review preview into a real two-pass OpenAI workflow. After the user stops recording, they can click `Compile tasks` to send the transcript to OpenAI and get grouped `Tasks` only. Each returned task should be one `Feature`, `Bug fix`, or `Miscellaneous` item. When they choose one task, Heed runs a second OpenAI pass, opens a right-side task context panel, and only then shows the real `Spawn agent` action.

## Scope

- Replace the fixture-based task compiler with a real OpenAI-backed first-pass compiler under [`heed/Analysis/`](../../../heed/Analysis/).
- Add a second-pass task-context compiler under [`heed/Analysis/`](../../../heed/Analysis/) so one task can expand into richer agent-ready context.
- Add a plain-text `Set API key` action to the bottom rail in [`heed/UI/WorkspaceShell.swift`](../../../heed/UI/WorkspaceShell.swift) and the matching settings surface in the app UI.
- Store the API key securely behind that settings UI.
- Add a right-side task context panel that keeps the transcript visible and contains the real `Spawn agent` action.
- Keep pass 2 temporary in memory and avoid any saved-data format change in v1.
- Add tests for prompt shaping, structured decoding, API-key setup states, second-pass panel states, and stale-request cancellation.
- Update [`docs/ARCHITECTURE.md`](../../ARCHITECTURE.md), [`docs/FRONTEND.md`](../../FRONTEND.md), [`docs/RELIABILITY.md`](../../RELIABILITY.md), and [`docs/SECURITY.md`](../../SECURITY.md) to match the shipped behavior.

## Non-Goals

- Live AI while recording
- Silent background upload of transcripts
- Replacing the local Whisper transcript path
- Saving task context to disk in v1
- Email or image attachment ingestion in v1
- Multi-provider account management in v1
- Prompt editing in v1
- Model switching in v1
- Full multi-provider agent orchestration in v1

## Risks

- API-key handling can become insecure if the settings UI writes to plain local settings instead of secure storage.
- The app may attach stale pass 1 or pass 2 results to the wrong session if cancellation is incomplete.
- Structured output parsing can fail if the model returns malformed JSON [a structured text format].
- The new side panel can make the transcript feel cramped if the layout shift is too heavy.
- The final `Spawn agent` destination is still undefined, so this feature can stall at the last step if that integration is not clarified early.

## Open Questions

- What exact label should replace the current task-row `Spawn agent` button: `Prepare context`, `Open context`, or `Review task`?
- What exact downstream target should the final `Spawn agent` action call once the context panel is ready?
- Should the side panel allow a lightweight user note before spawning, or should that wait for a later pass?

## Validation Steps

### Build And Test

- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`.
- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test`.

### Manual Product Checks

- Record a meeting, stop, and confirm `Compile tasks` appears only for a finished or recovered session with transcript text.
- Click `Set API key`, enter a key through the settings UI, relaunch if needed, and confirm the app can use that stored key.
- Click `Compile tasks` and confirm the `Suggested tasks` section appears under the transcript without hiding earlier transcript text.
- Confirm the busy state disables duplicate compile requests.
- Confirm a successful first-pass response renders only `Tasks`.
- Confirm each task is labeled as `Feature`, `Bug fix`, or `Miscellaneous`.
- Confirm one feature request with many supporting details stays grouped into one task when it describes one deliverable.
- Confirm each result row can show an evidence excerpt and jump back to the source transcript segment.
- Confirm each task row uses the renamed second-pass action instead of the old `Spawn agent` label.
- Click the second-pass action and confirm a right-side context panel opens without replacing the transcript.
- Confirm the panel shows loading, success, and retry states.
- Confirm the panel shows the real `Spawn agent` action only after task context is ready.
- Confirm a `no tasks found` response renders a clear empty state for the task section instead of a blank panel.
- Confirm a recovered session with transcript text can also compile successfully.
- Confirm recompiling replaces the previous in-memory result instead of stacking drafts.

### Failure Checks

- Remove the API key and confirm the app shows a clear setup error.
- Disconnect the network and confirm the app fails cleanly without affecting transcript review.
- Return malformed JSON from a test double [a fake test service] and confirm the app shows a retryable parse error.
- Start a compile request, switch sessions, and confirm stale results do not attach to the wrong session.
- Start a compile request, then recompile, and confirm the old result stays visible until the new one succeeds.
- Start a pass 2 request, switch tasks, and confirm stale context does not attach to the wrong task.
- Close the side panel during pass 2 and confirm the app cancels or safely ignores the stale result.

## Observable Acceptance Criteria

- A completed transcript session exposes one explicit post-meeting AI action in the current shell.
- The app sends transcript text to OpenAI only after the user clicks `Compile tasks` or the second-pass task action.
- The first-pass task list uses real OpenAI output instead of fixture data.
- Each task row offers a context-preparation action, not the final `Spawn agent` action.
- The app can open a right-side task context panel for one selected task without replacing the transcript.
- The panel contains the real `Spawn agent` action after context generation finishes.
- The canonical saved transcript format stays unchanged.

## Progress

- 2026-04-10: Updated the active plan to match the approved two-pass OpenAI design.
- 2026-04-10: Recorded the decision to keep pass 2 temporary and avoid any saved-data change in v1.

## Surprises & Discoveries

- 2026-04-10: The repo already has a clean first-pass seam through `TaskAnalysisCompiling`, so the fixture compiler can be replaced without redesigning the whole shell.
- 2026-04-10: The current UI already has a placeholder per-task agent action, which means the new second-pass entry point fits the shipped interface better than expected.
- 2026-04-10: An older active plan for this area assumed sidecar persistence and Keychain-first setup UI. That no longer matches the approved v1 shape and had to be rewritten.

## Decision Log

- 2026-04-10: Chose a two-pass OpenAI flow so task extraction stays lightweight while deeper task context remains on demand.
- 2026-04-10: Chose a right-side panel for pass 2 so the transcript remains visible during deeper review.
- 2026-04-10: Chose to keep pass 2 temporary in v1 to avoid persistence work and saved-data migration.
- 2026-04-10: Chose a bottom-rail `Set API key` action that opens app settings UI, while still planning secure storage behind that UI.
- 2026-04-10: Verified that `gpt-5.4-mini` is a current OpenAI model alias and that the Responses API is the right OpenAI surface for this path.

## Outcomes & Retrospective

- 2026-04-10: Planning only so far. No implementation has shipped yet.
- 2026-04-10: The main remaining unknown is the exact downstream destination for the final `Spawn agent` action.
