# macrecord — Proje Planı

> macOS için açık kaynak, tamamen yerel çalışan, gecikmesiz mouse/klavye makro kaydedici ve autoclicker.
> Bu belge projenin yaşayan planıdır; her faz bitince güncellenir.

## 1. Hedefler

| Hedef | Ölçüt |
|---|---|
| Sıfıra yakın gecikme | Oynatmada planlanan vs gerçekleşen zaman sapması (jitter) p99 < 1 ms, ortalama < 100 µs |
| Kasma yok | Kayıt sırasında sistem girdisine ek gecikme yok (pasif tap), CPU boşta ~%0 |
| Gizlilik | Sıfır ağ kodu, telemetri yok, otomatik güncelleme yok (varsayılan) |
| Açık kaynak | GitHub, CI, katkı rehberi, ölçülebilir benchmark sonuçları README'de |

## 2. Teknoloji Kararları

- **Dil/UI:** Swift + SwiftUI (menü çubuğu `MenuBarExtra` + ana pencere), gerektiğinde AppKit.
- **Kayıt:** `CGEventTap`, **`.listenOnly`** modunda (aktif tap tüm sistem girdisini yavaşlatır ve zaman aşımında kapatılır).
  - Kendi `CFRunLoop`'u olan ayrı thread.
  - `kCGEventTapDisabledByTimeout` / `ByUserInput` gelirse tap yeniden etkinleştirilir.
  - Callback içinde **sıfır allocation**: önceden ayrılmış ring buffer, zaman damgası `CGEvent.timestamp` (mach ns). Diske yazma ayrı thread'de.
  - Klavye: karakter değil **keycode + modifier flags** kaydedilir (klavye düzeninden bağımsız).
  - Mouse: mutlak konum **ve** göreli delta (`kCGMouseEventDeltaX/Y`, oyunlar için), çoklu monitör + Retina koordinatları.
  - Durdurma kısayolunun kendi tuş vuruşları kayda girmez.
- **Oynatma:**
  - Real-time thread (`THREAD_TIME_CONSTRAINT_POLICY`), `mach_wait_until` + son birkaç on µs için kısa spin.
  - Olaylar `.cghidEventTap` seviyesinde post edilir (bazı oyunlar session seviyesini yok sayar).
  - `CGEventSource.localEventsSuppressionInterval = 0` (yoksa kullanıcının kendi girdisi her post sonrası bastırılır → "kasma" hissi).
  - Post edilen olaylar `eventSourceUserData` ile etiketlenir; kaydedici/kısayol tap'i kendi çıktısını yok sayar.
- **İzinler (TCC):** Erişilebilirlik (post + tap) ve Girdi İzleme (`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`). Kullanıcı Sistem Ayarları'ndan elle onaylar; uygulama içinde rehberli onboarding ekranı olur.
  - TCC izni kod imzasına bağlıdır → geliştirmede **sabit bir imza kimliği** kullanılmalı, yoksa her derlemede izin kaybolur. Sıfırlama: `tccutil reset Accessibility <bundle-id>`.
- **Swift 6 eşzamanlılık:** `MacroCore` ve testler Swift 6 modunda; motor modülleri (C callback, real-time thread) ve uygulama hedefi pratiklik için **Swift 5 dil modunda**.
- **Minimum macOS:** 14 Sonoma (Observation, modern SwiftUI).
- **Dağıtım:** App Sandbox içinde olay post etmek imkânsız → **Mac App Store yok**. GitHub Releases + Homebrew cask.

## 3. Mimari

Xcode projesi yerine tek bir SwiftPM paketi + `scripts/build-app.sh` (.app paketleme, imzalama) kullanıldı:
CLI'dan ve CI'dan tamamen derlenebilir.

```
macrecord/
├── Package.swift
├── Sources/
│   ├── MacroCore      Veri modeli, sürümlü JSON, sanitizer, düzenleme (saf)
│   ├── CSupport       C: atomikler, Mach real-time politika, hassas bekleme
│   ├── Capture        Pasif CGEventTap kaydedici, InputWatcher
│   ├── Playback       Real-time oynatıcı, autoclicker, EventFactory, piksel örnekleyici
│   ├── Scripting      JavaScriptCore betik motoru
│   ├── Hotkeys        Carbon global kısayollar
│   ├── Permissions    TCC kontrolleri
│   ├── MacrecordApp   SwiftUI uygulaması (menü çubuğu + pencere + ayarlar)
│   └── Bench          macrecord-bench CLI (jitter, record, play)
├── Tests/             MacroCore, Playback, Scripting testleri (gerçek girdi göndermez)
├── App/               Info.plist, en/tr Localizable.strings
├── Casks/             Homebrew cask (kişisel tap için)
├── scripts/           build-app.sh, check-no-network.sh
└── .github/workflows/ ci.yml, release.yml
```

**Makro dosya formatı:** Sürümlü JSON (`schemaVersion`), insan tarafından okunabilir. Olay türleri: `mouseMove`, `mouseDown/Up` (buton), `scroll`, `keyDown/Up` (keycode, flags), `delay`. Zaman: önceki olaya göre ns. İleride büyük kayıtlar için ikili format eklenebilir.

## 4. Gizlilik ve Güvenlik

- Kodda hiçbir ağ API'si yok; CI'da `URLSession`, `Network`, `NSURLConnection`, `CFSocket` vb. için grep kontrolü — bulunursa build kırılır.
- `PRIVACY.md`: ne kaydedilir, nerede saklanır (`~/Library/Application Support/macrecord`), hiçbir şey gönderilmez.
- Kayıtlar şifre içerebilir: `IsSecureEventInputEnabled` algılanırsa kullanıcı uyarılır; ileride isteğe bağlı disk üstü şifreleme (Keychain anahtarı).
- Sparkle gibi otomatik güncelleme **varsayılan olarak yok**; eklenirse açıkça opt-in olur.

## 5. Fazlar

Her faz kendi başına çalışır durumda biter. Faz 1 bir **git / gitme kapısıdır**.

### Faz 0 — Altyapı
- README, LICENSE, PRIVACY.md, CONTRIBUTING.md, .gitignore
- Xcode projesi + yerel SwiftPM paketi iskeleti
- GitHub Actions: build + test + ağ kodu kontrolü
- Geliştirme imzalama rehberi (TCC için)

### Faz 1 — Motor prototipi + benchmark (kapı)
- İzin kontrolü, pasif tap ile kayıt, real-time oynatma (headless/CLI)
- **Jitter benchmark:** oynatmanın post ettiği olayları ikinci bir tap ile yakala, planlanan vs gerçek zamanı karşılaştır; p50/p99/max raporla
- `localEventsSuppressionInterval` ve `userData` filtrelemesinin doğrulanması
- Sürümlü makro şeması v1
- ✅ Kriter: p99 < 1 ms. Sağlanmazsa UI'ya geçilmez.

### Faz 2 — MVP uygulama
- Menü çubuğu + ana pencere, izin onboarding ekranı
- Kaydet / durdur / oynat global kısayolları
- Makro listesi, JSON kaydet/yükle/içe-dışa aktar
- Döngü sayısı / sonsuz döngü, hız çarpanı (0.1x–10x), acil durdurma kısayolu

### Faz 3 — Autoclicker
- CPS ayarı (yüksek CPS dahil), sol/sağ/orta buton, tek/çift tık
- Konum: imleç / sabit nokta / nokta listesi
- Rastgele jitter (zaman + konum), tıklama/süre limiti
- Basılı tut / aç-kapa modları; tetikleyici: klavye kısayolu veya orta/yan fare tuşu
- Teslim: Sistem (HID akışı, varsayılan) veya Doğrudan uygulamaya (`postToPid`, isteğe bağlı; Roblox bu tıkları yok sayıyor — 2026-11-17 kullanıcı testi); Hızlı yol (annotated session tap, diğer uygulamaların fare tap'lerini atlar; Roblox bunu da yok sayıyor). Roblox'taki kamera takılmasının ölçülen sebebi: Supercharge'ın aktif fare tap'i HID tıklarını ~40 ms bekletiyor
- Tıklama motoru `macrecord-clickd` yardımcı sürecinde (ClickService: tıklayıcı + fare tuşu tetikleyici + oturum tanılaması, stdin/stdout JSON); yardımcı yoksa/izinsizse aynı motor uygulama içinde çalışır. Her oturum sonunda `clicker` kategorisinde tek satır tanı logu (`postToPid`; imleç/genel tuş durumu değişmez; oyunlardaki kamera takılması için deneysel, oyunda henüz doğrulanmadı)

### Faz 4 — Editör
- Olay listesi / zaman çizelgesi görünümü
- Gecikme düzenleme, olay ekle/sil/taşı
- Mouse hareketlerini sadeleştirme (gereksiz noktaları kırpma)
- Geri al / yinele

### Faz 5 — Gelişmiş
- Makro başına kısayol, uygulamaya özel tetikleme
- Piksel rengi / görüntü koşulları (ScreenCaptureKit + Vision, tamamen yerel → Ekran Kaydı izni)
- Değişkenler, koşullar, döngüler; betik dili (JavaScriptCore)

### Faz 6 — Yayın
- Ad-hoc imzalı sürüm + Gatekeeper "Yine de Aç" rehberi (Developer ID hesabı alınırsa notarization eklenir)
- Homebrew cask, GitHub Releases otomasyonu
- TR/EN yerelleştirme, dokümantasyon

## 6. Riskler

| Risk | Önlem |
|---|---|
| Notarization olmadan Gatekeeper uyarısı (macOS 15+ "Yine de Aç" zorunlu) | Developer ID hesabı veya net kurulum rehberi + Homebrew |
| TCC izinlerinin her derlemede kaybolması | Sabit geliştirme imzası |
| Oyunların sentetik girdiyi reddetmesi | HID seviyesinde post, göreli delta; yine de garanti yok — README'de belirtilir |
| Swift 6 strict concurrency ile real-time kod çatışması | Motor modülleri Swift 5 modu |
| Hileye/kötüye kullanım algısı | README'de kullanım koşulları, oyun ToS uyarısı |

## 7. Kararlar (2026-10-04)

- [x] Uygulama adı: **macrecord** — bundle id: `io.github.<github-kullanıcı-adı>.macrecord` (Faz 0'da kesinleşir)
- [x] Lisans: **MIT**
- [x] Apple Developer hesabı: **yok** → ad-hoc imza; README'de "Yine de Aç" kurulum rehberi + Homebrew cask (`--no-quarantine` notu)
- [x] Minimum macOS: **14 Sonoma**

## 8. Durum (2026-10-04)

| Faz | Durum | Doğrulama |
|---|---|---|
| 0 Altyapı | ✅ | README, LICENSE, PRIVACY, CONTRIBUTING, CI, ağ kodu kontrolü |
| 1 Motor + benchmark | ✅ Kapı geçti | p99 14–40 µs (hedef < 1 ms), bkz. docs/BENCHMARKS.md |
| 2 MVP uygulama | ✅ | Derleniyor, arka planda açılıp ekran görüntüsüyle kontrol edildi |
| 3 Autoclicker | ✅ | Yapılandırma birim testleri |
| 4 Editör | ✅ | Düzenleme birim testleri (RDP, silme, gecikme taşıma) |
| 5 Gelişmiş | ✅ | Makro kısayolları, piksel bekleme, uygulama öne getirme, JS betikleri (testli) |
| 6 Yayın | ✅ | Universal .app, release workflow, cask, TR/EN |

Testler: 26 birim testi (`swift test`). Testler ve benchmark kullanıcının fare/klavyesine **hiç gerçek olay göndermez**
(dry-run null olaylar ve test sink'leri).

## 9. Bilinen Sınırlamalar / Sonraki Adımlar

- **Gerçek oynatma, kayıt ve autoclicker elle test edilmeli** (uygulamaya izin verip kısa bir makro). Otomatik testler bilinçli olarak gerçek girdi göndermiyor.
- Benchmark dry-run ölçer; gerçek olayların uygulamalara ulaşma gecikmesi ayrıca ölçülmedi.
- JS betiğinde API çağırmayan sonsuz döngü durdurulamaz (JavaScriptCore'un public zaman sınırı API'si yok).
- Uygulama ikonu yok (`App/AppIcon.icns` eklenirse build betiği kullanır).
- Ad-hoc imza: her derlemede TCC izni sıfırlanır → CONTRIBUTING'deki sabit imza kimliği.
- GitHub reposu, `homebrew-macrecord` tap reposu ve ilk `v0.1.0` etiketi henüz oluşturulmadı.
