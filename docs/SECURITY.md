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

## OpenAI Task Analysis And Prep

- Risk:
  Finished transcript text can leave the machine when the user runs AI task actions.
- Current posture:
  The app makes outbound OpenAI calls only after explicit user actions such as `Compile tasks`, `Prepare context`, or a follow-up message inside the prep chat. The prep workspace uses GPT-5.4 and streams replies [delivers the reply in small pieces over one network response].
- Guardrail:
  Keep every transcript upload user-triggered, keep the network boundary obvious in the UI, and never send raw audio.

## Task-Prep Transcript Tool

- Risk:
  A tool could expose more meeting text than the current task needs.
- Current posture:
  The prep service exposes a read-only `get_meeting_transcript` tool. It formats transcript lines only from the selected session when the model asks for more detail.
- Guardrail:
  Keep the tool scoped to the selected session and do not let it browse saved sessions globally.

## Spawn Approval Gate

- Risk:
  An automated handoff could start follow-on work the user did not approve.
- Current posture:
  The task-prep prompt tells the model to use `spawn_agent` only after clear approval, and app code separately blocks the request until the user clicks `Approve spawn`.
- Guardrail:
  Keep both checks. Prompt rules alone are not a strong enough control.

## No Prep Persistence

- Risk:
  Saving prep chat or the right-side brief would leave extra sensitive context on disk.
- Current posture:
  Prep chat messages and prep briefs stay in memory only. Closing the workspace, switching sessions, or starting prep for a different task clears them.
- Guardrail:
  Do not add prep persistence without a new plan, updated docs, and a clear migration [how old saved data becomes new saved data] story.

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
- The app has a network client for explicit OpenAI task-analysis and task-prep calls.
- Transcript storage lives under Application Support.
- Prep chat history and prep briefs are not written to Application Support.
- The Whisper model download URL is `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin`.
- The current docs record the downloaded model checksum as `a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002`, but the build step does not enforce that checksum yet.

## Main Risks Right Now

- Screen recording is still a broad permission and needs careful user explanation.
- Export can move sensitive text outside the app sandbox.
- The OpenAI task path sends transcript text over the network, so the user-triggered boundary must stay clear.
- The transcript tool must stay scoped to the selected session and must not expand into global transcript search without a fresh security review.
- API key handling depends on Keychain staying the only secret store.
- The build-time model download should still add explicit checksum verification in code, not docs alone.

## Security Posture Summary

The repo now has the main product-specific controls in place for the shipped task-prep workspace. The biggest remaining issues are hardening the build-time model download path, keeping the OpenAI boundary explicit and user-controlled, and preserving the approval gate if a future real spawn handoff is added.

## Rules For Future Work

- Follow least privilege [the smallest access level needed] when adding entitlements.
- Keep transcription local unless a user-visible feature explicitly requires network use.
- Do not add silent background uploads of audio or transcript content.
- Document every new permission, saved-data path, export path, and task-prep tool in this file.
- Treat API keys as secrets and keep them in Keychain or an equally strong system store.
- If the app ever turns the current ready-to-spawn state into a real external handoff, keep the explicit approval gate in app code and not only in the model prompt.
