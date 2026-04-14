# OpenAI Two-Pass Task Flow Design

## Goal

Turn the current task-review preview into a real LLM-backed flow. After a meeting ends, `Compile tasks` should send the transcript to OpenAI and return a usable task list. When the user picks one task, Heed should run a second LLM pass, open a task context panel, and only then offer a final `Spawn agent` action.

## Chosen User Flow

1. The user records and stops as they do today.
2. The bottom rail shows `Compile tasks` for a completed or recovered session with transcript text.
3. Clicking `Compile tasks` sends the full transcript to OpenAI with a structured output request.
4. Heed renders the returned `Tasks` inside the existing inline `Suggested tasks` section.
5. Each task row shows a renamed action. The working label for v1 is `Prepare context`.
6. Clicking `Prepare context` sends that task plus the full transcript to OpenAI for a second structured output pass.
7. Heed opens a right-side task context panel without replacing the transcript.
8. The panel shows task summary, execution context, transcript evidence, and optional suggested skills.
9. The panel contains the real `Spawn agent` button.

## Settings And API Key

- The bottom rail gets a plain-text `Set API key` action.
- Clicking that action opens a lightweight AI settings surface inside the app.
- The user pastes the OpenAI API key there.
- The UI is a settings screen, but the stored secret should still use Keychain [Apple's secure secret store] behind the scenes.
- If no key is present, `Compile tasks` and `Prepare context` should fail with a clear setup message instead of a generic network error.

## Data And Persistence

- Pass 1 task results can be recomputed and do not need a new saved sidecar file in v1.
- Pass 2 task context is temporary only and should not be saved.
- The canonical transcript session format stays unchanged.
- No migration [a change that updates old saved data to a new shape] is needed for existing sessions.

## Architecture

### UI Ownership

- `RecordingController` stays focused on capture, transcription, and session review.
- `TaskAnalysisController` stays focused on the first-pass task review flow.
- Add a second controller for the detail panel state, or expand `TaskAnalysisController` carefully if that keeps responsibilities clear.
- `WorkspaceShell` remains the top-level composition point.

### LLM Service Layer

Add one dedicated OpenAI service layer with two operations:

- `compileTasks(session)`
- `prepareTaskContext(session, task)`

This layer should own:

- prompt building
- network request building
- model configuration
- structured response decoding
- user-facing error mapping

The UI should not know request details or JSON parsing details.

### OpenAI Request Shape

- Use the Responses API.
- Pin the model to `gpt-5.4-mini` for v1.
- Use structured output so both passes decode into strict app-owned result types.
- Keep prompts in one place so they can be tuned without leaking prompt text into multiple views or controllers.

## Pass 1 Output Shape

The first pass should return:

- `summary`
- `tasks`
- `noTasksReason`
- `warnings`

Each task should include:

- stable `id`
- short `title`
- short `details`
- `type` with one of `feature`, `bug_fix`, or `miscellaneous`
- optional `assigneeHint`
- `evidenceSegmentIDs`
- `evidenceExcerpt`

The prompt should keep one deliverable grouped into one task. If the transcript describes one feature with many supporting details, the model should return one feature task instead of splitting the work into many feature rows.

## Pass 2 Output Shape

The second pass should return one task context packet with fields like:

- `taskID`
- `title`
- `goal`
- `whyItMatters`
- `implementationNotes`
- `acceptanceCriteria`
- `risks`
- `suggestedSkills`
- `evidence`
- `questionsForUser`

This packet should be rich enough to review before spawning an agent, but still short enough to read inside a side panel.

## Error Handling

- Keep the transcript usable if either pass fails.
- Cancel stale requests when the user switches sessions or requests a fresh compile.
- If pass 2 fails, keep the task list visible and show the error inside the side panel area.
- Do not replace a good first-pass result with a broken one from a later retry.
- Surface setup errors, timeout errors, parse errors, and rate-limit errors as separate user-facing messages when practical.

## Testing Focus

- Prompt input shaping for both passes
- Strict decoding of structured outputs
- Cancellation when the user switches sessions
- API-key setup states
- Right-panel open, close, retry, and loading states
- Evidence-to-transcript jump behavior after pass 2

## Known Open Question

The product flow now defines where the real `Spawn agent` button lives, but the exact downstream target is still not locked. The implementation plan should keep that hook explicit and make the missing destination visible rather than hiding it behind a fake success.
