# Terminal Spawn Handoff

## Goal

Turn the existing spawn approval gate into a real end-to-end Codex handoff. When the prep workspace already has a spawn request and the user clicks `Approve spawn`, Heed should open Terminal and start `codex` with a rich task brief right away instead of only changing in-app state.

## Scope

- Add a real spawn handoff path after approval in the task-prep controller.
- Build a Codex prompt from the active task, stable brief, open questions, evidence, spawn reason, prep chat history, and full transcript context.
- Launch Terminal without writing the prep brief to disk.
- Add the macOS Apple Events capability and usage string needed to automate Terminal.
- Update tests and docs for the new approval-to-handoff behavior.

## Non-Goals

- Persist prep chat, prep briefs, or launch history to disk.
- Add repo selection, working-directory selection, or multi-agent orchestration.
- Change the task-analysis pass or the transcript tool scope.
- Add new visual success chrome after a successful spawn handoff.

## Risks

- Terminal automation could fail because Apple Events permission is denied or not yet granted.
- Shell quoting could break if the prompt contains quotes or unusual punctuation.
- A launch bug could trigger duplicate handoffs from one approval.
- The new permission prompt could surprise users if the UI copy is vague.

## Open Questions

- Should a successful handoff leave the prep workspace open, or should it close automatically?
- Should a failed handoff show a retry action in the same spawn section, or only an error message?

## Validation Steps

- Run `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/TaskPrepControllerTests`.
- Run `xcodebuild test -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testCompileTasksFlowAppearsInlineAfterRecordingStops`.
- Run `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`.
- Manual check on macOS:
  Open `Prepare context`, wait for a spawn request, click `Approve spawn`, allow Terminal automation if prompted, and confirm a new Terminal session starts `codex` right away.
- Failure check on macOS:
  Deny Terminal automation and confirm Heed stays usable and shows a clear retry path.

## Observable Acceptance Criteria

- `Approve spawn` launches a real Terminal-based Codex handoff when a spawn request is pending.
- The launched Codex prompt includes task details, stable brief content, open questions, evidence, prep conversation context, and the full session transcript.
- Heed does not write the prep brief to a temp file just to launch Terminal.
- Successful handoff does not add extra visual confirmation chrome beyond the existing flow.
- Failed handoff leaves the user with a clear recovery path.

## Progress

- 2026-04-21: Read the repo docs, confirmed the current spawn gate only changes in-app state, and identified Terminal automation as the missing handoff step.
- 2026-04-21: Chose an `ExecPlan` because the real fix changes entitlements, privacy copy, and user-visible approval behavior.
- 2026-04-21: Started test-first coverage for immediate launch after approval and for rich prompt contents.
- 2026-04-21: Implemented a Codex prompt builder, a Terminal handoff launcher, a quiet success state in the prep panel, and a retry path for launch failures.
- 2026-04-21: Reworked the launcher after real-world feedback showed that one huge `codex <prompt>` terminal command could open Terminal without actually delivering the brief. The new flow launches `codex`, pastes the brief, and presses Return.
- 2026-04-21: Expanded the handoff payload after user feedback showed that the spawned agent still needed more context. The prompt now carries open questions plus the full transcript, not only the condensed brief and cited evidence.
- 2026-04-21: Added the Apple Events entitlement plus an `NSAppleEventsUsageDescription` string so Terminal automation has explicit macOS permission copy.
- 2026-04-21: Verified the controller path with `TaskPrepControllerTests` and verified the app still signs and builds with the new entitlement. The local UI harness still hits the known stale-process launch flake before it reaches the new spawn assertions.

## Surprises & Discoveries

- 2026-04-21: A `.command` temp-file launch would be simpler, but it would write the prep brief to disk and break the current memory-only privacy boundary.
- 2026-04-21: The app already ships with App Sandbox and Hardened Runtime, so Terminal automation needs an Apple Events capability and a matching usage description.
- 2026-04-21: The existing macOS UI harness can leave a stale debug-launched `heed` process attached to `debugserver`, which blocks later UI-test launches before the feature assertions run.

## Decision Log

- 2026-04-21: Prefer Apple Events over a temp script file so the handoff can stay memory-only. Rejected the temp-file path because it would persist sensitive prep context to disk.
- 2026-04-21: Keep the approval gate in app code and launch only after the explicit click. Rejected automatic launch on model request because the user wants approval to remain the real control point.

## Outcomes & Retrospective

- 2026-04-21: Core controller behavior, launcher wiring, docs, entitlement changes, and build verification are in place.
- 2026-04-21: `xcodebuild test -only-testing:heedTests/TaskPrepControllerTests` passed.
- 2026-04-21: `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build` passed.
- 2026-04-21: `xcodebuild test -only-testing:heedUITests/heedUITests/testCompileTasksFlowAppearsInlineAfterRecordingStops` is still blocked by the known local macOS stale-process launch flake, so UI verification is only partially complete.
