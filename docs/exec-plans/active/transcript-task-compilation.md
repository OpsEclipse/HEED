# Transcript Task Compilation

## Goal

Add an explicit post-meeting AI review flow to Heed. After the user stops recording and the transcript is complete, they can click `Compile tasks` from the bottom utility rail. Heed then sends the transcript to the OpenAI API from native Swift code, receives structured output back, and shows that output in a review UI that matches the current transcript-first shell. The compiled result includes `Tasks`, `Decisions`, and `Follow-ups`, with `Tasks` shown as the primary actionable group.

## Current Shipped Slice

The repo now has the UI-only first slice of this plan in code.

- The utility rail can show `Compile tasks` for completed sessions that have transcript text.
- Clicking that action opens a collapsible inline `Suggested tasks` section under the transcript.
- The section supports loading, success, empty, and retry states.
- `Tasks` render first with selection checkboxes.
- `Decisions` and `Follow-ups` render as collapsed read-only groups.
- `Show source` jumps back to the matching transcript segment and briefly highlights it.
- This current build uses a local fixture compiler so the UI can be reviewed without network or persistence work.

Still planned:

- OpenAI-backed remote compilation
- `task-analysis.json` sidecar persistence
- AI settings and Keychain [Apple’s secure password store] key storage
- privacy notice and outbound-network permission changes

## Scope

- Add a new post-transcript action to the current shell in [`heed/UI/UtilityRailView.swift`](../../../heed/UI/UtilityRailView.swift) and [`heed/UI/WorkspaceShell.swift`](../../../heed/UI/WorkspaceShell.swift).
- Add a new analysis module under `heed/` for prompt building, remote request handling, response parsing, and local result storage.
- Add one new saved sidecar file beside each transcript session so AI output does not mutate the canonical transcript file.
- Add a small AI settings flow for OpenAI and store the API key in Keychain [Apple’s secure password store].
- Add a task-review surface that keeps the transcript visible and uses the current design tokens from [`heed/UI/HeedTheme.swift`](../../../heed/UI/HeedTheme.swift).
- Add tests for prompt input shaping, response parsing, sidecar persistence, and the main UI states.
- Update [`docs/ARCHITECTURE.md`](../../ARCHITECTURE.md), [`docs/FRONTEND.md`](../../FRONTEND.md), [`docs/DESIGN.md`](../../DESIGN.md), [`docs/RELIABILITY.md`](../../RELIABILITY.md), and [`docs/SECURITY.md`](../../SECURITY.md) with the shipped behavior.

## Non-Goals

- Live AI while recording
- Silent background upload of transcripts
- Replacing the local Whisper transcript path
- Auto-creating tickets, PRs, or code changes in other tools
- Multi-provider account management in v1
- True speaker attribution [automatic “who said this” labeling by person]
- Using AI output as the source of truth over the transcript itself
- Prompt editing in v1
- Model switching in v1
- Ticket, issue, or PR creation in v1

## Current State

- The finished transcript already stays on screen after `Stop`.
- The bottom utility rail already holds post-recording actions like `Copy as text`.
- The app has no network client today.
- The app is sandboxed and the checked-in entitlement file does not yet allow outbound network access.
- The canonical saved session is still one local `session.json` file under `~/Library/Application Support/Heed/Sessions/<session-id>/`.
- The repo has no existing Node, TypeScript, or backend layer, so this feature should fit the current native Swift app shape.
- The new inline review UI is now present, but it is still powered by local fixture data instead of the planned OpenAI path.

## Proposed User Flow

1. The user records and stops as they do today.
2. The selected finished session shows a new utility-rail action: `Compile tasks`.
3. Clicking `Compile tasks` opens a collapsible inline review section under the transcript and starts the request.
4. The review section shows a short progress state while Heed builds the prompt, sends the transcript, and waits for a structured response.
5. When the response returns, the section shows:
   - one short summary
   - a `Tasks` section shown first
   - collapsed `Decisions` and `Follow-ups` sections
   - evidence snippets and source jumps that point back to the transcript
6. The user can keep the compiled result or run `Compile again`.
7. The transcript stays visible the whole time. The app does not jump to a different screen.

The current shipped UI-only slice matches this flow, except the compile step is still local fixture generation instead of a real remote request.

## Recommended UI Pattern

Use one new utility-rail action, `Compile tasks`, and render the result inline in the transcript column as a collapsible `Suggested tasks` section. Do not use a modal [a pop-up that takes focus] and do not replace the whole screen.

- This keeps the transcript as the hero.
- This fits the current shell, which already uses the transcript column as the main reading surface.
- This avoids adding a new permanent panel to a layout that is intentionally quiet.
- This lets the task draft feel like a reviewed appendix [a section added after the main content], not a separate mode.

### Review Section States

- `Not compiled`
  Show one sentence: `Compile this meeting into action items.`
- `Compiling`
  Show quiet progress text like `Preparing task draft`.
- `Compiled with tasks`
  Show `Suggested tasks`, a short helper like `Review before creating`, then the `Tasks` list and collapsed `Decisions` plus `Follow-ups`.
- `Compiled with no tasks`
  Show `No clear tasks found`, but still allow `Decisions` and `Follow-ups` if they exist.
- `Failed`
  Show `Could not compile tasks` and a retry action.

### Utility Rail Labels

- Ready state: `Compile tasks`
- Busy state: `Compiling…`
- Success state: `Recompile`
- Error state: `Try again`
- Existing actions stay visible: `Copy as text`, `Full screen`

### Task Row Shape

Each task row should show:

- selection checkbox
- short title
- one-sentence explanation
- task type, like `Feature`, `Bug`, `Follow-up`, or `Decision`
- one short evidence excerpt from the transcript
- an optional assignee hint only if the transcript states it clearly
- one quiet text action: `Show source`

Do not show fake precision like `91% confidence` in v1. Trust will come more from evidence than from a made-up score.

In v1, only `Tasks` are selectable. `Decisions` and `Follow-ups` are read-only context.

## Architecture Plan

### 1. Keep Transcript Storage Canonical

Do not put AI output into [`heed/Models/TranscriptSession.swift`](../../../heed/Models/TranscriptSession.swift) or the saved `session.json` shape in v1.

Instead, store AI output in a sidecar file:

- `~/Library/Application Support/Heed/Sessions/<session-id>/task-analysis.json`

Why this is the safer choice:

- old sessions need no migration [a change that updates old saved data to a new shape]
- rollback is easy because the transcript file stays untouched
- transcript persistence and AI persistence stay separate
- failed or partial AI runs cannot corrupt the transcript session

### 2. Add A Separate Analysis Module

Create a new `heed/Analysis/` area with clear ownership.

Expected new types:

- `TaskAnalysisStore`
  Loads and saves `task-analysis.json`.
- `TranscriptTaskCompiler`
  Builds the prompt and runs the remote request.
- `TaskAnalysisClient`
  Provider-facing network client behind a small protocol [a Swift interface contract].
- `TaskAnalysisResult`
  Top-level parsed result.
- `CompiledTask`
  One extracted task candidate.

Do not move this work into `ContentView`. Keep analysis logic out of the UI layer.

### 3. Keep Recording And Analysis As Separate Controllers

[`heed/Controllers/RecordingController.swift`](../../../heed/Controllers/RecordingController.swift) should stay focused on capture, transcription, and session selection.

Add one new controller for post-transcript AI work, likely:

- `TaskAnalysisController`

This controller should own:

- current selected session analysis
- compile state
- retry state
- last analysis error
- inline section expansion state
- per-task selection state
- source-jump state for evidence navigation

[`heed/ContentView.swift`](../../../heed/ContentView.swift) can compose both controllers into [`heed/UI/WorkspaceShell.swift`](../../../heed/UI/WorkspaceShell.swift).

### 4. Use Native Swift Networking With One Provider

V1 should target the OpenAI API directly from the macOS app.

- Do not add a JavaScript helper layer.
- Do not add a backend for v1.
- Keep the app native and add one small Swift HTTP [web request] client for this feature.
- Keep provider-specific headers and model names in one place so a later adapter [a layer that translates one interface to another] is still possible if needed.

This is the best fit for the current repo shape and the fastest path to a clean v1.

### 5. Use Structured Output, Not Free-Form Text

The request should ask for a strict JSON [JavaScript Object Notation, a structured text format] response.

Planned response shape:

- `summary`
- `tasks`
- `decisions`
- `followUps`
- `noTasksReason`
- `warnings`

Each task should include:

- `id`
- `title`
- `details`
- `type`
- `assigneeHint`
- `evidenceSegmentIDs`
- `evidenceExcerpt`

The parser should reject malformed or partial output and surface a retryable failure instead of guessing.

`decisions` and `followUps` should use the same evidence-linking fields so the UI can support `Show source` consistently across all result groups.

## Planned Saved Data Shape

`task-analysis.json` should contain:

- `sessionID`
- `createdAt`
- `updatedAt`
- `providerID`
- `modelID`
- `status`
- `summary`
- `tasks`
- `decisions`
- `followUps`
- `noTasksReason`
- `warnings`

Each saved task should contain:

- `id`
- `title`
- `details`
- `type`
- `assigneeHint`
- `evidenceSegmentIDs`
- `evidenceExcerpt`

Each saved decision and follow-up should contain:

- `id`
- `title`
- `details`
- `evidenceSegmentIDs`
- `evidenceExcerpt`

## Migration And Rollback

### Migration

- No migration is needed for old sessions.
- If `task-analysis.json` is missing, the app should treat that session as “not compiled yet.”
- If the file is present but unreadable, the app should show a non-destructive error and let the user compile again.
- Recompiling the same session should replace the old sidecar contents instead of keeping history in v1.

### Rollback

- Roll back by removing the new analysis UI and ignoring `task-analysis.json`.
- Existing `session.json` files remain valid because the transcript format does not change.
- The sidecar file can be safely left on disk even if the feature is disabled in a later build.

## Security And Permissions Plan

- Add outbound network entitlement support if the sandbox requires it.
- Keep transcript upload as an explicit user action only.
- Never auto-send the live transcript.
- Store the OpenAI API key in Keychain, not in `UserDefaults` [a plain local app settings store].
- Add a simple AI settings sheet for entering the key.
- Show a one-time privacy notice before first compile so the user knows this step sends transcript text to a remote service.
- Update [`docs/SECURITY.md`](../../SECURITY.md) to name OpenAI, the data sent, the key storage path, and the new network behavior.

## Reliability Plan

- Add a bounded timeout for compile requests.
- Support cancellation if the user collapses the review section or changes sessions mid-request.
- Persist only completed analysis results, not half-parsed partial responses.
- Keep the last good analysis visible until a new compile succeeds.
- Treat provider failures as non-destructive. The transcript stays usable even if analysis fails.
- If the user recompiles, replace the last good analysis only after the new result parses successfully.

## Open Questions

- What exact disabled or placeholder treatment should `Create selected` use in v1 if creation is intentionally out of scope?
- Should the first OpenAI-backed version pin one model or expose a hidden internal fallback model choice for development only?

## Validation Steps

### Build And Test

- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`.
- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test`.

### Manual Product Checks

- Record a meeting, stop, and confirm `Compile tasks` appears only for a finished or recovered session with transcript text.
- Click `Compile tasks` and confirm the `Suggested tasks` section appears under the transcript without hiding earlier transcript text.
- Confirm the busy state disables duplicate compile requests.
- Confirm a successful response renders `Tasks`, `Decisions`, and `Follow-ups`, with only `Tasks` expanded by default.
- Confirm each result row can show an evidence excerpt and jump back to the source transcript segment.
- Confirm a “no tasks found” response renders a clear empty state for the task section instead of a blank panel.
- Confirm switching to another session loads that session’s saved analysis if it exists.
- Confirm closing and reopening the app preserves the last saved analysis result.
- Confirm a recovered session with transcript text can also compile successfully.
- Confirm recompiling replaces the previous saved result instead of stacking drafts.

### Failure Checks

- Remove the API key and confirm the app shows a clear setup error.
- Disconnect the network and confirm the app fails cleanly without affecting transcript review.
- Return malformed JSON from a test double [a fake test service] and confirm the app shows a retryable parse error.
- Start a compile request, switch sessions, and confirm stale results do not attach to the wrong session.
- Start a compile request, then recompile, and confirm the old result stays visible until the new one succeeds.

## Observable Acceptance Criteria

- A completed transcript session exposes one explicit post-meeting AI action in the current shell.
- The app sends transcript text to OpenAI only after the user clicks that action.
- The compile result comes back as structured `Tasks`, `Decisions`, and `Follow-ups`, not just raw prose.
- The user can review extracted tasks without leaving the transcript-first workspace.
- The user can jump from compiled evidence back to the source transcript.
- Old saved sessions still load normally, even if they have never been compiled.
- A failed AI compile never damages the saved transcript session.

## Progress

- 2026-04-09: Created this `ExecPlan` before implementation started.
- 2026-04-09: Landed the UI-only first slice with the utility-rail `Compile tasks` action, inline `Suggested tasks` appendix, local fixture-backed loading and result states, task selection, and transcript source jumps.
- 2026-04-09: Updated `FRONTEND.md` and `DESIGN.md` so the docs describe the shipped inline review UI instead of implying the full OpenAI-backed stack is already done.

## Surprises & Discoveries

- 2026-04-09: The current app has no network client at all, so AI analysis is a real new system boundary, not a small extension of existing code.
- 2026-04-09: The checked-in sandbox entitlement file does not yet include outbound network access.
- 2026-04-09: The current transcript-first shell already has the right post-stop action area in the utility rail, so the new feature can fit the shipped layout without adding a new top bar or replacing the main screen.
- 2026-04-09: An inline results section fits the current shell better than a new docked drawer because it keeps chrome low and lets the transcript stay the main surface.
- 2026-04-09: The repo has no existing web or backend stack, so the Vercel AI SDK path would add unnecessary infrastructure [supporting technical pieces] for v1.

## Decision Log

- 2026-04-09: Chose a sidecar `task-analysis.json` file instead of changing `session.json`, because that keeps transcript persistence stable and makes rollback simple.
- 2026-04-09: Chose an inline collapsible `Suggested tasks` section instead of a docked drawer, modal, or full-screen replacement, because the transcript should stay visible and the shell should stay quiet.
- 2026-04-09: Chose evidence-backed task rows over numeric confidence badges, because trust should come from visible transcript grounding instead of fake precision.
- 2026-04-09: Chose balanced extraction instead of conservative-only or aggressive-only so the feature captures useful work items without leaning too hard into hallucination [AI making up content that was not really supported].
- 2026-04-09: Chose to include `Tasks`, `Decisions`, and `Follow-ups`, with `Tasks` primary and selectable while the other groups stay collapsed and read-only in v1.
- 2026-04-09: Chose direct OpenAI API calls from native Swift instead of a JavaScript helper or backend because the repo is already a native macOS app and has no existing server layer.
- 2026-04-09: Chose an in-app AI settings sheet backed by Keychain for API key entry.

## Outcomes & Retrospective

- 2026-04-09: The transcript-first shell was the right home for this feature. The inline appendix kept the transcript as the hero and avoided a new mode shift.
- 2026-04-09: Shipping the UI against a local fixture compiler let the team review hierarchy, copy, evidence jumps, and selection behavior before taking on network, persistence, and settings risk.
- 2026-04-09: The remaining work is now clearly the non-UI part of the plan: remote OpenAI calls, sidecar persistence, settings, privacy messaging, and entitlement changes.
