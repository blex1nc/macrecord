# macrecord for Windows — autoclicker (plan)

Durum: plan (2026-11-21). Kapsam kararı: **yalnızca autoclicker** (makro kaydet/oynat yok). Kullanıcı: Windows'ta bir
arkadaş, hedef oyun Roblox. Mac sürümünün davranışını taklit eder; kod paylaşılmaz (Swift ↔ C#), yapılandırma alanları
aynı adlarla tutulur.

## Teknoloji

- **C# / .NET 8, WinForms** (WPF'ten küçük ve basit; tek pencere + sistem tepsisi yeter).
- Yayın: `dotnet publish -r win-x64 --self-contained -p:PublishSingleFile=true` → tek `macrecord-windows-x64.exe`
  (arkadaşın .NET kurmasına gerek yok).
- Bu Mac'te .NET yok: derleme ve birim testleri **GitHub Actions `windows-latest`** üzerinde doğrulanır; gerçek tıklama
  testi arkadaş tarafından elle yapılır (bkz. Doğrulama).

## Klasör yapısı

```
windows/
  Macrecord.Windows.sln
  src/Macrecord.Core/        net8.0          — AutoClickConfig, zamanlama hesapları, sürüm karşılaştırma (saf, test edilebilir)
  src/Macrecord.Windows/     net8.0-windows  — WinForms UI, SendInput tıklayıcı, düşük seviye hook'lar, güncelleme kontrolü
  tests/Macrecord.Core.Tests/ xUnit
```

## Bileşenler

1. **AutoClickConfig (Core)** — Mac ile aynı alanlar: `clicksPerSecond` (0.1–2000, aralık hesabı aynı), `button`
   (left/right/middle), `clickType` (single/double), `target` (cursor / fixed / points), `timingJitter` (0–0.9),
   `positionJitter`, `holdDurationMs` (aralığın yarısıyla sınırlı), `limit` (none/clicks/seconds), `mode` (toggle/hold).
   Mac'teki `jitteredIntervalNs` / `effectiveHoldNs` mantığı birebir taşınır ve aynı testlerle doğrulanır.
2. **Clicker (Windows)** — ayrı thread, `ThreadPriority.Highest`.
   - Zamanlama: `Stopwatch` tabanlı **mutlak hedef zamanlar** (sapma birikmez), `CreateWaitableTimerExW` +
     `CREATE_WAITABLE_TIMER_HIGH_RESOLUTION` ile uyku, son ~0.5 ms spin. 50 ms'den fazla geride kalınırsa
     yeniden senkron (Mac ile aynı kural; patlama yok).
   - Tıklama: `SendInput` + `MOUSEINPUT` (`LEFTDOWN/UP`, `RIGHTDOWN/UP`, `MIDDLEDOWN/UP`). İmleç hedefinde **MOVE bayrağı
     yok** → imleç oynatılmaz (Mac'teki imleç zorlama sorunu yaşanmaz). Sabit nokta/nokta listesi:
     `MOVE | ABSOLUTE | VIRTUALDESK`, 0–65535 normalizasyonu.
   - `dwExtraInfo` = sabit macrecord etiketi → kendi hook'larımız kendi tıklarımızı tanır.
3. **Tetikleyiciler**
   - Fare: `WH_MOUSE_LL` hook (XButton1/XButton2/orta). Tetikleyici basma/bırakma **tüketilir** (1 döner); `LLMHF_INJECTED`
     veya bizim `dwExtraInfo` olan olaylar yok sayılır. Hareket olaylarına dokunulmaz.
   - Klavye: aç/kapa için `RegisterHotKey`; basılı tut modu için bırakma olayı gerektiğinden `WH_KEYBOARD_LL`.
   - Hook'lar kendi mesaj döngüsü olan ayrı thread'de; geri çağrılar mikrosaniyeler içinde döner (iş kuyruğa atılır).
     **Ders (Mac/Supercharge):** yavaş hook tüm girdi akışını bekletir; Windows ayrıca `LowLevelHooksTimeout` aşılınca
     hook'u sessizce kaldırır.
4. **Ayarlar** — `%APPDATA%\macrecord\settings.json` (System.Text.Json). Eski dosyalar eksik alanlarla da okunur.
5. **UI** — Mac'teki Autoclicker ekranının karşılığı: CPS, buton, tür, konum, jitter, basılı tutma, limit, mod, tetikleyici
   atama alanları, Başlat/Durdur, canlı tık sayacı; sistem tepsisi simgesi. TR/EN (resx).
6. **Güncelleme kontrolü** (kullanıcı kararı: uygulama içi, kapatılabilir)
   - Açılışta ve 24 saatte bir `GET https://api.github.com/repos/blex1nc/macrecord/releases/latest`; `tag_name`
     (`vX.Y.Z`) mevcut sürümle karşılaştırılır (Core'da test edilen SemVer karşılaştırma).
   - Yeni sürümde bildirim → "Güncelle": `macrecord-windows-x64.exe` asset'i indirilir, çalışan exe `*.old` olarak
     yeniden adlandırılır (Windows buna izin verir), yenisi yerine yazılır, uygulama yeniden başlatılır; sonraki açılışta
     `*.old` silinir. Ayarlarda "Güncellemeleri denetle" kapatılabilir.
   - Uygulamanın **tek** ağ erişimi budur; `PRIVACY.md` buna göre güncellenir, Windows için ayrı bir kontrol betiği
     yalnızca bu iki host'a izin verir.

## CI / Release

- `ci.yml`: yeni `windows` job (`windows-latest`): `dotnet build` + `dotnet test`.
- `release.yml`: `v*` etiketinde Windows job'u `dotnet publish` yapar ve `macrecord-windows-x64.exe`'yi aynı GitHub
  Release'e yükler (Mac zip/dmg'nin yanına).
- İmzasız exe → SmartScreen uyarısı: README'ye "Ek bilgi → Yine de çalıştır" notu.
- Not: Roblox yönetici olarak çalışmıyorsa sorun yok; yükseltilmiş (admin) bir pencereye UIPI nedeniyle tık gönderilemez.

## Fazlar (her biri kendi başına çalışır biter)

| Faz | İçerik | Doğrulama |
|---|---|---|
| W1 | `windows/` iskeleti, Core + AutoClickConfig + testler, CI windows job | CI yeşil |
| W2 | Clicker motoru (SendInput, zamanlama) + basit UI, Başlat/Durdur | CI derler; arkadaş elle dener |
| W3 | Fare/klavye tetikleyicileri (hook'lar), basılı tut/aç-kapa | Arkadaş: yan tuşla Roblox'ta |
| W4 | Ayarların kalıcılığı, tepsi simgesi, TR/EN | Elle |
| W5 | Güncelleme kontrolü + release workflow'u + README/PRIVACY | `v0.1.0` etiketiyle yayın, arkadaş indirir |

## Doğrulama (arkadaş için kontrol listesi)

1. Exe açılıyor (SmartScreen notu ile).
2. 20 CPS, sol tık, imleç hedefi: Roblox'ta tıklar sayılıyor.
3. Yan tuşla basılı tut modu: bırakınca anında duruyor; bu sırada kamera akıcı.
4. Yan tuşun "geri" işlevi tarayıcıda tetiklenmiyor (tüketiliyor).
5. Uygulamayı kapatınca tıklama duruyor.
6. Yeni sürüm yayınlanınca uygulama bildiriyor ve güncelliyor.
