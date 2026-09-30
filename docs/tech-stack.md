# Tumpukan teknologi, arsitektur, pola, dan fitur

Dokumen ini menjawab "dibuat dari apa, disusun bagaimana, dan bisa apa".
Untuk **kenapa** sebuah keputusan diambil, lihat
[keputusan-teknis.md](keputusan-teknis.md); untuk yang belum ada,
[backlog.md](backlog.md).

Angka saat ditulis (2026-09-30): 31 berkas Dart, 16 berkas uji, 211 tes,
ditambah satu crate Rust.

---

## 1. Tumpukan teknologi

### Di sinilah Rust-nya

WritePaperTeX punya inti Rust; pendampingnya, ReadPaper, **tidak**. Perbedaan
itu bukan selera, melainkan akibat dari satu kenyataan: **Android tidak punya
TeX Live.** Tidak ada `pdflatex` untuk dipanggil, tidak ada folder paket untuk
dibaca, dan tidak ada cara memasangnya. Jadi mesin TeX-nya harus ikut di dalam
aplikasi — dan satu-satunya mesin TeX yang bisa dibawa seperti itu adalah
**Tectonic**, XeTeX yang dibungkus ulang dengan Rust.

```
Antarmuka          Flutter / Dart
      │
      │  dart:ffi
      ▼
wptex_engine       crate Rust (cdylib)  →  libwptex_engine.so  ±51 MB
      ├── tectonic     Rust, membungkus XeTeX (C/C++)
      └── git2         libgit2, di-vendor beserta OpenSSL-nya
```

Yang ada di sisi Rust hanya dua hal, dan keduanya memang tidak pantas ditulis
ulang di Dart:

| Bagian | Isinya | Kenapa di Rust |
|---|---|---|
| **Kompilasi TeX** | sesi Tectonic beserta penampung status yang melaporkan langkahnya | XeTeX bukan sesuatu yang bisa ditulis ulang; membawanya adalah satu-satunya jalan |
| **Git di Android** | libgit2 dengan OpenSSL yang di-vendor | protokol git yang sudah teruji dipakai, dan tidak bergantung pada apa pun yang terpasang di perangkat |

Sisanya — penyunting, pelengkapan otomatis, pengurai log LaTeX, sidik sumber,
perkakas tabel, ruang kerja — seluruhnya Dart.

### Bahasa dan kerangka

- **Dart 3.12** / **Flutter 3.44.5**, Material 3.
- **Rust 2021**, crate `cdylib`, dibangun untuk `aarch64-linux-android`
  dengan `cargo-ndk` dan tujuh pustaka C dari vcpkg.
- Bahasa antarmuka: Indonesia.

### Paket Dart yang dipakai

| Paket | Perannya |
|---|---|
| `flutter_riverpod` | keadaan aplikasi |
| `pdfrx` | pratinjau PDF hasil kompilasi, berdampingan dengan sumbernya |
| `ffi` | memanggil `libwptex_engine.so` |
| `archive` | membongkar cache paket TeX dari dalam APK, dan ekspor proyek jadi ZIP |
| `http` | mengunduh arsip proyek |
| `file_picker`, `path`, `path_provider` | berkas dan folder proyek |

### Yang dibawa di dalam APK

- `libwptex_engine.so` (±51 MB) — Tectonic beserta XeTeX dan libgit2.
- **Cache paket TeX** sebagai aset zip. Dibongkar sekali saat pertama dipakai.
  Tanpa ini kompilasi pertama harus mengunduh berpuluh paket satu per satu,
  bergantung jaringan, dan satu unduhan yang gagal berakhir sebagai
  "failed to open input file hyph-en-us.tex" — pesan yang tidak menyebut
  jaringan sama sekali.

---

## 2. Arsitektur

```
lib/src/
  core/utils/
  features/
    project/    ruang kerja, profil proyek, pohon berkas, tambah berkas
    editor/     penyunting LaTeX, sorotan sintaks, pelengkapan otomatis, CWL
    compile/    mesin TeX (Tectonic lewat FFI, latexmk di desktop), pengurai log
    viewer/     pratinjau PDF
    git/        clone, commit, push — dua backend
    table/      perkakas tabel

rust/src/
  lib.rs      permukaan C yang dipanggil Dart
  compile.rs  sesi Tectonic beserta laporan langkahnya
  git.rs      libgit2
```

### Dua mesin di balik satu antarmuka

`LatexEngine` adalah satu-satunya yang dikenal antarmuka. Di baliknya:

- **`TectonicEngine`** — Android dan mana pun tanpa TeX Live. Berjalan di
  isolate tersendiri, karena kompilasi memblokir dan di thread utama itu
  berarti antarmuka membeku.
- **`LatexmkEngine`** — desktop yang sudah punya TeX Live.

### Dua backend git di balik satu antarmuka

`GitBackend`: biner `git` di desktop, libgit2 lewat FFI di Android. Token
dikirim lewat `GIT_ASKPASS` — skrip sementara berizin `0700` yang dihapus
setelah selesai — jadi ia tidak pernah masuk baris perintah atau
`.git/config`.

---

## 3. Pola yang dipakai berulang

### Yang lama harus terlihat bergerak

Kompilasi disertasi bisa makan semenit. Bilah kemajuan yang diam tidak bisa
dibedakan dari aplikasi yang menggantung, jadi sisi Rust menuliskan setiap
langkah ke sebuah berkas dan sisi Dart membacanya sambil menunggu. Tiap baris
diberi cap waktu, dan rinciannya bisa dibuka dari menu Kompilasi.

### Diam yang dicurigai, bukan lamanya

Pengawasnya menghitung **berapa lama tidak ada kemajuan**, bukan berapa lama
totalnya. Kompilasi pertama sebuah disertasi memang bisa sepuluh menit;
memotongnya di menit kelima berarti membunuh pekerjaan yang benar tepat
sebelum selesai. Yang pantas dicurigai adalah mesin yang tiga menit tidak
melapor apa pun.

### Kompilasi yang tidak perlu tidak dijalankan

TeX tidak mengenal kompilasi bertahap, jadi yang bisa dihemat bukan
kompilasinya melainkan kompilasi yang memang tidak perlu terjadi. Sidik jari
murah — nama, ukuran, dan waktu ubah tiap berkas sumber — disimpan bersama
hasil build; selama cocok, PDF terakhir yang dipakai. Diukur di tablet:
1 menit 1 detik menjadi 0 milidetik.

### Merah hanya untuk yang menggagalkan

`Underfull \hbox` adalah keluhan penataan huruf; dokumennya tetap terbit.
Tetapi TeX menulisnya dalam bentuk yang sama dengan galat sungguhan, jadi
pengurainya harus membedakannya — kalau tidak, layar memerah oleh puluhan
baris yang tidak perlu ditindaklanjuti dan galat yang sebenarnya tenggelam.

### Panic tidak boleh mematikan aplikasi

`[profile.release] panic` sengaja **bukan** `abort`. Panic di dalam Tectonic
harus bisa ditangkap dan dilaporkan sebagai kegagalan kompilasi, bukan
menjatuhkan seluruh aplikasi beserta tulisan yang belum tersimpan.

---

## 4. Fitur yang sudah ada

- **Penyunting LaTeX** dengan sorotan sintaks, palet warna yang bisa dipilih,
  dan baris tombol untuk `\ { } $ &` — yang semuanya tersembunyi di papan tik
  Android.
- **Pelengkapan otomatis** perintah, lingkungan, dan — yang paling berguna —
  kunci `\ref` dan `\cite` yang dibaca dari berkas proyek sendiri. Format CWL,
  sama dengan TeXstudio.
- **Kompilasi di tablet** lewat Tectonic, dengan laporan langkah bercap waktu.
  Lintasan cepat 9,8 detik, lintasan penuh 1 menit 1 detik pada disertasi
  sungguhan.
- **Pratinjau PDF** berdampingan, dengan halaman yang tidak terlempar ke awal
  setiap kali dikompilasi ulang.
- **Galat yang menunjuk barisnya**, dan pesannya bisa disalin.
- **Sistem ruang kerja**: berpindah proyek tanpa menutup aplikasi, tiap proyek
  mengingat remote dan tokennya sendiri.
- **Clone git sungguhan** dari GitHub, GitLab, atau Gitea, termasuk repositori
  privat; arsip ZIP hanya sebagai cadangan.
- **Tambah berkas** `.tex`, `.bib`, `.sty`, atau gambar dari perangkat, dengan
  penyambungan otomatis ke berkas utama.
- **Perkakas tabel** dan ekspor proyek sebagai ZIP.

---

## 5. Cara menjalankan pemeriksaan

```sh
flutter analyze
flutter test

# Membangun ulang mesin Rust untuk Android (lama, sekali saja)
scripts/build-tectonic-android.sh
```
