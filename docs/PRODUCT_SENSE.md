# Product Sense

## Product Purpose

Heed is for people who need a meeting transcript without sending the whole meeting to a remote service by default. The product promise is simple: start recording, see text appear quickly, and keep a usable session record after the call ends.

## User Jobs

- Capture both sides of a call in one transcript
- Read the conversation live while it is happening
- Recover what was said after the meeting ends
- Export notes without re-listening to the meeting
- Trust that the app is not silently dropping important moments

## Value Promises

- Local-first transcription
- Fast time to first text
- Clear recording state
- Durable session history
- Simple export

## Main Product Risks

- Permissions are confusing on macOS, so first-run setup can fail before value appears.
- System audio capture may behave differently across apps and audio devices.
- Transcript delay can make the app feel broken even when it is technically working.
- “Mic” vs “System” labeling is only rough speaker attribution [a guess about who said what], not true diarization [speaker separation].
- Saved transcripts may contain sensitive meeting content, so trust can be lost fast.

## Product Heuristics

Use these heuristics [simple decision rules] when tradeoffs appear.

- Prefer trust over cleverness.
  If a behavior might confuse users about what is being recorded, make it explicit.
- Prefer visible state over hidden automation.
  Recording, processing, and failure should all be obvious.
- Prefer local work over network dependence.
  The core transcript path should still function without a server.
- Prefer recovery over perfect elegance.
  Autosave and restart safety matter more than a fancy first version.
- Prefer a blunt, readable UI over decorative chrome [visual decoration around content].
  The transcript is the product.

## What Counts As Success

- A user can finish a meeting and keep a readable transcript.
- The app makes setup problems easy to diagnose.
- The live view feels fast enough to trust during a real call.
- Exported text is clean enough to use in notes or follow-up.

## Current Product Maturity

The product idea is clear, but the implementation is still near zero. The docs should therefore guide decisions, not pretend the experience already exists.
