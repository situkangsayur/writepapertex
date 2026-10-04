# Panduan teknis WritePaperTeX

Untuk yang membangun, mengubah, atau merilis aplikasinya. Gambaran besar —
tumpukan teknologi, susunan folder, dan pola yang dipakai berulang — sudah ada
di [tech-stack.md](tech-stack.md) dan tidak diulang di sini. Alasan di balik
keputusan besar ada di [keputusan-teknis.md](keputusan-teknis.md).

Dokumen ini mengisi yang di antaranya: cara menyiapkan mesin pengembangan,
membangun mesin TeX untuk Android, kontrak antara Dart dan Rust, dan cara
mengukur kompilasi di perangkat sungguhan.

---

## 1. Arsitektur singkat

```
Flutter / Dart  ──  LatexEngine ──┬── LatexmkEngine   (desktop: latexmk + XeLaTeX)
                                  └── TectonicEngine  (Android)
                                           │ dart:ffi, di isolate
                                           ▼
                                  libwptex_engine.so  (rust/, cdylib)
                                     ├── compile.rs  sesi Tectonic + laporan langkah
                                     ├── git.rs      libgit2
                                     └── lib.rs      permukaan C
```

Pemilihan mesin dan backend git ada di `workspace_screen.dart`:
`Platform.isAndroid || Platform.isIOS` memilih Tectonic dan `GitFfiBackend`,
selain itu `LatexmkEngine` dan `GitCliBackend`.

Yang perlu diingat saat menyentuh kode kompilasi:

- **Kode Rust tidak tinggal di repositori ini saja.** `rust/Cargo.toml`
  menunjuk ke `tectonic = { path = ".." }`: crate-nya disalin ke dalam pohon
  Tectonic yang sudah ditambal saat dibangun. `cargo build` di `rust/` secara
  langsung tidak akan jalan.
- **`panic = "unwind"` disengaja.** `wptex_compile` dan `guard()` di `git.rs`
  menangkap panic dengan `catch_unwind`. Dengan `abort`, panic di XeTeX
  mematikan aplikasi (SIGABRT) — itu yang terjadi pada percobaan pertama di
  perangkat.
- **`wptex_compile` mengubah keadaan seluruh proses**: `set_current_dir` ke
  folder berkas `.tex`, serta variabel lingkungan `TECTONIC_APP_DIR`,
  `TECTONIC_CACHE_DIR`, dan `FONTCONFIG_FILE` (lihat *Font* di bawah). Isolate berbagi proses yang sama, jadi jangan
  mengandalkan direktori kerja di sisi Dart setelah kompilasi.

---

## 2. Menyiapkan mesin pengembangan

| Perkakas | Versi / letak |
|---|---|
| Flutter | 3.44.5 (Dart 3.12), di `~/flutter/bin` |
| Android SDK | `~/Android/Sdk` |
| Android NDK | **28.2.13676358** — sama dengan bawaan Flutter 3.44, dan yang dipakai skrip |
| Rust | stable, dengan target `aarch64-linux-android` |
| cargo-ndk | `cargo install cargo-ndk` |
| Untuk vcpkg/fontconfig | `autoconf autoconf-archive automake libtool` |
| Lainnya | `git`, `python3`, `zip` |
| Desktop | `texlive-xetex latexmk git` |

```sh
export PATH="$HOME/flutter/bin:$PATH"
rustup target add aarch64-linux-android
cargo install cargo-ndk
sudo apt install autoconf autoconf-archive automake libtool python3 zip \
                 texlive-xetex latexmk
```

`minSdk` dan `ndkVersion` di `android/app/build.gradle.kts` mengikuti nilai
Flutter (`flutter.minSdkVersion` = 24, `flutter.ndkVersion`). `abiFilters`
hanya `arm64-v8a`, karena mesinnya hanya dibangun untuk itu.

---

## 3. Membangun mesin Tectonic untuk Android

```sh
/home/<anda>/…/writepapertex/scripts/build-tectonic-android.sh
```

**Jalankan dengan jalur absolut.** Skrip ber-`cd` ke pohon Tectonic sebelum
menghitung letak repositori dari `dirname "${BASH_SOURCE[0]}"`. Dengan jalur
relatif seperti `scripts/build-…`, `dirname` itu dibaca relatif terhadap pohon
Tectonic, dan langkah penyalinan crate serta pemasangan `.so` jatuh ke tempat
yang salah.

Pembangunan pertama lama (vcpkg membangun ICU dan kawan-kawannya); berikutnya
memakai ulang semuanya.

### Folder kerja

Semua yang berat disimpan di `WORK`, bawaannya
`~/.cache/writepapertex-android`:

```
~/.cache/writepapertex-android/
  vcpkg/              tujuh pustaka C untuk triplet arm64-android
  tectonic-src/       Tectonic pada tag tectonic@0.15.0, sudah ditambal
    wptex_engine/     salinan rust/ dari repositori ini
  openssl-src-stdio/  openssl-src yang sudah ditambal (5a di bawah)
```

**Folder ini, termasuk `vcpkg/` di dalamnya, harus folder sungguhan — bukan
symlink ke tempat sementara.** `vcpkg/` pernah berupa symlink ke folder
scratch sebuah sesi; saat folder itu dibersihkan, seluruh hasil build vcpkg
hilang dan harus dibangun ulang dari nol.

Variabel yang bisa ditimpa: `WORK`, `ANDROID_NDK_HOME` (bawaan
`~/Android/Sdk/ndk/28.2.13676358`), `TECTONIC_TAG` (bawaan `tectonic@0.15.0`).

### Tambalan, dan kenapa

Semua tambalan diterapkan pada salinan, tidak ada yang menyentuh
`~/.cargo/registry` (cargo memeriksa checksum-nya). Semuanya idempoten.

| | Tambalan | Kenapa |
|---|---|---|
| **a** | `-std=c++14` → `-std=c++17` di `engine_xetex` dan `xetex_layout` | header ICU 78 dari vcpkg menuntut C++17 |
| **b** | `cargo update -p time` | crate `time` yang terkunci di `Cargo.lock` Tectonic 0.15 tidak lagi terkompilasi dengan rustc masa kini |
| **c** | `TECTONIC_APP_DIR` di `crates/io_base/src/app_dirs.rs` | `app_dirs2` menanyakan folder data aplikasi ke konteks Java; tanpa konteks itu ia panik ("android context was not initialized") dan mematikan proses. Aplikasi sudah tahu foldernya, jadi ia memberitahukannya lewat variabel ini |
| **d** | `src/driver.rs`: keadaan berkas tanpa sidik jari dianggap **tidak** berubah | `.bbl` jatuh ke keadaan itu di setiap lintasan ("internal consistency problem when checking if ….bbl changed"), sehingga lintasan lengkap selalu mengulang TeX sampai batas enam kali. `.bbl` hanya berubah saat BibTeX jalan, dan itu sudah memicu ulangannya sendiri. Diukur di tablet: 7 lintasan/57 detik → 26 detik (14 detik setelah perbaikan font) |
| **5a** | `openssl-src`: buang `no-stdio` | dengan `no-stdio` OpenSSL tidak bisa memuat sertifikat dari berkas, dan setiap clone HTTPS berakhir "the SSL certificate is invalid". NDK 28 punya stdio lengkap |

Angka akhirnya, setelah tambalan **d** dan pengalihan font (lihat §6, *Font*):
lintasan cepat 6,9 detik, lintasan lengkap 14 detik, pada proposal disertasi
di tablet. Sebelum semua perbaikan itu lintasan cepat tidak menghasilkan PDF
dan lintasan lengkap makan 57 detik.

Tambalan **d** gagal keras ("Tambalan driver.rs gagal: polanya tidak
ditemukan") kalau teks sumbernya berubah — misalnya setelah `TECTONIC_TAG`
dinaikkan. Itu disengaja: tambalan yang diam-diam tidak terpasang akan
mengembalikan 57 detik itu tanpa ada yang sadar.

### Hasilnya

Langkah terakhir menyalin dua berkas ke
`android/app/src/main/jniLibs/arm64-v8a/`:

- `libwptex_engine.so` (±51 MB setelah `llvm-strip`) — Tectonic, XeTeX,
  libgit2, OpenSSL
- `libc++_shared.so` — runtime C++ NDK. Tanpa ini `dlopen` gagal dengan
  "library not found" yang tidak menyebut nama yang kurang

Keduanya **tidak** disimpan di riwayat git (`.gitignore`: terlalu besar dan
selalu bisa dibangun ulang). Jadi pada clone baru, skrip ini dan skrip bundel
di bawah harus dijalankan sekali sebelum APK pertama. Sesudahnya, jalankan
ulang hanya saat `rust/` atau tambalannya berubah.

APK yang dibangun tanpa `.so` ini tetap jalan, tetapi `isAvailable()` gagal
membuka pustakanya dan ruang kerja menampilkan *"Mesin Tectonic tidak ikut
pada build ini…"* alih-alih tombol yang gagal setiap kali ditekan.

---

## 4. Membangun bundel paket TeX

```sh
/home/<anda>/…/writepapertex/scripts/build-tectonic-bundle.sh
```

Butuh pohon Tectonic dari langkah 3. Skrip membangun CLI `tectonic` untuk
mesin pengembangan, lalu mengompilasi dengan cache kosong:

- templat aplikasi — diambil langsung dari `latex_project.dart`, supaya
  bundelnya persis mencakup paket yang dipakai templat;
- dokumen "serba ada" di `scripts/bundle-docs/` (amsmath, booktabs, TikZ,
  pgfplots, biblatex, font TeX Gyre lewat fontspec);
- opsional, proyek sungguhan lewat `WPTEX_BUNDLE_REPO=https://…` supaya kelas
  dokumen dan gaya sitasi kampus ikut. Jangan menaruh token di riwayat shell
  yang dibagikan.

Cache yang terisi di-zip ke `assets/bundle/tectonic-cache.zip` (±15 MB).
Seperti `.so`-nya, berkas ini diabaikan git. `pubspec.yaml` mendaftarkan
`assets/bundle/` sebagai aset, jadi tanpa berkas ini build APK tidak lengkap
dan kompilasi pertama di perangkat gagal saat memuat asetnya.

Di perangkat, `TectonicEngine` membongkarnya ke
`<application support>/tectonic-cache/` **tanpa menimpa** berkas yang sudah
ada (cache Tectonic beralamat isi), lalu menulis penanda `.bundle-siap` berisi
ukuran aset. Bundel baru dengan ukuran berbeda otomatis dibongkar lagi pada
kompilasi berikutnya; paket yang pernah diunduh pengguna tetap utuh.

---

## 5. Membangun APK dan menjalankan pemeriksaan

```sh
flutter pub get
dart format --line-length 100 --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Ketiga pemeriksaan pertama sama dengan yang dijalankan CI
(`.github/workflows/ci.yml`), yang juga memasang TeX Live supaya tes kompilasi
desktop benar-benar jalan. Di mesin tanpa TeX Live, tes di
`test/latexmk_engine_test.dart` melewati dirinya sendiri.

APK rilis saat ini ditandatangani dengan kunci debug (`signingConfig =
signingConfigs.getByName("debug")`). Akibatnya APK dari mesin pengembangan
lain tidak bisa memperbarui yang sudah terpasang tanpa mencopotnya dulu.

Desktop: `flutter run -d linux`, atau `flutter run -d linux -a
~/tulisan/paper` untuk langsung membuka sebuah folder (argumen pertama
`main()` adalah folder proyek).

### Memeriksa git terhadap server sungguhan

`tool/periksa_git.dart` menjalankan clone, commit, dan push lewat
`GitCliBackend` terhadap repositori sungguhan. Bukan bagian dari `flutter
test` karena butuh jaringan dan token:

```sh
WPTEX_REPO=https://github.com/pemilik/repo-uji.git WPTEX_TOKEN=… \
  dart run tool/periksa_git.dart
```

Pakai repositori yang memang disediakan untuk diuji. Token hanya dibaca dari
lingkungan; jangan pernah menuliskannya ke berkas di dalam repositori.

---

## 6. Kontrak FFI

Semua fungsi `extern "C"` ada di `rust/src/lib.rs`. String berupa UTF-8
berakhir NUL; penyangga galat diisi `write_err`, yang selalu mengakhiri dengan
NUL dan memotong di batas karakter.

### `wptex_compile`

```c
int32_t wptex_compile(const char *tex_path,      // jalur absolut berkas utama
                      const char *out_path,      // PDF yang diminta
                      const char *cache_dir,     // cache paket Tectonic
                      const char *progress_path, // berkas laporan langkah
                      int32_t     full_pass,     // 0 = cepat, lainnya = lengkap
                      char       *err_buf,
                      size_t      err_len);
```

| Kode | Arti | Isi `err_buf` |
|---|---|---|
| 0 | PDF ada di `out_path` | — |
| 1 | Tectonic gagal | pesan beserta rantai sebabnya, tiap sebab di baris `  disebabkan: …` |
| 2 | `tex_path` atau `out_path` bukan string C yang sah | `jalur berkas tidak sah` |
| 4 | PDF tidak bisa dipindah ke `out_path`, atau tidak ada | `PDF ada di … tapi tidak bisa dipindah: …` / `mesin selesai tanpa keluhan, tetapi PDF-nya tidak ada` |
| 5 | panic tertangkap | `mesin berhenti mendadak: …` |

Kode 3 tidak dipakai di sini. Dua kode lagi dibuat sisi Dart, bukan Rust:
**6** — isolate mati (`Mesin berhenti: …`), dan **7** — pengawas diam
menghentikan kompilasi.

Tectonic menulis PDF dengan nama berkas sumbernya di folder `out_path`; kalau
namanya berbeda, berkasnya di-*rename*, bukan dikompilasi ulang. Berkas antara
(`.aux`, `.bbl`, `.log`) disimpan (`keep_intermediates`), jadi
`<build>/<nama>.log` tersedia untuk diurai setelahnya.

Fungsi lain: `wptex_version()` (string statis), dan keluarga `wptex_git_*`
(`clone`, `status` → JSON, `commit` → 3 berarti "tidak ada yang berubah",
`pull`, `push`, `init`, `set_ca_bundle`). Semuanya mengembalikan 0 untuk
berhasil.

### Mode kompilasi

`compile::run` di `rust/src/compile.rs`:

| Mode | Pengaturan sesi | Yang terjadi |
|---|---|---|
| `Quick` (`full_pass == 0`) | `PassSetting::Default` + `reruns(0)` | satu lintasan TeX, BibTeX kalau ada `\bibdata`, lalu xdvipdfmx |
| `Full` | `PassSetting::Default` | BibTeX dan pengulangan TeX sampai mantap (maks. enam ulangan) |

**Jangan kembali ke `PassSetting::Tex` untuk lintasan cepat.** Ia berhenti di
`.xdv` dan tidak pernah menjalankan xdvipdfmx: setiap kompilasi cepat berakhir
tanpa PDF, dan setiap rebuild jatuh ke lintasan lengkap. Itulah bug yang
diperbaiki di 0.12.2.

Di desktop, `LatexmkEngine` memakai `latexmk -xelatex` untuk lintasan lengkap
dan memanggil `xelatex` langsung untuk lintasan cepat, keduanya dengan
`-file-line-error -halt-on-error -synctex=1`.

`needsFullPass` hanya diisi `TectonicEngine`, dari `logAsksForRerun()` atas
`.log` TeX (`Rerun to get`, `Citation … undefined`, `No file ….bbl`, dan
seterusnya — lihat `rerunMarkers`).

### Berkas kemajuan dan pengawas diam

- Rust menulis setiap pesan Tectonic ke `progress_path` —
  `<proyek>/.writepapertex/build/kemajuan.log` — satu baris satu pesan, langsung
  di-*flush*. Peringatan diberi awalan `peringatan: `, galat `galat: `.
  `LatexLogParser` membuang awalan itu, juga cap waktu `[7,9 s] `, sebelum
  mengurai; tanpa itu keduanya tertelan ke dalam nama berkas pesan.
- Dart membaca berkas itu tiap **400 md** dan meneruskan baris barunya, diberi
  cap waktu (`[3,2 s] …`), ke `onOutput`. Garis waktu yang sama menjadi `log`
  saat kompilasi berhasil — itulah isi *Rincian waktu kompilasi*.
- Pengawas berdetak tiap **10 detik** dan menghentikan kompilasi kalau tidak
  ada baris baru selama **3 menit** (`TectonicEngine.idleTimeout`). Isolate-nya
  di-`kill`, bukan sekadar diabaikan.

Hal halus: penanda aktivitas hanya diperbarui oleh pembaca berkas kemajuan,
dan pembaca itu berhenti lebih awal kalau `onOutput` null. Pemanggil yang
tidak memberi `onOutput` akan dihentikan tiga menit setelah mulai, seberapa
pun aktif mesinnya. `WorkspaceScreen` selalu memberinya.

### Font

`use_own_fonts()` di `rust/src/lib.rs` menulis
`<cache>/fontconfig/fonts.conf` yang hanya berisi `<cache>/fonts` (di
perangkat: `<application support>/tectonic-cache/fonts`) beserta folder cache
fontconfig-nya, lalu menyetel `FONTCONFIG_FILE` ke berkas itu. Berkasnya hanya
ditulis ulang kalau isinya berbeda.

Kenapa: setiap pencarian font lewat nama yang tidak ada — gaya ITB menanyakan
`\IfFontExistsTF{Times New Roman}` — membuat XeTeX membuka seluruh
`/system/fonts` satu per satu untuk membaca namanya. Diukur di tablet: sekitar
4 detik di **setiap** lintasan, separuh lintasan TeX proposal disertasi. Cache
fontconfig tidak menolong, karena XeTeX membaca nama itu sendiri dari berkas
fontnya.

Akibatnya font sistem Android tidak tersedia lewat nama. Font dari bundel dan
`.otf`/`.ttf` di proyek dimuat lewat nama berkas (lewat pencarian berkas TeX,
bukan fontconfig), jadi tidak terpengaruh. Lihat juga
`scripts/bundle-docs/serbaguna-font.tex`, yang sengaja memakai nama berkas
supaya font TeX Gyre ikut masuk bundel.

### Sidik sumber (`SourceStamp`)

`lib/src/features/compile/domain/source_stamp.dart`. Sebelum kompilasi
(kecuali dipaksa), `reusablePdf()` membandingkan sidik saat ini dengan
`.writepapertex/build/sidik-sumber.txt`. Cocok dan PDF-nya ada → PDF itu
dipakai, mesin tidak dijalankan.

Sidiknya: `pass=<cepat|lengkap>`, `utama=<berkas>`, lalu baris
`jalur|ukuran|waktu-ubah-ms` yang diurutkan, untuk setiap berkas berakhiran
`.tex .bib .cls .sty .bst .bbx .cbx .def .png .jpg .jpeg .pdf .eps .svg .gif
.tiff` di luar `.git/` dan `.writepapertex/`. PDF hasil kompilasi yang disalin
ke akar proyek dikecualikan; kalau tidak, sidiknya basi begitu PDF itu ditulis.

Lintasan ikut dihitung, jadi hasil lintasan cepat tidak menjawab permintaan
lintasan lengkap. `remember()` dipanggil **setelah** PDF disalin ke akar
proyek. Kalau menambah jenis berkas yang memengaruhi hasil (mis. `.csv` yang
dibaca `pgfplotstable`), tambahkan ke `watched` — kalau tidak, perubahannya
tidak memicu kompilasi.

---

## 7. Mengukur kompilasi di perangkat sungguhan

Build rilis tidak bisa dibaca lewat `run-as`, jadi log dan berkas build dari
dalam aplikasi tidak bisa diambil. Jangan meminta pengguna menyalin log dari
tablet. Yang bisa dilakukan: memanggil **pustaka yang sama persis**
(`libwptex_engine.so`) dari program kecil di `/data/local/tmp`, lewat adb.
Mesinnya sama, perangkatnya sama; yang tidak ikut hanya Flutter.

### Harness

```c
// harness.c — ./harness <tex> <pdf> <cache> <progress> <full:0|1>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

typedef int (*compile_fn)(const char*, const char*, const char*, const char*,
                          int, char*, size_t);
static double t0; static const char *prog; static volatile int done = 0;

static double now(void) {
  struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

// Mencetak baris baru dari berkas kemajuan, diberi cap waktu.
static void *watch(void *arg) {
  long off = 0; char buf[4096];
  while (!done) {
    FILE *f = fopen(prog, "r");
    if (f) {
      fseek(f, off, SEEK_SET);
      while (fgets(buf, sizeof buf, f)) printf("[%7.2f] %s", now() - t0, buf);
      fflush(stdout); off = ftell(f); fclose(f);
    }
    usleep(100000);
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 6) { fprintf(stderr, "argumen kurang\n"); return 2; }
  void *h = dlopen("./libwptex_engine.so", RTLD_NOW);
  if (!h) { printf("dlopen: %s\n", dlerror()); return 1; }
  compile_fn fn = (compile_fn)dlsym(h, "wptex_compile");
  prog = argv[4]; unlink(prog);
  t0 = now();
  pthread_t th; pthread_create(&th, 0, watch, 0);
  char err[4096] = {0};
  int r = fn(argv[1], argv[2], argv[3], argv[4], atoi(argv[5]), err, sizeof err);
  usleep(300000); done = 1; pthread_join(th, 0);
  printf("[%7.2f] kode=%d %s\n", now() - t0, r, err);
  return r;
}
```

### Langkah

```sh
NDK=~/Android/Sdk/ndk/28.2.13676358
CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang
LIBS=android/app/src/main/jniLibs/arm64-v8a
D=/data/local/tmp/wptex

$CC -O2 harness.c -o harness

mkdir -p cache && (cd cache && unzip -q ../assets/bundle/tectonic-cache.zip)

adb shell mkdir -p $D/out
adb push harness $LIBS/libwptex_engine.so $LIBS/libc++_shared.so $D/
adb push cache $D/cache
adb push /jalur/ke/proyek-uji $D/proj

# cepat (0) lalu lengkap (1); masing-masing dua kali
adb shell "cd $D && LD_LIBRARY_PATH=. ./harness $D/proj/main.tex $D/out/main.pdf $D/cache $D/out/kemajuan.log 0"
adb shell "cd $D && LD_LIBRARY_PATH=. ./harness $D/proj/main.tex $D/out/main.pdf $D/cache $D/out/kemajuan.log 1"

adb shell rm -rf $D   # bersihkan setelah selesai
```

Catatan:

- Folder `out` harus sudah ada; di aplikasi, `ensureBuildDir` yang
  membuatnya.
- Jalankan tiap mode dua kali. Pemanggilan pertama pada cache baru bisa
  memuat pekerjaan sekali jalan; yang kedua yang mewakili pemakaian
  sehari-hari.
- Bandingkan cap waktu antarbaris, bukan hanya totalnya. Rincian per langkah
  inilah yang menunjukkan bahwa satu setengah menit dulu bukan jaringan atau
  bundel (0,6 detik), melainkan lintasan TeX yang diulang tujuh kali.
- Pakai proyek sungguhan (berbab, dengan bibliografi dan gambar), bukan
  templat. Masalah kecepatan tidak muncul di dokumen satu halaman.
- Untuk membandingkan sebelum/sesudah sebuah tambalan, simpan `.so` lama
  dengan nama lain dan jalankan keduanya dengan proyek dan cache yang sama.

---

## 8. Merilis

1. Naikkan `version:` di `pubspec.yaml` — `X.Y.Z+N`, dengan `N` (versionCode
   Android) selalu bertambah.
2. Commit, lalu tag dan push:
   ```sh
   git tag -a vX.Y.Z -m "WritePaperTeX X.Y.Z"
   git push && git push origin vX.Y.Z
   ```
3. Bangun APK dan beri nama sesuai versinya:
   ```sh
   flutter build apk --release
   cp build/app/outputs/flutter-apk/app-release.apk writepapertex_vX.Y.Z.apk
   ```
4. Rilis GitHub dengan APK terlampir:
   ```sh
   gh release create vX.Y.Z writepapertex_vX.Y.Z.apk#"WritePaperTeX X.Y.Z (arm64 APK)" \
     --repo situkangsayur/writepapertex --title "WritePaperTeX X.Y.Z" --notes "…"
   ```
   Catatan rilis menyebut apa yang berubah bagi pemakai, dengan angka kalau
   ada (mis. "26 → 14 detik").
5. Perbarui halaman unduh internal: salin APK ke foldernya, arahkan tautan
   "terbaru" ke berkas baru, dan perbarui nomor versi, md5, serta keterangan
   "Baru di X.Y.Z". Halaman ini yang dipakai memasang ke tablet, jadi rilis
   belum selesai sebelum halaman ini ikut diperbarui.

Sebelum langkah 3, pastikan `jniLibs/arm64-v8a/` dan
`assets/bundle/tectonic-cache.zip` ada dan mutakhir — keduanya tidak ada di
git, jadi yang terbawa ke APK adalah apa pun yang kebetulan ada di mesin
pembangun. Kalau `rust/` atau tambalannya berubah sejak build terakhir,
jalankan ulang skrip mesinnya dulu.

---

## 9. Konvensi

- **Pesan commit dalam bahasa Indonesia, menjelaskan sebab, bukan daftar
  perubahan.** Baris judul menyebut masalahnya dari sisi pemakai ("Lintasan
  cepat yang tidak pernah menghasilkan PDF, …"); badannya menjelaskan apa yang
  diukur, apa sebabnya, dan angka sebelum/sesudah.
- **Komentar kode juga menjelaskan kenapa.** Hampir setiap keputusan yang
  tidak jelas punya komentar yang menyebut kejadian yang memicunya. Pertahankan
  itu; komentar "apa" tidak berguna.
- **Antarmuka dan pesan galat dalam bahasa Indonesia**, dan pesan galat
  menyebut sebab, bukan gejala. Pesan asli dari git atau Tectonic tetap dibawa
  di bawahnya.
- **Ukur dulu, baru ubah.** KT-7 dan perbaikan 0.12.2 sama-sama berawal dari
  cap waktu per langkah, bukan dugaan.
- **Format** dengan `dart format --line-length 100`; CI menolak yang tidak.
- **Kontribusi** di bawah AGPL-3.0-or-later dengan `git commit -s` (DCO).
- Keputusan yang sulit diubah masuk [keputusan-teknis.md](keputusan-teknis.md)
  sebagai KT baru; pekerjaan yang belum selesai masuk
  [backlog.md](backlog.md).
