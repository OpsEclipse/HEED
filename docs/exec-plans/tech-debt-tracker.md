# Tech Debt Tracker

- `Platform target`
  The project deploys to macOS `26.2`, but the product phases mention broader support. Decide the real floor and align the Xcode target.

- `Privacy setup`
  The repo uses generated Info.plist values, but the required microphone and screen-capture strings are not in place yet.

- `Entitlements`
  The planned capture product needs explicit permission-related setup, but no checked-in entitlements file exists yet.

- `Module boundaries`
  The app still has one placeholder view. Create clear ownership seams before real feature code piles into `ContentView`.

- `Session format`
  The repo has no decision yet on SwiftData vs JSON for saved transcripts.

- `Tests`
  Unit and UI test targets are still template stubs. Add one meaningful path as soon as recording exists.
