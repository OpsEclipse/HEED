# ExecPlan Standard For Heed

An `ExecPlan` is the repo’s full plan format for work that is too risky or too broad for a quick checklist. It should let a new engineer execute the work from the plan file alone, without hidden chat history.

## When To Use One

Use an `ExecPlan` when the work has one or more of these traits:

- more than one implementation step
- failure risk
- cross-cutting impact [impact across many parts]
- user-visible behavior changes
- permission changes
- persistence changes
- export changes
- unknowns that need to be resolved in sequence

Use a lightweight plan for small, local, low-risk work.

## Where It Lives

- Default location: `docs/exec-plans/`
- Active plans: `docs/exec-plans/active/`
- Completed plans: `docs/exec-plans/completed/`
- Short debt list: `docs/exec-plans/tech-debt-tracker.md`

## Writing Rules

- Write in plain language.
- Focus on outcomes, not tasks alone.
- Describe behavior that a reviewer can observe.
- Be specific about files, commands, UI states, permissions, and failure cases.
- If something is unknown, say so.
- Update the plan as the work changes. It is a living document.

## Required Sections

Every `ExecPlan` must include these sections.

### Goal

State the user-visible outcome in one short paragraph.

### Scope

List what the plan will change.

### Non-Goals

List what the plan will not change. This stops scope drift [work growing beyond the original goal].

### Risks

List the main things that could fail or cause regressions [bugs caused by a change].

### Open Questions

List decisions that are still unresolved.

### Validation Steps

List exact checks to run. Include commands, manual steps, and failure cases when relevant.

### Observable Acceptance Criteria

List the behaviors that must be true when the work is done. Make them easy to verify from the app, logs, files, or tests.

## Required Living Sections

These sections must be updated while the work is in flight.

### Progress

Keep a dated log of what is finished, what is in progress, and what is blocked.

### Surprises & Discoveries

Record new facts found during the work. This includes hidden constraints, framework limits, or code paths that behaved differently than expected.

### Decision Log

Record each important decision, why it was made, and what alternatives were rejected.

### Outcomes & Retrospective

Close the plan with what shipped, what did not, what follow-up work remains, and what the team learned.

## Good Heed-Specific Triggers

Start an `ExecPlan` before work like:

- adding microphone or screen-capture permissions
- choosing SwiftData vs JSON for sessions
- changing saved transcript format
- adding Whisper model download behavior
- introducing export flows
- changing deployment targets or entitlements [signed capability flags]

## Suggested Template

```md
# <Plan title>

## Goal

## Scope

## Non-Goals

## Risks

## Open Questions

## Validation Steps

## Observable Acceptance Criteria

## Progress
- YYYY-MM-DD: ...

## Surprises & Discoveries
- YYYY-MM-DD: ...

## Decision Log
- YYYY-MM-DD: ...

## Outcomes & Retrospective
- YYYY-MM-DD: ...
```
