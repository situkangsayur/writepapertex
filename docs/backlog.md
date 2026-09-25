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
| **C** | Tata letak tablet, muat proyek dari git — GitHub, GitLab, atau Gitea sendiri | Butuh A. Desktop lewat biner `git` bisa langsung; Android butuh smart HTTP (KT-6) |
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
- [~] **Mesin Tectonic untuk Android** — dicoba sungguhan pada 2026-09-25 dan
      **terhenti di titik yang jelas**: Tectonic bukan murni Rust, ia
      membungkus XeTeX dan meminta tujuh pustaka C lewat `pkg-config` target.
      Hanya `harfbuzz` yang punya opsi vendored; `fontconfig`, `freetype2`,
      `graphite2`, `icu`, dan `png` harus dibangun sendiri untuk
      `aarch64-linux-android` beserta sysroot `pkg-config`-nya. Rinciannya
      di KT-2.
- [ ] Bangun lima pustaka C itu untuk Android sebagai tahap tersendiri, dengan
      skrip build dan artefak yang disimpan supaya tidak diulang
- [ ] Cadangan yang bisa dipakai hari ini: kompilasi di komputer, PDF-nya
      di-commit, tablet tinggal menarik — tanpa infrastruktur baru
- [ ] Cadangan kedua: layanan kompilasi di komputer sendiri, dipanggil tablet
      lewat WireGuard yang sudah ada
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

- [x] **Penyunting tabel visual**: kisi yang disunting langsung, tambah/hapus
      baris dan kolom, perataan per kolom, jumlah baris judul, dan Tab
      berjalan urut menyusuri sel — tanpa itu papan tik tidak berguna untuk
      tabel
- [x] **Sisipkan dari papan klip / CSV**: pemisah ditebak sendiri (tab, titik
      koma, koma, pipa), tanda kutip CSV dihormati, baris pendek dilengkapi
      alih-alih datanya dibuang, dan kolom yang isinya angka otomatis rata
      kanan
- [x] **`booktabs` sebagai bawaan** — `\toprule`/`\midrule`/`\bottomrule`;
      `\hline` tetap tersedia lewat sakelar
- [x] Karakter yang akan merusak tabel (`&`, `%`, `_`, `$`, `#`, kurung
      kurawal) di-escape saat menulis LaTeX-nya
- [x] Penyisipan jatuh sebelum `\end{document}` kalau kursornya di luar badan
      dokumen — teks setelah itu diabaikan LaTeX, jadi tabelnya akan diam-diam
      tidak pernah muncul
- [ ] Gabung sel (`\multicolumn`, `\multirow`) lewat antarmuka
- [ ] Tabel panjang (`longtable`) dan tabel lebar (`sidewaystable`)
- [ ] Sunting tabel yang sudah ada di berkas, bukan hanya membuat yang baru

## Fase 5 — Penampil PDF

- [x] Pratinjau berdampingan dengan editor (`pdfrx`, sama seperti ReadPaper)
- [~] Halaman dipertahankan saat dikompilasi ulang; posisi gulir di dalam
      halaman belum
- [ ] Lompat ke halaman, zoom
- [~] Bilah error di atas editor dengan nomor barisnya; belum bisa diketuk
      untuk melompat ke sana

## Fase 6 — Git (GitHub, GitLab, Gitea, atau remote apa pun)

Proyek disimpan di git. Bukan hanya GitHub: **git lain, dan git lokal seperti
Gitea yang dipasang sendiri**, harus ikut jalan. Alasan dan pilihan teknisnya
di KT-6 — ringkasnya, cara ReadPaper (GitHub REST API) tidak dipakai ulang di
sini karena berarti satu adaptor per penyedia, selamanya.

- [x] **Desktop: panggil biner `git`.** Diuji terhadap repositori bare
      sungguhan — yang bagi `git` berperilaku persis seperti GitHub, GitLab,
      atau Gitea sendiri. 10 tes: clone, ubah, commit, push (dan remote-nya
      benar-benar menerima), pull, serta pull yang tidak membuang tulisan
      yang belum disimpan
- [x] Clone, pull, commit, push dari dalam aplikasi, lewat panel Git
- [x] Tampilkan perubahan lokal sebelum commit, beserta jenis perubahannya
- [x] Folder biasa bisa dijadikan repositori dari dalam aplikasi, dengan
      remote apa pun — GitHub, Gitea kantor, atau folder lain di komputer ini
- [x] Keluaran build tidak lagi muncul di `git status`: `.writepapertex/`
      berisi `.gitignore` yang mengabaikan dirinya sendiri, jadi `.gitignore`
      milik penulis tidak disentuh
- [ ] Uji terhadap Gitea sungguhan di jaringan, bukan hanya repositori bare
- [ ] Profil repositori (nama, remote, cabang, identitas commit)
- [ ] Identitas commit diambil dari pengaturan aplikasi, bukan dari git global
- [ ] **Android: protokol git smart HTTP**, diterapkan sendiri — satu
      penerapan untuk semua host. Clone dan pull dulu; commit dan push
      belakangan karena menulis *pack* jauh lebih rumit daripada membacanya
- [ ] Berkas hasil build sudah otomatis di luar direktori proyek, jadi
      `git status` tidak akan penuh `.aux` (lihat KT-4)
- [ ] `.gitignore` disiapkan saat proyek dibuat dari templat

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

- [x] **Format CWL** (*completion word list*) — sudah dibaca, termasuk
      argumen menjadi kurung kosong, `\begin{...}` menjadi lingkungan,
      akhiran klasifikasi TeXstudio (`#*`, `#m`) dibuang, penanda
      `%<...%>` dibuang, dan `#include:` diikuti. Sembilan berkas CWL
      dibundel (booktabs, tabularx, longtable, multirow, graphicx, amsmath,
      siunitx, hyperref, array); berkas CWL dari TeX Live tinggal ditaruh di
      folder asetnya tanpa mengubah kode. 19 tes.
- [x] **Muat pelengkapan mengikuti `\usepackage`** — hanya paket yang
      benar-benar dimuat dokumen itu yang dibaca. Dicari di tiga tempat
      berurutan: `.writepapertex/cwl/` milik proyek, folder pengguna, lalu
      yang dibundel — jadi sebuah proyek bisa menimpa yang bawaan
- [ ] Baca CWL dari TeX Live yang terpasang secara otomatis (sekarang harus
      disalin sendiri)
- [ ] **Placeholder yang bisa dilompati dengan Tab** — `\frac{•}{•}`: sekarang
      kursor hanya mendarat di satu tempat, sisanya harus dicari sendiri
- [x] **Peringatan `\ref` ke label yang tidak ada**, dengan nomor barisnya.
      LaTeX tidak gagal karena ini — ia mencetak `??` lalu jalan terus, dan
      itu mudah luput sampai orang lain yang membacanya. Berlaku untuk
      `\ref`, `\eqref`, `\autoref`, `\pageref`, dan `\nameref`
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
