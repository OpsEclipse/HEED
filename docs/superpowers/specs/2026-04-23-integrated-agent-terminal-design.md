# Integrated Agent Terminal Design

## Goal

After the user approves a spawn request, Heed should keep the user inside the task-prep workspace and turn the left chat pane into a real integrated terminal. Codex should run inside that terminal with compressed handoff context, while the right panel keeps showing the structured brief.

## Why This Change

The current spawn flow opens Terminal.app through Apple Events [macOS app-to-app automation messages]. That works, but it breaks the workspace. The user has to leave Heed right when the task becomes actionable.

The desired flow is closer to an IDE [integrated development environment, an app that combines editing, terminal, and project tools]. The prep chat gathers context. Approval turns that same pane into the work surface. It feels like the conversation becomes the agent session instead of handing the user a separate window.

## Chosen User Flow

1. The user opens `Prepare context` for a compiled task.
2. The left pane shows the prep chat.
3. The right pane shows the stable context brief.
4. The assistant asks to spawn when it thinks the task is ready.
5. The user clicks `Approve spawn`.
6. Heed replaces the left chat pane with a terminal view.
7. Heed starts `codex` in the project directory.
8. Heed sends a compressed handoff prompt into the Codex terminal session.
9. The user can interact with Codex directly in the terminal.
10. The right panel stays visible as the handoff brief and spawn status surface.

## Non-Goals

- Do not keep launching Terminal.app for the happy path.
- Do not persist prep chat, prep briefs, terminal logs, or spawn history to disk.
- Do not change the saved transcript session schema [data shape].
- Do not add multi-agent orchestration [running and coordinating many agents] in this step.
- Do not build a fake terminal that only looks like a terminal.

## Terminal Behavior

The left pane should be a real terminal backed by a PTY [pseudo-terminal, a program interface that lets an app talk to a shell like Terminal does]. A PTY matters because CLIs [command-line apps] often change behavior when they detect a real terminal. It is the difference between speaking to someone on a phone call and leaving a note under the door.

The first version should support:

- launching `codex`
- writing the compressed prompt into stdin [the input stream a process reads from]
- reading stdout and stderr [the normal output stream and error output stream]
- accepting keyboard input from the user
- preserving terminal-style line wrapping and scrolling
- showing a clear failure state with retry

## Handoff Context

The terminal should not receive the right-side panel verbatim. It should receive a compressed prompt [a shorter version that keeps the important facts and drops repeated wording].

The compressed prompt should include:

- selected task title and type
- one short objective
- the most important constraints
- acceptance criteria
- unresolved questions
- top evidence excerpts
- a short note that the full transcript exists in Heed, but was not pasted wholesale

The full transcript should not be pasted into the terminal by default. If later work needs full-transcript access, add an explicit local file or tool flow with a separate privacy review.

## UI Design

The workspace keeps its two-pane layout.

Left pane states:

- `chat`
  Shows the existing prep chat before approval.
- `terminalLaunching`
  Shows terminal chrome and a small launch status while Codex starts.
- `terminalRunning`
  Shows the interactive terminal.
- `terminalFailed`
  Shows the error and a retry action.
- `terminalEnded`
  Shows the terminal output and an option to start another session if needed.

Right pane changes:

- Rename or visually shift the spawn section after launch so it reads as the active handoff state.
- Keep the brief visible during the terminal session.
- Do not add extra success chrome that competes with the terminal.

## Architecture

Add a terminal session layer below `TaskPrepController`.

Suggested types:

- `TaskPrepTerminalSession`
  Owns the PTY, the `codex` process, terminal output, input writes, resize handling, and teardown.
- `TaskPrepTerminalSessionLaunching`
  A protocol [a named contract that types can implement] for tests and real launch code.
- `TaskPrepTerminalView`
  Renders the terminal buffer and forwards key input.
- `TaskPrepAgentHandoffPromptBuilder`
  Keeps owning prompt creation, but changes from a full transcript packet to a compressed handoff packet.

`TaskPrepController` should own the terminal state because approval already lives there. The UI should not launch processes directly.

## Failure Handling

- If `codex` cannot be found, show a clear error and keep retry available.
- If PTY creation fails, show a clear error and keep the right-side brief intact.
- If the process exits, keep the terminal transcript in memory until the workspace closes.
- If the user closes the prep workspace, stop the terminal session.
- If the selected session changes, stop the terminal session and reset prep state.

## Security And Privacy

This change reduces Apple Events exposure because the happy path no longer drives Terminal.app. It adds a new local process boundary [the line where Heed starts and talks to another program], so the app must keep the handoff explicit and user-approved.

Guardrails:

- Spawn stays blocked until the user clicks approval.
- The prompt stays in memory.
- Terminal output stays in memory.
- No transcript or terminal log is saved automatically.
- The full transcript is not pasted by default.

## Testing Focus

- Prompt-builder tests prove the handoff is compressed and does not include the full transcript by default.
- Controller tests prove approval switches the workspace into terminal mode.
- Terminal launcher tests prove `codex` is started with the expected working directory and initial prompt.
- UI tests or focused view tests prove the left pane switches from chat to terminal.
- Failure tests cover missing `codex`, PTY launch failure, and process exit.

## Recommendation Summary

Build a real PTY-backed integrated terminal and make it the post-approval state of the left prep pane. Keep the right pane as the stable brief. Send compressed context, not the sidepanel verbatim and not the full transcript by default.
