# Security

## Main Security Surfaces

## Microphone Access

- Risk:
  The app can capture sensitive speech.
- Current posture:
  The app requests microphone access only when the user clicks `Record`, and the recording state is visible in the header.
- Guardrail:
  Ask only when the user is about to record, and make recording state obvious.

## Screen And System-Audio Capture

- Risk:
  Screen-capture permission can grant access broader than users expect.
- Current posture:
  `ScreenCaptureKit` capture is implemented, and the app explains the need for screen and system-audio capture before recording.
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
  Export exists as clear user actions: clipboard copy, `.txt`, and `.md`.
- Guardrail:
  Make export a clear user action, not an automatic side effect.

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
- No network client is present in app code today.
- Transcript storage lives under Application Support.
- The Whisper model download URL is `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin`.
- The current downloaded model checksum is `a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002`.

## Main Risks Right Now

- Screen recording is still a broad permission and needs careful user explanation.
- Export can move sensitive text outside the app sandbox.
- The build-time model download should eventually add explicit checksum verification in code, not docs alone.

## Security Posture Summary

The repo now has the core product-specific controls in place. The biggest remaining issue is hardening the build-time model download path and expanding real-world permission recovery checks.

## Rules For Future Work

- Follow least privilege [the smallest access level needed] when adding entitlements.
- Keep transcription local unless a user-visible feature explicitly requires network use.
- Do not add silent background uploads of audio or transcript content.
- Document every new permission, saved-data path, and export path in this file.
