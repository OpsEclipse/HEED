# Tech Debt Tracker

- `Model download hardening`
  The build step downloads `ggml-base.en.bin`, but it still does not verify the checksum in code before bundling it.

- `Real-world capture validation`
  The v1 path is wired, but device changes, interruption handling, and long meetings still need deeper manual validation on real hardware.

- `Permission recovery UX`
  The app now keeps first-run screen-capture guidance honest, but the recovery flow still relies on plain inline text instead of a richer guided walkthrough.

- `Export feedback`
  Clipboard copy works, but the UI still does not show a clear success state, and the refreshed shell does not surface file export yet even though the export code still exists.

- `Long-run observability`
  The app has very light logging today. Capture, chunking, and autosave would be easier to trust with structured logs [consistent machine-readable logs].
