# Keputusan teknis — WritePaperTeX

Keputusan yang sulit diubah setelah ada kode di atasnya. Satu bagian satu
keputusan: apa, kenapa, dan apa yang dikorbankan.

---

## KT-1 — Flutter + Dart, basis yang sama dengan ReadPaper

**Status:** ditetapkan.

Diminta secara eksplisit: "base yang sama dengan ReadPaper, bahasa dan
tech-nya". Konsekuensi yang bagus: tata letak tablet, pemilih berkas,
penampil PDF (`pdfrx`), dan pola sinkronisasi GitHub sudah terbukti di
ReadPaper dan bisa dipindahkan, bukan ditemukan ulang.

Prioritas platform, sesuai permintaan: **tablet Android lebih dulu**, lalu
**Linux**, lalu **Windows**.

---

## KT-2 — Dua mesin LaTeX di balik satu antarmuka

**Status:** `LatexmkEngine` selesai dan teruji; `TectonicEngine` belum.

Ini masalah terbesar proyek ini, dan lebih baik dinyatakan terang-terangan:
**Android tidak punya TeX Live.** Tidak ada `pdflatex` untuk dipanggil, dan
TeX Live lengkap berukuran beberapa gigabita — tidak mungkin dibundel ke APK.

Karena itu ada dua mesin di balik satu antarmuka `LatexEngine`:

| Mesin | Untuk | Keadaan |
|---|---|---|
| **latexmk / XeLaTeX** | Linux, Windows, macOS | **Selesai.** Memakai TeX Live yang sudah ada di mesin — membundel salinan kedua akan sia-sia dan tidak sopan |
| **Tectonic** | Android | **Belum.** Mesin TeX lengkap yang ditulis ulang dengan Rust, mandiri, dan mengunduh paket sesuai kebutuhan lalu menyimpannya |

Tectonic dipilih karena tiga alasan yang kebetulan bertemu: ia satu-satunya
mesin TeX lengkap yang realistis dibundel ke aplikasi seluler, ia **berbasis
Rust** persis seperti yang diminta, dan sudah ada preseden memakainya di
Android lewat `cargo-ndk` (proyek TeXslate). Penyambungannya lewat
`flutter_rust_bridge`, pola yang sama dengan rencana inti Rust di ReadPaper.

**Yang belum terbukti dan harus dibuktikan lebih dulu**: kompilasi silang
Tectonic ke `aarch64-linux-android`, dan berapa besar tambahannya pada APK.
Sampai itu terbukti, versi Android belum bisa mengompilasi apa pun. Jangan
menulis antarmuka yang mengandaikannya sudah ada.

**Cadangan kalau Tectonic tidak bisa**: layanan kompilasi di komputer sendiri
yang dipanggil tablet lewat jaringan lokal. Lebih lemah — perlu jaringan dan
sebuah komputer — tapi jauh lebih pasti.

---

## KT-3 — XeLaTeX, bukan pdfLaTeX

**Status:** ditetapkan.

XeLaTeX membaca UTF-8 dan font sistem tanpa upacara. Untuk tulisan berbahasa
Indonesia dan untuk kutipan beraksara lain, pdfLaTeX menuntut paket dan
pengaturan tambahan yang tidak ada gunanya di sini. Tectonic pun berbasis
XeTeX, jadi dua mesinnya berperilaku sama.

---

## KT-4 — Keluaran build di luar direktori proyek

**Status:** selesai dan teruji.

Satu kompilasi LaTeX meninggalkan belasan berkas: `.aux`, `.log`, `.out`,
`.toc`, `.fls`, `.fdb_latexmk`, `.synctex.gz`, dan seterusnya. Kalau ditaruh
di sebelah sumbernya, proyek yang dimuat dari GitHub akan memperlihatkan
belasan perubahan yang tidak pernah ditulis siapa pun.

Semuanya masuk ke `.writepapertex/build/`. Ada tesnya: setelah kompilasi,
direktori proyek harus hanya berisi berkas yang memang ditulis penulisnya.

---

## KT-5 — Lisensi AGPL-3.0-or-later

**Status:** ditetapkan.

Sama dengan ReadPaper, dan dengan alasan yang sama: boleh dipakai, diubah,
bahkan dijual, tapi tidak boleh ditutup. Kalau nanti ada layanan kompilasi
yang dijalankan sebagai server, AGPL yang membuat sumbernya tetap wajib
terbuka — dan layanan itu memang salah satu cadangan di KT-2.

---

## KT-6 — Git apa pun, bukan hanya GitHub

**Status:** ditetapkan sebagai lingkup; belum ada kodenya.

Proyek LaTeX disimpan di git — GitHub, **atau git lain, atau Gitea yang
dipasang sendiri**. Itu mengubah rancangannya, karena ReadPaper menyelesaikan
masalah yang mirip dengan cara yang **tidak** bisa dipakai ulang di sini.

### Kenapa cara ReadPaper tidak cukup

ReadPaper memakai **GitHub REST API** di Android, karena Android tidak punya
biner `git`. Itu berhasil justru karena ReadPaper hanya perlu bicara dengan
GitHub. Begitu Gitea dan GitLab ikut masuk, jalan itu berarti menulis satu
adaptor per penyedia — dan setiap penyedia baru menjadi pekerjaan baru
selamanya.

### Yang dipilih

| Platform | Cara |
|---|---|
| Linux, Windows, macOS | Panggil biner `git`. Otomatis bekerja dengan GitHub, GitLab, Gitea, Bitbucket, remote SSH biasa, bahkan folder lokal |
| Android | **Protokol git smart HTTP**, diterapkan sendiri |

Git smart HTTP adalah protokol yang sama yang dipakai `git clone https://…`
ke server mana pun. Satu penerapan bekerja untuk **semua** host, termasuk
Gitea yang dipasang di jaringan sendiri — tanpa satu pun adaptor khusus
penyedia.

### Yang dikorbankan

Ini jelas lebih berat daripada memanggil REST API: perlu menegosiasi
kemampuan, membaca dan menulis berkas *pack*, serta menghitung ulang objek.
Tapi biayanya dibayar sekali, sementara pendekatan adaptor menagih setiap kali
ada penyedia baru — dan permintaannya memang "GitHub ataupun git lainnya atau
git lokal seperti Gitea".

### Urutan yang masuk akal

1. **Desktop lebih dulu** lewat biner `git`. Itu langsung memenuhi seluruh
   kebutuhan di Linux dan Windows, dan bisa diuji terhadap Gitea sungguhan.
2. **Android: clone dan pull** dulu (hanya butuh membaca pack), yang sudah
   cukup untuk menulis dari tablet atas proyek yang disiapkan di komputer.
3. **Android: commit dan push** terakhir, karena menulis pack jauh lebih
   rumit daripada membacanya.

### Cadangan

Kalau smart HTTP ternyata terlalu berat, cadangannya adalah memakai `dart_git`
atau pustaka sejenis bila sudah cukup matang — **perlu dicek saat tahapnya
tiba**, jangan diandalkan sekarang.
