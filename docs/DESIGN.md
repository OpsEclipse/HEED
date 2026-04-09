# Design

## What This File Is

This is the design index. It says what the design is trying to do, where the design truth lives, and what is still unknown.

## Design Beliefs

- The product should feel fast and quiet.
- The transcript should be the main object on screen.
- Recording state should be obvious at a glance.
- Errors should be blunt and visible, not hidden in tiny status text.
- The planned visual direction is brutalist: sharp edges, strong contrast, monospace text, and no decorative softness.

## Current Design Sources Of Truth

- Product phases in the current repo planning notes
- Root UI in [`../heed/ContentView.swift`](../heed/ContentView.swift)
- This docs set

There is no Figma file, no checked-in mockup, and no shared design token [named design value like a color or spacing constant] system in the repo today.

## Verification Status

- Product intent: clear enough to document
- Visual system: not implemented
- Typography: unknown
- Color system: unknown
- Empty, loading, error, and permission-denied states: not implemented
- Sessions list and detail views: not implemented
- Export UI: not implemented

## Current UI Evidence

The only shipped UI is a placeholder `VStack` with an SF Symbol [Apple’s built-in icon system] and text. It does not yet express the product.

## Planned Design Areas

- First-run permission setup
- Recording screen with timer and status
- Live transcript feed with timestamps
- Speaker labeling for `Mic` and `System`
- Saved sessions list
- Session review screen
- Export actions
- Error and recovery states

## Unknowns That Need Decisions

- Whether the app stays windowed only or also gets a menu bar surface
- Whether the first screen is onboarding or the live transcript view
- How dense the transcript layout should be during long meetings
- Whether session review uses the same screen shell as live recording
- Whether the product keeps one visual mode or adds a second calmer mode later

## Design Change Rule

If a future change affects layout, hierarchy, visual tone, or major states, update this file and [`FRONTEND.md`](FRONTEND.md) together.
