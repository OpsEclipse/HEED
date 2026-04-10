# Minimalist UI Refresh

## Goal

Refresh Heed into a calmer transcript-first macOS window. The planned result is a sparse black canvas with a centered transcript column, a collapsible left sidebar, and one floating bottom-center record or stop button. The refresh should keep the current local transcription product intact while making the interface feel more focused and intentional.

## Scope

- Redesign the main window layout in [`heed/ContentView.swift`](../../../heed/ContentView.swift) and any new front-end views it needs.
- Replace the always-visible split layout with a transcript-first shell.
- Add a toggleable left sidebar for sessions.
- Move record or stop into a floating transport.
- Define the first shared design token system for spacing, color, type, and motion.
- Update the docs that describe front-end behavior and visual direction.

## Non-Goals

- Changing capture, transcription, storage, or export logic
- Adding new persistence formats
- Adding cloud features or network services
- Building a full settings screen
- Rebranding the product with a new logo or marketing site

## Implementation Slices

The work should be split into small front-end slices with clean ownership seams [clear boundaries between who owns what].

- Slice 1: tokens and shared styles
  Add the first design token layer for color, spacing, type, corner radius, and motion timing.
- Slice 2: shell layout
  Build the new workspace shell with the transcript canvas, sidebar host, and floating transport.
- Slice 3: transcript presentation
  Restyle transcript rows and empty states to fit the calmer reading-column layout.
- Slice 4: sidebar behavior
  Make the sessions list collapsible and visually lighter.
- Slice 5: tests and polish
  Update UI coverage and clean up edge cases around narrow widths and active recording states.

## Planned File Shape

These file names are directional. We can adjust them if implementation finds a better cut.

- `heed/ContentView.swift`
  Thin composition root for the app window.
- `heed/UI/HeedTheme.swift`
  Shared tokens and helper colors, spacing, and typography.
- `heed/UI/WorkspaceShell.swift`
  High-level layout and overlay behavior.
- `heed/UI/SessionSidebarView.swift`
  Sidebar content and collapse behavior.
- `heed/UI/TranscriptCanvasView.swift`
  Centered transcript column and empty states.
- `heed/UI/FloatingTransportView.swift`
  Floating record or stop button.

## Concrete Visual Targets

These values are the current implementation target unless the build proves one needs adjustment.

- Window canvas color: near-black in the `#050505` to `#090909` range
- Transcript column width: clamp between `620` and `760`
- Transcript top padding: `56`
- Transcript bottom padding: at least `96` so the floating button does not cover text
- Sidebar width: `256`
- Sidebar presentation: docked left column, hidden by default, that pushes transcript content when open
- Floating button position: bottom center by default, top right below `820` width
- Floating button size: about `132` to `156` wide and `44` high
- Floating button fill: yellow close to the attached `Create` reference
- Floating button corner radius: `0`

## Initial Token Direction

- `canvasPrimary`: near-black main background
- `canvasElevated`: slightly lifted near-black for overlays
- `textPrimary`: soft warm white
- `textSecondary`: muted gray for support copy
- `textMuted`: darker muted gray for hints
- `dividerSubtle`: white at low opacity
- `actionYellow`: bright yellow for the main button
- `warning`: muted amber
- `selection`: white at low opacity

## Risks

- The new minimal shell could hide important actions too well.
- The floating transport could block transcript reading or text selection.
- A collapsed sidebar could make saved sessions harder to discover.
- Removing utility copy could make permission and error states too subtle.
- A new token system could drift if we do not define where those values live and who owns them.

## Open Questions

- Which exact typeface pair should lead the system: system fonts only, or one custom app font plus a utility monospace face?
## Validation Steps

- Build the app with `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`.
- Run the unit tests with `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests`.
- Verify the app opens into a transcript-first canvas with the sidebar collapsed by default.
- Verify the sidebar can open and close without breaking transcript scroll or selection.
- Verify the floating transport stays visible and usable in idle, recording, stopping, and error states.
- Verify the empty transcript state shows only the one prompt sentence.
- Verify permission guidance and runtime errors remain obvious enough to recover from.
- Verify long transcript sessions still feel readable and do not clip behind the floating transport.

## Observable Acceptance Criteria

- The main window feels transcript-first instead of split-pane-first.
- The sessions list is available from a left sidebar that can be shown or hidden.
- The primary record or stop action lives in one floating yellow button instead of a heavy header bar.
- The refresh keeps the current local transcription behavior and session review flow intact.
- The docs and the shipped layout describe the same product truth.

## Progress

- 2026-04-09: Created this `ExecPlan` to capture the agreed minimalist UI direction before implementation starts.
- 2026-04-09: Updated [`docs/DESIGN.md`](../../DESIGN.md) and [`docs/FRONTEND.md`](../../FRONTEND.md) so the planned refresh is documented as planned, not shipped.
- 2026-04-09: Expanded the plan with implementation slices and a planned file shape so multiple agents can work against the same UI map.
- 2026-04-09: Split the implementation across sub-agents for theme plus floating transport, sidebar plus utility rail, and a local shell plus transcript canvas integration pass.
- 2026-04-09: Replaced the old split-view shell with a transcript-first `WorkspaceShell`, moved the main recording action into a floating transport, added a centered transcript canvas, and moved secondary actions into a bottom utility rail.
- 2026-04-09: Added new UI files under [`heed/UI/`](../../../heed/UI/) and a shared time-format helper under [`heed/Support/`](../../../heed/Support/).
- 2026-04-09: Simplified the sidebar and utility rail again so the drawer now shows title-only session rows and the bottom rail keeps only one `Copy as text` action.
- 2026-04-09: Restyled the sidebar again to match the later reference more closely, shifting from a softer sheet to a tighter tree-style column with compact rows and a selected-state accent bar.
- 2026-04-09: Kept that new sidebar layout, but moved its colors and type back onto the shared Heed theme so it still matches the rest of the app.
- 2026-04-09: Switched the sidebar from a floating overlay to a docked left column so opening it now shifts the transcript workspace instead of covering it.
- 2026-04-09: Removed the bottom utility rail from the current shell, stripped the main canvas down to transcript-only content plus one empty-state line, and restyled the floating control into a flat yellow button based on the attached `Create` reference.
- 2026-04-09: Verified `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build`.
- 2026-04-09: Verified `xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' test -only-testing:heedTests`.
- 2026-04-09: Updated the UI test for the new sidebar and floating transport identifiers, but the targeted macOS UI automation run still showed flaky behavior and needs one more stabilization pass.
- 2026-04-09: Re-ran the focused macOS UI test after the sidebar simplification. The code path reached launch, but the local run failed on Accessibility authorization instead of the old empty-state assertion.

## Surprises & Discoveries

- 2026-04-09: The repo has already moved beyond the old scaffold note in `AGENTS.md`. The app now has a real split-view transcript UI, so the refresh plan needs to describe a redesign of working code, not a first UI implementation.
- 2026-04-09: The current UI is visually consistent, but its strong header, footer, and boxed rows create more chrome than the new reference direction wants.
- 2026-04-09: A later layout correction replaced the overlay idea. The sidebar now needs to read like part of the app shell and take up real space when open.

## Decision Log

- 2026-04-09: Chose a transcript-first canvas as the new front-end north star so the product feels closer to a focused writing surface than an admin dashboard.
- 2026-04-09: Chose a collapsible left sidebar so session history stays available without permanently splitting the screen.
- 2026-04-09: Chose the sidebar as a docked column instead of an overlay so it feels like a real navigator and shifts the workspace when open.
- 2026-04-09: Chose to derive sidebar titles from the first non-empty transcript line until the product grows a real stored session title field.
- 2026-04-09: Chose to borrow the later sidebar reference's compact file-tree rhythm while still keeping the user's rule of title-only session content.
- 2026-04-09: Chose a flat yellow floating button as the default recording control because it matches the latest reference and keeps the action obvious without extra chrome.
- 2026-04-09: Chose a width-clamped centered transcript column instead of a full-width transcript list so long sessions read more like notes and less like a table.
- 2026-04-09: Chose to remove the utility rail entirely in the latest pass so the transcript and main button are the only bottom-level UI elements.
- 2026-04-09: Chose to split implementation into theme, shell, sidebar, and transcript slices so sub-agents can work in parallel without fighting over one large SwiftUI file.

## Outcomes & Retrospective

- 2026-04-09: The main shell overhaul is now implemented. The app window now matches the transcript-first direction in layout and control placement.
- 2026-04-09: Verification is mixed. The app builds and the unit suite passes, but the local macOS UI automation run is currently blocked by Accessibility authorization and still needs cleanup before this plan can be considered fully closed.
