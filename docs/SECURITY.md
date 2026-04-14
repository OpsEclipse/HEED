# Security

## Main Security Surfaces

## Microphone Access

- Risk:
  The app can capture sensitive speech.
- Current posture:
  The app requests microphone access only when the user clicks `Record`, and the recording state stays visible through the floating transport and bottom utility rail.
- Guardrail:
  Ask only when the user is about to record, and make recording state obvious.

## Screen And System-Audio Capture

- Risk:
  Screen-capture permission can grant access broader than users expect.
- Current posture:
  `ScreenCaptureKit` capture is implemented. The app keeps the first-run state neutral until the user clicks `Record`. If screen recording stays unavailable, the controller tracks a blocked message, but the current shell mostly exposes that state through status text instead of a richer recovery panel.
- Guardrail:
  Explain clearly why the app needs this permission and never imply it captures less than it really does.

## Saved Transcripts

- Risk:
  Transcript files may contain confidential business or personal data.
- Current posture:
  Sessions are saved locally as JSON in `~/Library/Application Support/Heed/Sessions/<session-id>/session.json`.
- Guardrail:
  Keep storage local by default and make file locations easy to inspect.

## Export

- Risk:
  Copy or file export can move sensitive text into less trusted places.
- Current posture:
  Clipboard copy is surfaced in the current shell. `.txt` and `.md` file export paths still exist in controller code, but they are not currently exposed in the refreshed UI.
- Guardrail:
  Make export a clear user action, not an automatic side effect.

## OpenAI Task Calls

- Risk:
  Finished transcript text can leave the machine when the user runs task actions.
- Current posture:
  The app now makes outbound OpenAI calls only after the user clicks `Compile tasks` or `Prepare context`. The API key is entered through the UI and stored in Keychain, not in saved session JSON.
- Guardrail:
  Keep every transcript upload user-triggered, keep task context temporary by default, and never send audio.

## API Key Storage

- Risk:
  A leaked API key can expose billing and data access.
- Current posture:
  The app stores the OpenAI API key in Keychain and exposes a plain-text `Set API key` action in the utility rail that opens a dedicated settings sheet.
- Guardrail:
  Keep secrets out of source control, out of session files, and out of debug UI.

## Model Files

- Risk:
  A downloaded model adds supply-chain [risk introduced by third-party code or files] and integrity [trust that the file is authentic and unchanged] concerns.
- Current posture:
  The app bundles `ggml-base.en.bin` by downloading it at build time from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin`.
- Guardrail:
  Record source, checksum [a file fingerprint used to detect tampering], and update behavior in docs and code.

## Current Baseline

Real security-relevant facts from the project today:

- App Sandbox is enabled.
- Hardened Runtime is enabled.
- Generated Info.plist is enabled.
- Privacy usage strings for microphone, screen capture, and system audio are present in build settings.
- The checked-in entitlements file enables App Sandbox, microphone input, and outbound network access. Screen recording uses the macOS privacy prompt flow here, not a separate checked-in entitlement.
- The app now has a network client for explicit OpenAI task calls.
- Transcript storage lives under Application Support.
- The Whisper model download URL is `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin`.
- The current docs record the downloaded model checksum as `a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002`, but the build step does not enforce that checksum yet.

## Main Risks Right Now

- Screen recording is still a broad permission and needs careful user explanation.
- Export can move sensitive text outside the app sandbox.
- The new OpenAI path sends transcript text over the network, so the user-triggered boundary must stay clear.
- API key handling now depends on Keychain staying the only secret store.
- The build-time model download should still add explicit checksum verification in code, not docs alone.

## Security Posture Summary

The repo now has the core product-specific controls in place. The biggest remaining issues are hardening the build-time model download path, keeping the new OpenAI boundary explicit and user-controlled, and expanding real-world permission recovery checks.

## Rules For Future Work

- Follow least privilege [the smallest access level needed] when adding entitlements.
- Keep transcription local unless a user-visible feature explicitly requires network use.
- Do not add silent background uploads of audio or transcript content.
- Document every new permission, saved-data path, and export path in this file.
- Treat API keys as secrets and keep them in Keychain or an equally strong system store.
