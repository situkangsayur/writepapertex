# WritePaperTeX — Backlog

Status per 2026-09-25. Dimulai hari ini. Yang sudah jalan dan dibuktikan di
desktop: proyek, editor, pelengkapan otomatis, kompilasi, dan pratinjau PDF.
Di Android semuanya jalan kecuali kompilasi — lihat KT-2.

Legenda: `[x]` selesai · `[~]` sebagian · `[ ]` belum.

---

## Urutan pengerjaan

Platformnya diurutkan sesuai permintaan: **tablet Android dulu**, lalu Linux,
lalu Windows. Tapi urutan *fitur* tidak bisa mengikuti itu begitu saja, karena
satu hal menghalangi segalanya di Android: tidak ada TeX Live di sana.

| Tahap | Isi | Kenapa di sini |
|---|---|---|
| **A** | Editor, proyek, penampil PDF, kompilasi di Linux | Semua bagian ini bisa dibuat **dan dibuktikan** hari ini, karena TeX Live sudah ada di mesin pengembangan |
| **B** | Tectonic untuk Android | Palang pintu sesungguhnya. Sampai ini terbukti, versi tablet tidak bisa mengompilasi apa pun (lihat KT-2) |
| **C** | Tata letak tablet, muat proyek dari GitHub | Butuh A; memindahkan pola yang sudah terbukti di ReadPaper |
| **D** | Perkakas tabel, pelengkapan otomatis lanjutan, SyncTeX | Kenyamanan, setelah dasarnya kokoh |
| **E** | Windows | Paling akhir, sesuai permintaan |

Tahap A dikerjakan lebih dulu **bukan** untuk menomorduakan tablet, melainkan
karena antarmuka yang sama dipakai kedua platform, dan di Linux ia bisa diuji
sungguhan hari ini alih-alih ditebak.

---

## Fase 1 — Kompilasi

- [x] Antarmuka `LatexEngine` supaya desktop dan Android tidak perlu saling tahu
- [x] **Mesin latexmk/XeLaTeX** untuk desktop, memakai TeX Live yang sudah ada
- [x] Keluaran build ditaruh di `.writepapertex/build/`, bukan di sebelah sumbernya
- [x] Pengurai log: `!` error, `berkas:baris:` error, dan peringatan LaTeX/Package/Class
- [x] Pesan yang jelas ketika TeX Live tidak terpasang, bukan crash
- [ ] **Mesin Tectonic untuk Android** — palang pintu; lihat KT-2
- [ ] Kompilasi ulang otomatis saat berkas disimpan, dengan penundaan
- [ ] Batalkan kompilasi yang sedang berjalan
- [ ] BibTeX/Biber (latexmk sudah menjalankannya, tapi belum diuji di sini)
- [ ] SyncTeX dua arah: klik di PDF melompat ke sumbernya dan sebaliknya
      (`-synctex=1` sudah dinyalakan, berkasnya sudah dihasilkan)

## Fase 2 — Editor

- [ ] Penyorotan sintaks LaTeX: perintah, lingkungan, matematika, komentar
- [x] **Pelengkapan otomatis**: perintah, nama lingkungan, dan kunci
      `\ref`/`\cite` yang dibaca dari berkas proyek sendiri — itulah
      pelengkapan yang benar-benar menghemat waktu; tidak ada yang lupa
      `\section`, semua orang lupa apakah gambarnya `fig:overview` atau
      `fig:overview-2`. Diuji di desktop sungguhan: `\sec` memunculkan tiga
      perintah, `\ref{tab` memunculkan label dari berkas proyeknya.
- [x] `\begin{...}` melengkapi `\end{...}` sendiri, dengan kursor mendarat
      di dalam badannya — lupa `\end{...}` adalah cara paling sering sebuah
      berkas LaTeX berhenti terkompilasi
- [ ] Nomor baris, dan error ditandai di baris yang bersangkutan
- [ ] Cari dan ganti
- [ ] Urungkan/ulangi yang layak dipakai
- [x] Papan tik tambahan di layar sentuh untuk `\`, `{`, `}`, `$`, `&`, `%`,
      `_`, `^`, `~`, `\\` — di papan tik Android karakter-karakter ini
      semuanya di balik satu tombol lagi, dan itu melumpuhkan pengetikan LaTeX

## Fase 3 — Proyek

- [x] Buat proyek baru dari templat: artikel, artikel dengan tabel, laporan
- [ ] Templat IEEE dan skripsi
- [x] Buka folder yang sudah ada; di desktop juga lewat argumen baris perintah
      (`writepapertex ~/tulisan/paper`)
- [x] Pohon berkas, dengan berkas hasil build disembunyikan
- [x] Berkas utama dideteksi dari `\documentclass`, bukan dari namanya — menebak
      dari nama akan memilih `main.tex` bahkan pada proyek yang titik masuknya
      `skripsi.tex`
- [ ] Ganti berkas utama secara manual
- [ ] Beberapa berkas `.tex` dengan `\input`/`\include`
- [ ] Simpan otomatis

## Fase 4 — Tabel

Disebut khusus karena tabel LaTeX adalah bagian yang paling menyiksa ditulis
dengan tangan, terutama di tablet.

- [ ] Penyunting tabel visual: baris, kolom, gabung sel, perataan
- [ ] Sisipkan dari CSV dan dari papan klip
- [ ] `booktabs` sebagai bawaan, karena `\hline` bertumpuk jarang benar
- [ ] Tabel panjang (`longtable`) dan tabel lebar (`sidewaystable`)
- [ ] Sunting tabel yang sudah ada di berkas, bukan hanya membuat yang baru

## Fase 5 — Penampil PDF

- [x] Pratinjau berdampingan dengan editor (`pdfrx`, sama seperti ReadPaper)
- [~] Halaman dipertahankan saat dikompilasi ulang; posisi gulir di dalam
      halaman belum
- [ ] Lompat ke halaman, zoom
- [~] Bilah error di atas editor dengan nomor barisnya; belum bisa diketuk
      untuk melompat ke sana

## Fase 6 — GitHub

- [ ] Muat proyek dari repositori
- [ ] Commit dan push perubahan
- [ ] Profil repositori, sama seperti ReadPaper
- [ ] Android tidak punya biner git: pakai GitHub REST API, seperti ReadPaper

## Fase 7 — Tablet & desktop

- [x] Tata letak tablet: pohon berkas · editor · PDF berdampingan, dengan
      pohon berkas masuk laci di bawah 1100 dp
- [ ] Dukungan stylus dan papan tik luar
- [ ] Pintasan papan tik
- [ ] Build Linux (AppImage/deb)
- [ ] Build Windows

---

## Jurang fitur terhadap Overleaf dan TeXstudio

Ditulis setelah memeriksa keduanya, supaya jelas apa yang belum ada dan mana
yang memang tidak akan dikejar.

### Yang ada di Overleaf

| Fitur | Keadaan di sini |
|---|---|
| Pratinjau PDF berdampingan | **Ada** |
| Error ditampilkan beserta barisnya | **Ada**, tapi di bilah atas, belum sebagai tanda di baris kodenya |
| Kompilasi otomatis saat berubah | Belum |
| Templat jurnal (ribuan, resmi dari penerbit) | Baru tiga templat sendiri |
| Penyunting visual seperti Word | Belum — layak dipertimbangkan justru untuk tablet |
| Kolaborasi banyak orang serentak | **Tidak dikejar.** Butuh server; ini penyunting lokal. Kolaborasi lewat git sudah cukup |
| Track changes dan komentar | Belum; bisa dibuat di atas git tanpa server |
| Riwayat versi | Lewat git (Fase 6) |
| AI menjelaskan error kompilasi | Belum; menarik, dan kebetulan sejalan dengan rencana plugin di ReadPaper |

### Yang ada di autocomplete TeXstudio

Ini bagian yang paling layak ditiru, karena TeXstudio sudah menyelesaikan
masalah yang sama dengan rapi.

- [ ] **Format CWL** (*completion word list*) — format dari Kile yang dipakai
      TeXstudio, memuat daftar perintah beserta posisi placeholder-nya. Kalau
      kita membacanya, ribuan berkas CWL paket yang sudah ada bisa langsung
      dipakai, dan daftar perintah bawaan kita yang ditulis tangan tidak perlu
      tumbuh selamanya. **Ini yang paling besar hasilnya.**
- [ ] **Muat pelengkapan mengikuti `\usepackage`** — TeXstudio membaca CWL
      paket yang dipakai dokumen itu saja, jadi daftarnya relevan, bukan
      seluruh isi TeX Live
- [ ] **Placeholder yang bisa dilompati dengan Tab** — `\frac{•}{•}`: sekarang
      kursor hanya mendarat di satu tempat, sisanya harus dicari sendiri
- [ ] **Peringatan `\ref` ke label yang tidak ada** — kita sudah membaca
      seluruh label proyek untuk pelengkapan, jadi memeriksanya tinggal
      selangkah
- [ ] **Peringatan `\usepackage` ke paket yang tidak terpasang**
- [ ] Pelengkapan dari kata yang sudah ada di dokumen itu sendiri
- [x] Pelengkapan `\ref`/`\cite` dari berkas proyek — sudah ada
- [x] Melengkapi `\begin` dengan `\end`-nya sekaligus — sudah ada

### Keputusan yang diambil dari perbandingan ini

1. **Adopsi CWL** sebagai sumber pelengkapan, jangan menumbuhkan daftar
   bawaan dengan tangan. Daftar bawaan tetap ada sebagai cadangan untuk
   ketika berkas CWL tidak tersedia.
2. **Kolaborasi serentak tidak dikejar.** Itu menuntut server, dan proyek ini
   penyunting lokal yang menyimpan ke git. Kolaborasi lewat git sudah
   menjawab kebutuhan yang sama tanpa infrastruktur.
3. **Penyunting visual layak dipertimbangkan untuk tablet**, bukan meniru
   Overleaf begitu saja: mengetik LaTeX dengan papan tik layar memang berat,
   dan di situlah mode visual paling berguna.

### Sumber

- [Overleaf — Rich Text editor](https://www.overleaf.com/blog/the-updated-rich-text-editor-simplifies-team-collaboration)
- [Overleaf — Track changes](https://docs.overleaf.com/collaborating/track-changes)
- [Overleaf — Premium features](https://docs.overleaf.com/getting-started/free-and-premium-plans/premium-features)
- [TeXstudio — Background information (format CWL)](https://texstudio-org.github.io/background.html)
- [TeXstudio — FAQ (pemuatan CWL otomatis)](https://github.com/texstudio-org/texstudio/wiki/Frequently-Asked-Questions)
- [Berkas CWL untuk TeXstudio](https://github.com/brianschubert/texstudio-completion)

---

## Bug yang ditemukan saat pengujian menyeluruh (2026-09-25)

Ditemukan dengan menjalankan aplikasinya dan mencoba setiap fitur satu per
satu, bukan dari tes.

- [x] **Tombol Simpan selamanya mati.** `_dirty` tidak pernah diisi `true`,
      jadi penanda perubahan tidak pernah muncul dan satu-satunya cara
      menyimpan adalah dengan mengompilasi.
- [x] **Fokus hilang setelah menerima saran.** Mengetuk sebuah saran
      memindahkan fokus ke chip-nya, sehingga ketikan berikutnya dan Ctrl+S
      tidak masuk ke mana-mana.
- [x] **Setiap error tampil dua kali.** Pesan yang sama ada di keluaran
      latexmk dan di berkas `.log`, dan keduanya dibaca; sekarang
      dihilangkan duplikatnya.
- [x] **Keterangan saran terpotong separuh** karena tinggi chip-nya kurang.

---

## Lintas fase

- [x] Lisensi AGPL-3.0-or-later
- [ ] Uji pada perangkat sungguhan (tablet Moto Pad 60 Neo)
- [x] Publikasi APK ke `http://10.100.21.22:8899`, pola sama dengan ReadPaper
- [ ] **Belum terpasang di perangkat sungguhan.** MIUI menolak pemasangan
      paket *baru* lewat USB (`INSTALL_FAILED_USER_RESTRICTED`); ReadPaper
      lolos karena itu pembaruan paket yang sudah ada. Pasang dari 8899 lewat
      peramban.
- [ ] Rilis GitHub
- [ ] Dwibahasa (Indonesia/Inggris), sejak awal supaya tidak menumpuk utang
