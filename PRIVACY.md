# Privacy

macrecord is built to never send data anywhere.

- **No networking code.** `scripts/check-no-network.sh` runs in CI and fails the build if any networking API
  (URLSession, sockets, Network.framework, web views, update frameworks…) appears in `Sources/`.
- **No telemetry, analytics, crash reporting or auto-update.**
- **What is stored:** macros you record or write, as JSON files in
  `~/Library/Application Support/macrecord/Macros`, and your settings in macrecord's preferences.
  Nothing else is written.
- **What recordings contain:** whatever you did while recording — including anything you typed, such as passwords.
  macOS blocks keystroke capture while a password field has secure input enabled, and macrecord warns you,
  but treat macro files as sensitive before sharing them.
- **Permissions:** Accessibility (replay input), Input Monitoring (record input), and optionally Screen Recording
  (only to read single pixel colors for “wait for pixel” steps; no images are saved).
- **Scripts** run locally in JavaScriptCore with no network or file APIs exposed.

You can verify all of this: the source is small, and `grep -rE "URLSession|socket" Sources` returns nothing.
