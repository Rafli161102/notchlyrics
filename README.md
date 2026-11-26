# TouchBarLyrics

Lirik lagu tersinkronisasi untuk **macOS Touch Bar**, terutama audio yang dimainkan dari **Safari**. Aplikasi membaca Now Playing lewat `mediaremote-adapter`, mengambil lirik sinkronisasi dari sumber online, memisahkan vokal utama dan *backing vocal*, menyediakan romanisasi, serta menyinkronkan waktu lirik dengan energi vokal audio sistem.

## Persyaratan

- macOS **14.2+** dengan Touch Bar (`DFRFoundation`).
- **Xcode Command Line Tools**: `xcode-select --install`.
- **Atoll** terpasang di `/Applications/Atoll.app`, dengan:
  - `Contents/Resources/mediaremote-adapter.pl`
  - `Contents/Resources/MediaRemoteAdapter.framework`
- Akses **System Audio Recording / System Audio** bila memakai auto-sync vokal.
- Koneksi internet untuk pencarian lirik. LRCLIB dan NetEase dicoba paralel, dengan fallback Lyrics.ovh; lirik tanpa timing memakai estimasi.
- Default sumber hanya **Safari**, tetapi dapat dimatikan di menu.

Dependency runtime Atoll saat ini masih hard-coded; aplikasi tidak mengunduh atau memasangnya sendiri.

## Build lokal

```sh
cd /Users/macbookpro/bin/TouchBarLyricsSrc
./build.sh
```

Output ada di:

```text
.build/TouchBarLyrics.app
```

Build lalu pasang:

```sh
./build.sh --install
```

Aplikasi terpasang di `~/Applications/TouchBarLyrics.app`. Jalankan/restart manual, atau bila memakai LaunchAgent yang sudah terpasang:

```sh
launchctl kickstart -k "gui/$(id -u)/com.user.touchbarlyrics"
```

Versi diambil dari `VERSION`; nomor build dari `BUILD_NUMBER` atau variabel `BUILD_NUMBER`. `VERSION` dan `BUILD_NUMBER` dapat di-commit; tidak perlu menyimpan secret.

## Signing

Default memakai **ad-hoc** signing (`CODESIGN_IDENTITY=-`), cocok untuk penggunaan lokal, bukan distribusi publik.

Untuk Developer ID:

```sh
CODESIGN_IDENTITY="Developer ID Application: Nama Anda (TEAMID)" ./build.sh
```

Script memverifikasi signature dan mengaktifkan **hardened runtime + timestamp** untuk identitas selain ad-hoc. Tidak ada provisioning profile atau `.entitlements` khusus di repo.

## Notarization

Notarization **tidak bisa dijalankan tanpa**:
1. build yang di-sign **Developer ID Application**, bukan ad-hoc;
2. kredensial Apple untuk `notarytool` (Apple ID + app-specific password, atau App Store Connect API key);
3. akses internet ke Apple notary service.

Simpan kredensial sekali, tanpa menulisnya ke repo:

```sh
xcrun notarytool store-credentials TouchBarLyricsNotary \
  --apple-id "email@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Kemudian:

```sh
CODESIGN_IDENTITY="Developer ID Application: Nama Anda (TEAMID)" ./build.sh
NOTARY_PROFILE=TouchBarLyricsNotary ./notarize.sh
```

`notarize.sh` membuat ZIP, mengirim `notarytool submit --wait`, `stapler staple`, dan validasi. Variabel `APP_PATH`, `NOTARY_PROFILE`, dan `ZIP_PATH` dapat diatur. App Store Connect API key juga didukung oleh `notarytool`, tetapi pemanggilan resminya tidak disimpan di script.

## Runtime

- `mediaremote-adapter.pl ... stream --debounce=250` membaca Now Playing.
- `send 2` dipakai untuk play/pause.
- Sistem audio memakai `CATapDescription` + private aggregate device. Jika izin tidak diberikan, aplikasi **fallback ke timestamp** dan tetap menampilkan lirik.
- `NSAudioCaptureUsageDescription` sudah ada di `Info.plist`.
- Tema tersimpan di `~/Library/Application Support/TouchBarLyrics/themes.json`.
- Bundle identifier `com.user.TouchBarLyrics`; `LSUIElement` aktif; single instance ditegakkan aplikasi.
- Signal `SIGTERM`/`SIGINT`/`SIGHUP` dan shutdown sistem ditangani untuk menghentikan audio tap dan proses adapter.

## Fitur utama

- Karaoke per huruf/per kata, main + backing vocal.
- LRC/YRC + enhanced LRC + estimasi.
- Romanisasi Jepang, Korea, China, dan script non-Latin lainnya.
- Auto-sync vokal lead + backing.
- Warna adaptif artwork + WCAG contrast guard.
- Tema built-in/custom, layout, font, transisi, animation speed, reduced motion.

## Test / verifikasi

Saat ini belum ada XCTest/CI. Verifikasi dasar:

```sh
swiftc -swift-version 5 ...   # lihat perintah nyata di build.sh
codesign --verify --deep --strict .build/TouchBarLyrics.app
plutil -lint .build/TouchBarLyrics.app/Contents/Info.plist
```

Disarankan menambah XCTest untuk parser, romanizer, timing, palette, fetch ranking, dan regression vocal sync. Lihat `CHANGELOG.md`.
