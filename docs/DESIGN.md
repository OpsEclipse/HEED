# Design

## What This File Is

This file tracks two things:

- the visual truth that exists in code today
- the follow-up polish work we still want after the shipped refresh

If the code and this file disagree, call that out and update both this file and [`FRONTEND.md`](FRONTEND.md).

## Current Visual Truth

The shipped UI now leans minimalist with some brutalist leftovers.

- The app uses a near-black canvas and soft white text.
- The transcript sits in a centered reading column instead of a split-pane detail view.
- The sessions list is a left sidebar column that is hidden by default and styled like a compact tree navigator.
- The main record or stop control is one floating yellow button near the bottom.
- The bottom utility rail is still present. It stays quiet and text-first.
- Transcript rows are not boxed. They read as source-plus-time metadata followed by plain transcript text.
- The post-transcript `Suggested tasks` review renders inline as one subdued panel below the transcript, not as a modal or side panel.

## Current Design Sources Of Truth

- Root UI in [`../heed/ContentView.swift`](../heed/ContentView.swift)
- Shared visual tokens in [`../heed/UI/HeedTheme.swift`](../heed/UI/HeedTheme.swift)
- Recording state text in [`../heed/Models/RecordingState.swift`](../heed/Models/RecordingState.swift)
- Front-end behavior in [`FRONTEND.md`](FRONTEND.md)

There is still no checked-in Figma file. The repo now does have a small shared design token [named shared value like a color, spacing step, or motion timing] layer in `HeedTheme`.

## Refresh Status

The core shell refresh is now implemented in code. Some polish is still open.

The shipped shell is a sparse, writer-like transcript screen:

- a mostly black canvas
- a narrow readable transcript column
- very little chrome [the visible frame pieces around content, like bars and panels]
- one short empty-state prompt before recording starts
- a toggleable [can be shown or hidden] left sidebar column
- one floating yellow record or stop button instead of a heavy header bar
- one quiet bottom utility rail for status, copy, and fullscreen
- one inline review appendix for suggested tasks after a transcript is complete

We still want some brutalist energy. We just want less boxy noise and more calm focus.

## Visual Direction To Keep

### 1. Transcript First

The transcript should stay the hero [main focal point].

- Keep the transcript in a centered column instead of stretching it edge to edge.
- Keep line length readable. Aim for roughly `60` to `75` characters per line.
- Let empty space do real work. Negative space [intentional empty space that improves focus] should make the screen feel calm, not unfinished.
- When post-meeting review appears, treat it like an appendix under the transcript, not a new primary surface.

### 2. Empty State Copy

The canvas should stay almost blank before recording starts.

- Show only `Press record to begin the full transcript` when there is no transcript yet.
- Avoid extra heading, readiness copy, and helper status text in the main canvas.
- Let the transcript itself become the main content once capture begins.

### 3. Sidebar As A Tool Drawer

The sessions list should still exist, but it should not dominate the screen.

- Keep the sidebar on the left.
- Let the shell toggle it so the transcript can take over when needed.
- Treat it like a compact tree column that shifts the workspace, not a floating drawer.
- Keep showing only session titles, using the first transcript line as the label until real title metadata exists.
- Keep tight rows and a slim selected-state accent bar instead of boxed cards.

### 4. Floating Transport

The primary recording action should stay a floating transport [a small control cluster for record or stop actions].

- Default anchor: bottom center
- Fallback anchor: top right below narrow widths
- Keep the button compact and obvious
- Keep the button flat and square, with no visible border radius
- Keep yellow as the one strong accent

### 5. Brutalist, But Cleaner

Keep the directness of the app, but remove extra framing.

- Fewer boxes
- Fewer full-width dividers
- Keep the sidebar matte and built into the window instead of floating above it
- No decorative gradients
- Let the yellow record button stay the loudest element

### 6. Review As Appendix

The task review UI should feel attached to the transcript, like margin notes gathered into one block.

- Keep it inline in the reading column.
- Use one restrained panel surface so it reads as reviewed output, not live transcript text.
- Keep `Tasks` as the only returned content because they are the actionable part.
- Let task type badges show `Feature`, `Bug fix`, or `Miscellaneous`.
- Keep one deliverable grouped into one task so the appendix reads like a clean work list instead of fragmented notes.
- Use source jumps and brief transcript highlighting to connect the appendix back to the transcript evidence.

## Current Design System Rules

### Layout Primitives

These are the main building blocks in the current shell design.

- `AppCanvas`
  A full-window black surface that holds everything.
- `TranscriptColumn`
  A centered reading column for live and saved transcript text.
- `SidebarHost`
  A left-side drawer for sessions and future navigation.
- `FloatingTransport`
  The one floating yellow record or stop button.
- `UtilityRail`
  The quiet bottom status and action strip.
- `TranscriptAppendix`
  The inline task-review panel that appears below the transcript when task compilation is active or finished.

### Typography

Use typography to create hierarchy before using color.

- The transcript body should use one clean primary text face.
- Utility text can use a monospaced face for a tool-like feel.
- Avoid many font families. One main family plus one utility family is enough.
- The transcript should feel dense and intentional, not roomy like a marketing page.

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

## Content Rules

- Keep labels short.
- Prefer sentence case over shouting in all caps unless a capture state really needs force.
- Keep pre-recording copy to one short sentence.
- Keep permission and error guidance visible, but do not let it turn the whole screen into a warning panel unless recording is blocked.

## Current Gaps Against The Planned Direction

- The yellow button still needs a final pass against the exact reference spacing and shade.
- Session labels are derived from transcript content, so empty or repetitive openings still need polish.
- The sidebar toggle and quiet rail still need a discoverability [how easy something is to notice] pass so first-time users do not miss them.
- The new review appendix needs one more polish pass on spacing and long-result density once real OpenAI-backed output lands.
- UI automation coverage for the new shell still needs stabilization on macOS.

## Design Change Rule

If a future change affects layout, hierarchy, visual tone, or major states, update this file, [`FRONTEND.md`](FRONTEND.md), and the matching `ExecPlan` in [`docs/exec-plans/`](exec-plans/) together.
