# Design

## What This File Is

This file tracks two things:

- the visual truth that exists in code today
- the planned minimalist refresh we want to implement next

If the code and this file disagree, call that out and update both this file and [`FRONTEND.md`](FRONTEND.md).

## Current Visual Truth

The shipped UI now leans minimalist with some brutalist leftovers.

- The app uses a near-black canvas and soft white text.
- The transcript sits in a centered reading column instead of a split-pane detail view.
- The sessions list is now a left sidebar column that is hidden by default and styled like a compact tree navigator.
- The main record or stop control is now one floating yellow button near the bottom.
- The bottom utility rail has been removed from the current shell.
- Transcript rows are no longer boxed. They now read as source-plus-time metadata followed by plain transcript text.

## Current Design Sources Of Truth

- Root UI in [`../heed/ContentView.swift`](../heed/ContentView.swift)
- Recording state text in [`../heed/Models/RecordingState.swift`](../heed/Models/RecordingState.swift)
- Front-end behavior in [`FRONTEND.md`](FRONTEND.md)

There is still no checked-in Figma file and no shared design token [named design value like a color, spacing step, or text size] system in the repo.

## Refresh Status

The core shell refresh is now implemented in code. Some polish is still open.

The new target is a sparse, writer-like transcript screen:

- a mostly black canvas
- a narrow readable transcript column
- very little chrome [the visible frame pieces around content, like bars and panels]
- one short empty-state prompt before recording starts
- a toggleable [can be shown or hidden] left sidebar column
- one floating yellow record or stop button instead of a heavy header bar

We still want some brutalist energy. We just want less boxy noise and more calm focus.

## Planned Visual Direction

### 1. Transcript First

The transcript should be the hero [main focal point].

- Put the transcript in a centered column instead of stretching it edge to edge.
- Keep line length readable. Aim for roughly `60` to `75` characters per line.
- Let empty space do real work. Negative space [intentional empty space that improves focus] should make the screen feel calm, not unfinished.

### 2. Empty State Copy

The canvas should stay almost blank before recording starts.

- Show only `Press record to begin the full transcript` when there is no transcript yet.
- Remove extra heading, readiness copy, and helper status text from the main canvas.
- Let the transcript itself become the only content once capture begins.

### 3. Sidebar As A Tool Drawer

The sessions list should still exist, but it should not dominate the screen.

- Keep the sidebar on the left.
- Let the main shell toggle it so the transcript can take over when needed.
- Treat it like a compact tree column that shifts the workspace, not a floating drawer.
- Default to the collapsed state when we want maximum focus.
- Show only session titles, using the first transcript line as the label until real title metadata exists.
- Use tight rows and a slim selected-state accent bar instead of boxed cards, but keep the shared near-black palette and existing type scale.

### 4. Floating Transport

The primary recording action should become a floating transport [a small control cluster for record or stop actions].

- Default anchor: bottom center
- Fallback anchor: top right only if bottom center blocks transcript reading or text selection
- Keep the button compact and obvious
- Use a yellow fill inspired by the reference `Create` button
- Keep the button flat and square, with no visible border radius

### 5. Brutalist, But Cleaner

Keep the directness of the current app, but remove extra framing.

- Fewer boxes
- Fewer full-width dividers
- Keep the sidebar matte and built into the window instead of floating above it
- No decorative gradients
- Allow the yellow record button as the one strong accent

## Planned Design System Rules

### Layout Primitives

These are the main building blocks we should implement later.

- `AppCanvas`
  A full-window black surface that holds everything.
- `TranscriptColumn`
  A centered reading column for live and saved transcript text.
- `SidebarHost`
  A left-side drawer for sessions and future navigation.
- `FloatingTransport`
  The one floating yellow record or stop button.

### Typography

Use typography to create hierarchy before using color.

- The transcript body should use one clean primary text face.
- Utility text can use a monospaced face for a tool-like feel.
- Avoid many font families. One main family plus one utility family is enough.
- The transcript should feel dense and intentional, not roomy like a marketing page.
- The floating button can use the main app type instead of utility monospace [fixed-width text].

### Color

The palette should stay restrained.

- Background: near-black
- Primary text: soft white, not bright blue-white
- Secondary text: muted gray
- Dividers: low-contrast gray when needed
- Record button: yellow
- Warning accent: amber

Color should explain state, not decorate the page.

### Motion

Motion should support clarity.

- Sidebar open or close should feel quick and quiet.
- Floating transport can fade or lift slightly on hover and focus.
- New transcript rows should appear with minimal motion so the screen stays calm.
- Avoid ornamental animation [movement used only for decoration].

## Planned Content Rules

- Keep labels short.
- Prefer sentence case over shouting in all caps unless a capture state really needs force.
- Keep pre-recording copy to one short sentence.
- Keep permission and error guidance visible, but do not let it turn the whole screen into a warning panel unless recording is blocked.

## Current Gaps Against The Planned Direction

- The yellow button still needs a final pass against the exact reference spacing and shade.
- Session labels are derived from transcript content, so empty or repetitive openings still need polish.
- UI automation coverage for the new shell still needs stabilization on macOS.

## Design Change Rule

If a future change affects layout, hierarchy, visual tone, or major states, update this file, [`FRONTEND.md`](FRONTEND.md), and the matching `ExecPlan` in [`docs/exec-plans/active/`](exec-plans/active/) together.
