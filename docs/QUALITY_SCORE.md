# Quality Score

## Snapshot

These scores reflect the repo as it exists after the 2026-04-09 review pass. They describe the current code, not the ideal product.

## By Area

- Product direction: `8/10`
  The product goal is clear and the active v1 plan is detailed.
- Documentation: `8/10`
  The docs now describe the shipped shell and pipeline more honestly, but they still need steady upkeep as reliability work lands.
- App shell: `8/10`
  The app now has a real recording workspace instead of the template shell.
- Frontend implementation: `7/10`
  The main transcript flow, session list, and copy flow exist, but polish, richer recovery copy, and the decision about visible file export are still open.
- Audio capture: `6/10`
  Microphone and system-audio capture both exist, but device-change and long-run behavior still need more real-world checks.
- Transcription: `7/10`
  Local Whisper transcription works through a bundled helper, but first-chunk latency and long-run stability still need more measurement.
- Persistence and export: `8/10`
  JSON autosave, recovery, clipboard copy, and text or Markdown export code are all implemented, even though the refreshed shell only surfaces copy right now.
- Test coverage: `5/10`
  There is real unit and UI coverage now, but capture-heavy paths still rely mostly on manual checks.
- Release readiness: `5/10`
  The v1 path is real, but reliability work is still the main blocker.

## By Layer

- UI layer: `7/10`
  The main workflow is present and readable.
- Domain layer: `7/10`
  Shared session, segment, source, and state models are in place.
- Service layer: `6/10`
  Capture, transcription, permission, and storage services exist, but interruption handling and hardware variance still need more trust work.
- Platform layer: `6/10`
  Project settings, privacy strings, sandboxing, helper bundling, and exports are wired, but the build-time model download is not fully hardened yet.

## Highest-Leverage Gaps

- Add more manual smoke coverage for permission resets, device changes, and live meeting apps.
- Measure first-chunk and steady-state latency on supported Apple Silicon hardware.
- Harden the build-time model download with explicit checksum verification in code.
- Add more failure-path coverage around interrupted system-audio capture.
- Decide whether `.txt` and `.md` export should return to the refreshed shell or stay controller-only.

## Re-Scoring Rule

Update this file whenever a major layer ships or a meaningful reliability risk drops.
