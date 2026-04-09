# Plans

## Why This Exists

Heed is still early. Small choices now will shape permissions, latency, saved-data format, and daily reliability later. This repo uses two planning depths so work stays proportional.

## Use A Lightweight Plan When

- the change is small
- one area owns the work
- rollback is easy
- the user-visible effect is obvious
- there is little chance of data loss or permission trouble

A lightweight plan can live in the task, PR, or commit notes.

## Use An `ExecPlan` When

- the work spans multiple steps
- the work crosses UI, capture, storage, or export boundaries
- the change touches permissions or entitlements [signed capability flags]
- the change touches persistence or file format
- the work has meaningful risk
- the team needs a durable record of decisions

## Where Plans Live

- deeper plans: `docs/exec-plans/`
- active plans: `docs/exec-plans/active/`
- completed plans: `docs/exec-plans/completed/`
- short debt list: `docs/exec-plans/tech-debt-tracker.md`

## Minimum `ExecPlan` Contents

Every `ExecPlan` must include:

- goal
- scope
- non-goals
- risks
- decision log
- progress log
- open questions
- validation steps
- observable acceptance criteria

The full standard lives in [`.agents/PLAN.md`](../.agents/PLAN.md).

## Repo-Specific Triggers

Start an `ExecPlan` before work like:

- first real audio capture implementation
- Whisper integration
- choosing a session storage format
- adding export behavior
- lowering the deployment target
- changing privacy strings, sandbox rules, or permission behavior

## Writing Standard

- Use plain language.
- Name real files and modules.
- Describe behavior a reviewer can observe.
- Record unknowns instead of hiding them.
- Update the plan as you learn. It is not a static spec.

## Consistency Rule

If you change planning guidance here, update [`.agents/PLAN.md`](../.agents/PLAN.md) and [`../AGENTS.md`](../AGENTS.md) in the same change.
