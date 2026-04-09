# Quality Score

## Snapshot

These scores reflect the repo as it exists today, not the planned product.

## By Area

- Product direction: `8/10`
  The product goal and build phases are clear.
- Documentation: `8/10`
  The repo now has a connected doc set, but it will need upkeep as code lands.
- App shell: `3/10`
  The app launches, but it is still the template shell.
- Frontend implementation: `1/10`
  There is no transcript UI, onboarding, or session history yet.
- Audio capture: `0/10`
  No microphone or system-audio code exists.
- Transcription: `0/10`
  No Whisper integration exists.
- Persistence and export: `0/10`
  No session model or storage path exists.
- Test coverage: `1/10`
  Test targets exist, but only template tests are present.
- Release readiness: `1/10`
  Required permissions, entitlements, and failure handling are not implemented.

## By Layer

- UI layer: `1/10`
  Placeholder only.
- Domain layer: `0/10`
  No shared session, transcript, or recording model exists.
- Service layer: `0/10`
  No capture, mixing, transcription, or storage services exist.
- Platform layer: `2/10`
  The Xcode target exists and sandboxing is on, but the permission-heavy app setup is incomplete.

## Why These Scores Matter

The repo is strong on intent and weak on execution. That is normal for day-one code, but it means most future mistakes will come from structure choices made before the first feature works.

## Highest-Leverage Gaps

- Build the permission and capture skeleton first. That turns the project into the real product space.
- Split app code into modules early so audio, UI, and persistence do not collapse into one view file.
- Decide how sessions are saved before transcription output starts to pile up.
- Add one small end-to-end test path once recording exists.
- Lower the deployment target if macOS 13 support is still a real goal.

## Re-Scoring Rule

Update this file whenever a major layer ships or when a risk drops in a measurable way.
