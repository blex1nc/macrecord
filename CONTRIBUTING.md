# Contributing

Thanks for helping make macrecord better!

## Layout

| Target | Role |
|---|---|
| `MacroCore` | Data model, versioned JSON format, sanitizer, editing (pure, Swift 6 mode) |
| `CSupport` | C helpers: atomics, Mach real-time thread policy, precise waits |
| `Capture` | Passive `CGEventTap` recorder, input watcher |
| `Playback` | Real-time player, autoclicker, event factory, pixel sampler |
| `Scripting` | JavaScriptCore runner |
| `Hotkeys` | Carbon global shortcuts |
| `Permissions` | TCC checks |
| `MacrecordApp` | SwiftUI app |
| `Bench` | `macrecord-bench` CLI: timing benchmark, headless record/play |

Engine targets use Swift 5 language mode because they run on event-tap / real-time threads with C callbacks.

## Rules

1. **Never add networking code.** CI enforces it (`scripts/check-no-network.sh`).
2. Keep the hot paths lean: the tap callback only copies a struct into a pre-reserved buffer, and the player
   builds all CGEvents before playback starts. No logging or blocking calls on these threads.
3. Tests must not post real input. Use `MacroPlayer.configuration.dryRun`, `ScriptRunner.post` or inspect
   events from `EventFactory`.
4. Run `swift test` and `./scripts/check-no-network.sh` before opening a PR.
5. New user-facing strings need an entry in `App/Resources/tr.lproj/Localizable.strings`.

## Stable signing for development

macOS binds Accessibility/Input Monitoring grants to the code signature's designated requirement. For plain ad-hoc
signatures that is the cdhash, which changes on every build. `build-app.sh` therefore signs local ad-hoc builds with
an identifier-based requirement, so grants survive rebuilds (releases built with `RELEASE=1` keep the strict cdhash).
If a grant was made for an older build, the switch in System Settings looks on but doesn't apply: run the
`tccutil reset` commands below and grant again. Alternatively, create a local self-signed identity:

1. Keychain Access → Certificate Assistant → Create a Certificate…
2. Name `macrecord dev`, Identity Type *Self Signed Root*, Certificate Type *Code Signing*.
3. Build with `SIGN_IDENTITY="macrecord dev" ./scripts/build-app.sh`.

To reset permissions: `tccutil reset Accessibility io.github.blex1nc.macrecord`
(and `ListenEvent`, `ScreenCapture`).

## Testing the UI with throwaway data

```sh
open -g dist/macrecord.app --args -macrecordDataDir /tmp/macrecord-test -AppleLanguages '(tr)'
```
