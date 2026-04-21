# Task Prep Chat Workspace Design

## Goal

Replace the current static task-context panel with a real task-prep workspace. When the user clicks `Prepare context`, Heed should open a split layout with a streamed GPT-5.4 chat on the left and a live task context panel on the right. The AI should ask follow-up questions, build structured task context during the conversation, actively suggest when it believes the task is ready, and only call `spawn_agent` after the user clearly says it is allowed.

## Why This Change

The current `Prepare context` flow behaves like a one-shot summary. That is useful, but it is too rigid for real feature planning. The new flow should feel more like sitting with a strong product or engineering partner who asks for the missing details before work starts. The right-side panel stays as the living brief, while the left side becomes the working conversation.

## Chosen User Flow

1. The user finishes a transcript review and clicks `Prepare context` on one task row.
2. Heed opens a task-prep workspace inside the existing shell.
3. The left side takes about `70%` of the width and shows a chat interface.
4. The right side takes about `30%` of the width and shows the live context panel.
5. The first assistant turn is generated from the selected task, the transcript evidence, and the initial task draft. The reply must stream into the chat.
6. The user answers in the chat box and continues the conversation.
7. After every completed assistant turn, Heed updates the structured context panel with the latest stable draft.
8. The chat stays temporary and in memory only. Switching sessions or preparing context for a new task resets the workspace.
9. The AI must not auto-spawn. It keeps asking and refining until the user explicitly says it can spawn the agent.
10. If the AI believes it already has enough context, it should say so directly and ask for permission, for example: `I think we have enough context to proceed. Do you want me to spawn the agent now?`
11. Once the user gives clear approval, the model can call a `spawn_agent` tool and pass the selected task plus the best context it has assembled.

## Explicit Non-Goals

- No persistence for chat history or task-prep context in v1.
- No automatic spawn without explicit user approval.
- No change to saved transcript session schema.
- No attempt to support multiple open task-prep chats at once.
- No redesign of the broader transcript shell beyond what is needed for the new split workspace.

## UI Design

### Left Chat Workspace

- Use the existing Heed visual language: dark canvas, quiet chrome, yellow action emphasis, and compact controls.
- Show the selected task title at the top of the chat workspace so the user stays oriented.
- Render assistant and user messages as a readable threaded conversation.
- Add a bottom input row with a text field, send button, and small state text such as `Thinking`, `Streaming`, or `Ready to spawn`.
- Stream assistant replies into one growing message bubble instead of waiting for the full reply.
- Keep the chat usable after failures. A failed turn should show an error state plus a retry path without deleting earlier messages.

### Right Context Panel

- Keep the current right-side role in the shell, but change its content from static sections to a live structured brief.
- Keep the panel readable and stable while the assistant is still streaming.
- Show the last completed structured draft, not a flickering half-finished version.
- Recommended sections:
  - `Goal`
  - `Constraints`
  - `Acceptance criteria`
  - `Risks`
  - `Open questions`
  - `Evidence`
- Start the panel with task title, source evidence, and a short initial summary so the workspace does not look empty while the first streamed answer is still arriving.

### Layout Behavior

- `Prepare context` should still keep the shell visible instead of navigating away.
- The new workspace replaces the old static task panel path.
- The transcript shell stays behind the task-prep workspace structure, so this still feels like one app surface rather than a modal detour.
- The right panel width should stay near `320` to `360` points in practice, which is close to the current panel footprint.

## Architecture

### Controller Ownership

Add one new controller dedicated to the prep conversation.

Recommended name:

- `TaskPrepController`

Responsibilities:

- own the selected task and displayed session
- own the chat transcript
- own the stable structured context draft
- own in-flight streaming state for the current assistant turn
- own the assistant's readiness signal so the UI can show when the model thinks the task is ready to hand off
- enforce the user-approval rule for spawning
- reset temporary prep state on session change, task change, or explicit close

The existing controllers keep their current roles:

- `TaskAnalysisController` still owns pass-1 task compilation and task list UI.
- `RecordingController` still owns capture, transcription, and session review.
- `WorkspaceShell` stays the top-level composition point that decides when the prep workspace is visible.

### View Ownership

Recommended new views:

- `TaskPrepChatView`
  Owns the left-side threaded chat UI and input row.
- `TaskPrepContextPanelView`
  Owns the right-side structured context rendering.
- `TaskPrepWorkspaceView`
  Owns the two-pane composition and wires the controller state into both sides.

This keeps the split workspace easy to reason about. It is like giving the conversation, the brief, and the layout their own desks instead of piling everything onto one table.

### OpenAI Service Layer

The current task-context path is a one-request summary. The new flow needs a turn-based conversation layer on top of the existing OpenAI client.

Add a small service layer that can:

- send the current conversation turn to OpenAI
- stream assistant text back into the app
- decode the structured context update for the completed turn
- surface readiness suggestions from the model when it thinks enough context has been gathered
- surface tool calls such as `spawn_agent`
- surface read-only transcript tool calls

Recommended shape:

- keep `OpenAIResponsesClient` as the low-level request builder
- add a prep-specific service above it, such as `OpenAITaskPrepConversationService`

That service should own:

- prompt building
- streaming response parsing
- structured context decoding
- tool definition wiring
- user-facing error mapping

The UI should not know request JSON, stream event details, or parsing rules.

## Model Contract

Each assistant turn should produce three possible outputs:

1. Streamed assistant text for the visible chat reply.
2. One structured context draft for the right-side panel.
3. An optional `spawn_agent` tool call.

The assistant should also be allowed to say when it believes the context is good enough. That is a suggestion, not an action. The user still decides whether to proceed.

The model input for each turn should include:

- the selected task title and details
- transcript evidence tied to that task
- the current stable context draft
- the chat history so far
- a system rule that says `spawn_agent` is allowed only after clear user approval

The structured context draft should stay app-owned and explicit. Recommended fields:

- `summary`
- `goal`
- `constraints`
- `acceptanceCriteria`
- `risks`
- `openQuestions`
- `evidence`
- `readyToSpawn`

The `readyToSpawn` field is advisory. The app must still enforce the approval check in code.

## Tools During Prep

The prep conversation should expose two app-owned tools to the model.

1. `get_meeting_transcript`
   A read-only tool that returns the transcript for the currently selected session. This should let the model pull the full meeting transcript or relevant transcript slices when it needs more detail than the seeded evidence excerpts.
2. `spawn_agent`
   The final handoff tool. This remains blocked until the user gives explicit approval.

The transcript tool should be safe by default:

- it only reads from the currently displayed session
- it does not modify session data
- it does not bypass the app's existing local-only transcript storage
- it should support scoped reads when practical, such as `full transcript` or `selected evidence plus nearby lines`

This gives the model a way to look back at the meeting like flipping back a few pages in a notebook instead of trying to remember every earlier sentence from memory alone.

## Streaming Design

The assistant reply must stream into the left chat UI token by token [small pieces of generated text]. This should feel like live typing instead of waiting for a full finished block.

The right context panel should update in two phases:

1. Stable draft
   The last fully completed structured context.
2. In-progress draft
   The new structured update being built during the streamed turn.

The user-facing panel should continue to show the stable draft until the streamed turn finishes successfully. Then Heed promotes the new draft into the stable slot. This avoids jumpy UI and keeps the panel readable.

## Spawn Handoff

The user may say something direct like:

- `okay you're good to spawn the agent now`
- `go ahead and spawn it`

Before that happens, the assistant should be encouraged to suggest readiness when appropriate. For example, if it has enough context, it should ask whether the user wants it to spawn the agent now.

Only after explicit user approval may the model call `spawn_agent`.

When the tool call is allowed, Heed should package:

- the selected task
- the final stable structured context
- useful evidence excerpts
- a short prep-chat transcript
- the explicit user approval message when present

The UI should show that the handoff happened. Do not make the final action feel silent or invisible.

## Failure Handling

- If a turn fails, keep the existing chat history and stable context draft.
- If streaming stops halfway, mark that assistant turn as interrupted instead of pretending it completed.
- Allow retry for the failed turn without resetting the workspace.
- If the model tries to call `spawn_agent` before approval, reject the call and keep the conversation going.
- If the model asks for the transcript through `get_meeting_transcript`, return only data from the selected session and keep the tool read-only.
- Session switches and fresh `Prepare context` actions should cancel stale in-flight work so old replies do not land in the wrong workspace.

## Testing Focus

- Controller tests for message ordering, streaming assembly, stable-draft updates, reset behavior, and spawn guardrails.
- Client tests for streamed text events, structured draft parsing, readiness suggestions, transcript-tool parsing, tool-call parsing, and partial-stream failure handling.
- UI tests for `Prepare context` opening the two-pane workspace, streamed reply rendering, right-panel updates, and retry flows.
- Guardrail tests that prove `spawn_agent` is blocked before approval and allowed after an explicit approval message.

## Recommendation Summary

This design keeps the current task-review entry point, but turns it into a real prep workspace. The left side becomes the conversation. The right side becomes the living brief. Streaming keeps the app feeling responsive, and the guarded `spawn_agent` tool call makes the final handoff explicit instead of automatic.
