# macrecord

**Fast, private, open-source mouse & keyboard macro recorder and autoclicker for macOS.**
Everything runs on your Mac. There is no networking code at all — CI fails the build if any appears.

*[Türkçe açıklama aşağıda](#türkçe)*

## Features

- **Record & replay** mouse moves, clicks, drags, scrolls and keystrokes with microsecond-precise timing
  (real-time thread, absolute scheduling — no drift over long macros). See [benchmarks](docs/BENCHMARKS.md).
- **Zero-lag recording:** passive event tap, nothing in the system input path waits on macrecord.
- **Autoclicker:** up to 2000 CPS, left/right/middle/back/forward, single/double, cursor / fixed point / point sequence,
  timing & position randomness, hold duration, click or time limits, toggle or hold-to-click shortcut.
- **Editor:** edit delays, delete/insert steps, simplify mouse paths (Ramer–Douglas–Peucker), remove moves, undo.
- **Conditions:** wait for a pixel color (ScreenCaptureKit, local), bring an app to the front.
- **Scripting:** JavaScript macros (JavaScriptCore) with loops, variables, `click`, `key`, `type`, `pixel`, `play(...)`.
- **Global shortcuts** for record / play / stop / autoclicker and per-macro shortcuts.
- **Safety:** stops when you physically move the mouse or press a key (optional), releases held keys/buttons on stop,
  emergency stop shortcut (default ⌘⎋).
- Loops (∞), speed 0.1×–10×, pause between loops, relative mouse mode for games.
- English & Turkish UI. Plain, versioned JSON macro files you can share.

## Install

Requires macOS 14 Sonoma or later (Apple silicon & Intel).

**Homebrew**

```sh
brew install --cask blex1nc/macrecord/macrecord
```

**Manual:** download `macrecord.dmg` from [Releases](https://github.com/blex1nc/macrecord/releases), open it and drag macrecord to
`/Applications`.

macrecord is not notarized (no paid Apple Developer account), so on first launch macOS blocks it. Either:
- System Settings → Privacy & Security → scroll down → **Open Anyway**, or
- `xattr -dr com.apple.quarantine /Applications/macrecord.app`

Then grant **Accessibility** (to replay) and **Input Monitoring** (to record) when asked.
**Screen Recording** is only needed for “wait for pixel color”.

## Default shortcuts

| Action | Shortcut |
|---|---|
| Start / stop recording | ⌥⌘R |
| Play selected macro (again to stop) | ⌥⌘P |
| Stop everything | ⌘⎋ |
| Autoclicker | ⌥⌘A |

All are configurable in Settings.

## Scripting

```js
// Click a sequence of points until a pixel turns green, then type.
while (running() && !waitForPixel(100, 200, 0x00FF00, 12, 50)) {
  click(400, 300)
  sleep(250)
}
key('a', 'cmd')
type('hello')
play('Recording 1')
```

API: `move click mouseDown mouseUp scroll key keyDown keyUp type sleep cursor pixel waitForPixel activate play log running`.

## Build from source

```sh
swift test                      # unit tests
./scripts/build-app.sh          # → dist/macrecord.app (universal)
swift run -c release macrecord-bench jitter   # timing benchmark (dry run: touches no real input)
```

macOS ties permissions to the code signature, so ad-hoc builds lose them on every rebuild.
See [CONTRIBUTING.md](CONTRIBUTING.md) for a stable local signing identity.

## Privacy

See [PRIVACY.md](PRIVACY.md). Short version: nothing ever leaves your Mac.

## Responsible use

Automating input in online games or services may violate their terms. You are responsible for how you use macrecord.

## License

[MIT](LICENSE)

---

## Türkçe

**macOS için hızlı, gizli ve açık kaynak fare/klavye makro kaydedici ve autoclicker.**
Her şey senin Mac'inde çalışır, hiçbir veri dışarı gönderilmez. Kodda ağ kodu yoktur; eklenirse CI derlemeyi durdurur.

- Fare ve klavye kaydı ve tekrar oynatma, mikrosaniye hassasiyetinde ([ölçümler](docs/BENCHMARKS.md))
- Autoclicker: saniyede 2000 tıklamaya kadar, rastgele zamanlama ve konum, sınırlar, basılı tutma modu
- Düzenleyici, piksel rengi bekleme, JavaScript betikleri, makro başına kısayol
- Fareyi oynattığında veya bir tuşa bastığında oynatma otomatik durur

**Kurulum:** `brew install --cask blex1nc/macrecord/macrecord` veya Releases'tan zip'i indir.
İlk açılışta: Sistem Ayarları → Gizlilik ve Güvenlik → **Yine de Aç**. Sonra Erişilebilirlik ve Girdi İzleme izinlerini ver.
