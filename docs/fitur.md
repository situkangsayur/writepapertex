# Fitur WritePaperTeX

Dokumen ini menjawab "bisa apa", tanpa istilah teknis yang tidak perlu. Tiap
fitur disertai alasannya, karena hampir semuanya lahir dari satu kejengkelan
yang nyata saat menulis paper di tablet.

Untuk cara memakainya langkah demi langkah, lihat
[panduan-pengguna.md](panduan-pengguna.md). Untuk "dibuat dari apa dan disusun
bagaimana", lihat [tech-stack.md](tech-stack.md). Untuk yang belum ada,
[backlog.md](backlog.md).

Keadaan per versi 0.12.2 (2026-10-04).

---

## Proyek

- **Layar pembuka dengan lima jalan masuk.** Lanjutkan proyek terakhir, buka
  folder, buka satu berkas `.tex`, bongkar arsip ZIP, atau clone repositori
  git. Paper datang dari mana saja — dari pembimbing lewat surel, dari GitHub,
  dari folder lama — dan semuanya harus bisa dibuka tanpa memindahkannya dulu
  di komputer.
- **Proyek baru dari templat.** Tiga templat: *Artikel*, *Artikel dengan
  tabel* (sudah memuat `booktabs`), dan *Laporan / skripsi* (berbab, dengan
  daftar isi). Halaman kosong di tablet adalah tempat yang buruk untuk mulai
  mengingat preamble.
- **Berkas utama dicari dari `\documentclass`, bukan dari namanya.** Menebak
  dari nama akan memilih `main.tex` bahkan pada proyek yang titik masuknya
  `skripsi.tex`. Kalau tebakannya salah, tekan lama berkas `.tex` lain di
  pohon berkas untuk menjadikannya berkas utama.
- **Pohon berkas dengan folder yang bisa dibuka-tutup.** Disertasi biasanya
  terbagi ke `bab/`, `gambar/`, `pustaka/`; daftar datar berisi tiga puluh
  berkas tidak bisa dijelajahi. Folder tertutup menunjukkan berapa isinya, dan
  berkas hasil build disembunyikan.
- **Tambah berkas.** Buat bab, daftar pustaka, berkas gaya, atau kelas dokumen
  baru — lengkap dengan isi awal, dan langsung disambungkan ke berkas utama
  (`\input`, `\bibliography`/`\addbibresource`, `\usepackage`). Berkas yang
  dibuat tetapi tidak pernah dipanggil adalah keluhan paling umum di editor
  LaTeX mana pun: berkasnya ada di daftar, tetapi tidak muncul di PDF.
- **Ambil gambar dan berkas dari perangkat.** Gambar disalin ke folder proyek
  dan disisipkan sebagai `figure` lengkap dengan caption dan label; `graphicx`
  ditambahkan ke preamble kalau belum ada. Disalin, bukan dirujuk, supaya ikut
  terbawa saat proyeknya diarsipkan atau dikirim ke git.
- **Berpindah proyek tanpa menutup ruang kerja.** Ketuk nama proyek di bilah
  atas. Proposal, artikel jurnal, dan slide seminar sering disunting
  bergantian dalam satu duduk.
- **Tiap proyek mengingat remote, cabang, token, dan identitas commit-nya
  sendiri.** Token disimpan terpisah dari daftar proyek, di berkas yang hanya
  bisa dibaca pemiliknya.
- **Simpan PDF dan ekspor proyek sebagai ZIP.** Arsipnya tidak memuat berkas
  hasil build: penerimanya menginginkan sumbernya, bukan keluaran mesin orang
  lain.

## Penyunting dan pelengkapan

- **Sorotan sintaks dengan empat palet**: *Tenang*, *Tegas*, *Kertas*, dan
  *Tanpa warna*. Pilihannya diingat. Aplikasi mengikuti mode terang/gelap
  perangkat.
- **Baris tombol tambahan** untuk `\ { } $ & % _ ^ ~ \\ [ ]`, hanya di layar
  sentuh. Di papan tik Android semua karakter itu tersembunyi di balik satu
  tombol lagi, dan itu melumpuhkan pengetikan LaTeX.
- **Pelengkapan perintah dan lingkungan.** Ketik `\sec` dan sarannya muncul di
  bawah. Daftarnya dibaca dari berkas CWL (format yang sama dengan TeXstudio),
  hanya untuk paket yang benar-benar dimuat dokumen itu — daftar seluruh TeX
  Live akan mengubur selusin perintah yang penting.
- **`\begin{...}` sekaligus menulis `\end{...}`-nya**, dengan kursor di dalam.
  Lupa `\end` adalah cara paling sering sebuah berkas berhenti terkompilasi.
- **Pelengkapan `\ref` dan `\cite` dari proyek sendiri.** Label dibaca dari
  semua berkas `.tex`, kunci pustaka dari semua `.bib`. Tidak ada yang lupa
  `\section`; semua orang lupa apakah gambarnya `fig:overview` atau
  `fig:overview-2`.
- **Peringatan rujukan ke label yang tidak ada**, dengan nomor barisnya. LaTeX
  tidak gagal karena ini — ia mencetak `??` lalu jalan terus — jadi mudah
  luput sampai pembimbing yang menemukannya.
- **Penyunting tabel visual.** Kisi yang disunting langsung, tambah/hapus baris
  dan kolom, perataan per kolom, jumlah baris judul, dan *Tempel dari
  spreadsheet* (pemisah ditebak sendiri). Hasilnya memakai `booktabs`, dan
  karakter yang merusak tabel di-escape. Tabel adalah bagian LaTeX yang paling
  menyiksa ditulis dengan tangan, terlebih di tablet.
- **Simpan dengan Ctrl+S** di papan tik fisik, atau tombol simpan di bilah
  atas. Titik `•` setelah nama berkas berarti ada perubahan yang belum
  disimpan.

## Kompilasi

- **Dua lintasan: Cepat dan Lengkap.** *Cepat* menjalankan TeX sekali lalu
  langsung membuat PDF — sekitar 7 detik untuk proposal disertasi di tablet.
  *Lengkap* menjalankan BibTeX dan mengulang TeX sampai rujukannya mantap —
  sekitar 14 detik. (Sebelum perbaikan 0.12.2 dan sesudahnya, lintasan cepat
  tidak menghasilkan PDF sama sekali dan lintasan lengkap makan 57 detik.)
  Hampir semua kompilasi hanya untuk melihat satu paragraf
  yang baru diubah, jadi Cepat adalah bawaannya.
- **Tawaran "Jalankan lengkap" muncul sendiri** ketika log TeX memintanya
  (rujukan belum mantap, kutipan belum dikenal, `.bbl` belum ada). Ditawarkan,
  tidak dijalankan sendiri, karena lintasan penuh memakan waktu berlipat.
- **Kompilasi otomatis** dua detik setelah berhenti mengetik, selalu lintasan
  cepat. Bukan per ketikan: satu kompilasi makan beberapa detik dan itu akan
  menjadi antrean yang tidak pernah habis.
- **Kompilasi yang tidak perlu tidak dijalankan.** Kalau tidak ada berkas
  sumber yang berubah sejak kompilasi terakhir, PDF yang ada langsung dipakai.
  TeX tidak mengenal kompilasi bertahap, jadi yang bisa dihemat adalah
  kompilasi yang memang tidak perlu terjadi. *Paksa kompilasi ulang* tersedia
  untuk saat hasilnya dicurigai.
- **Kemajuan yang terlihat bergerak.** Selama kompilasi, bilah atas
  menunjukkan langkah yang sedang dikerjakan dan detik yang berjalan. Spinner
  yang diam selama semenit tidak bisa dibedakan dari aplikasi yang menggantung.
- **Rincian waktu kompilasi** dengan cap waktu tiap langkah, supaya "lama" bisa
  diukur dan dicari sebabnya, bukan hanya dirasakan.
- **Merah hanya untuk galat sungguhan.** `Underfull \hbox` dan sejenisnya
  adalah keluhan penataan huruf; PDF-nya tetap terbit. Mereka ditampilkan
  sebagai peringatan dengan warna netral, supaya galat yang sebenarnya tidak
  tenggelam di antara ratusan baris.
- **Pesan menunjuk berkas dan barisnya**, dalam bentuk `berkas:baris — teks`
  (mis. `bab/02-tinjauan-pustaka.tex:142 — Underfull \hbox …`). Disertasi
  terbagi ke belasan bab; "baris 142" saja tidak berarti apa-apa.
- **Ketuk pesan untuk melompat ke sana.** Berkasnya dibuka dan kursor
  ditaruh di baris itu.
- **Peringatan terlipat jadi satu baris** ("N peringatan — PDF-nya tetap
  terbit") dan baru dibuka lewat *Lihat peringatan*; galat selalu terbuka dan
  merah. Sebuah disertasi bisa punya puluhan peringatan penataan huruf yang
  tidak menggagalkan apa pun.
- **Pesan bisa disalin** sekaligus lewat *Salin semua pesan*. Sebelumnya satu-
  satunya cara memindahkan pesan adalah mengetiknya ulang.
- **Paket TeX ikut di dalam aplikasi** (Android). Kompilasi pertama tidak
  perlu jaringan. Paket yang belum ada di bundel diunduh sekali saat
  dibutuhkan, lalu dipakai bersama semua proyek.
- **Batal.** Kompilasi yang sedang berjalan bisa ditinggalkan supaya ruang
  kerja bisa dipakai lagi. Mesinnya sendiri menyelesaikan pekerjaannya di
  latar; hasilnya diabaikan.
- **Pengawas diam.** Kalau mesin tidak melaporkan apa pun selama tiga menit,
  kompilasi dihentikan dengan penjelasan. Yang dihitung adalah diamnya, bukan
  lamanya: kompilasi pertama sebuah disertasi memang boleh lama.
- **Berkas hasil build di luar folder sumber** (`.writepapertex/build/`), jadi
  repositori tidak dipenuhi `.aux` dan `.log`. PDF-nya disalin ke akar proyek
  supaya ikut ter-push dan bisa dibaca orang yang tidak memasang TeX.

## Pratinjau PDF

- **PDF berdampingan dengan sumbernya** di tablet dan desktop. Pemisah di
  antaranya bisa diseret, dan lebarnya diingat: menulis tabel butuh kode yang
  lebar, memeriksa hasil butuh halaman yang lebar.
- **Halaman tidak terlempar ke awal** setiap kali dikompilasi ulang. Itulah
  yang membuat menulis bertahap bisa ditanggung.
- **Bilah gulir yang bisa diseret**, dengan nomor halamannya. Menggeser empat
  puluh halaman dengan sapuan jari bukan cara membaca hasil kompilasi.
- **PDF yang sudah ada langsung tampil saat proyek dibuka.** Repositori yang
  baru di-clone biasanya sudah membawa PDF-nya; memaksa menunggu satu
  kompilasi sebelum boleh membacanya tidak masuk akal.

## Git dan sinkronisasi

- **Clone sungguhan dari GitHub, GitLab, atau Gitea sendiri**, termasuk
  repositori tertutup dengan token. Riwayatnya ikut, jadi perubahan bisa
  dikirim balik.
- **Arsip sebagai cadangan.** Kalau clone repositori publik gagal, arsip ZIP-nya
  diunduh — dan dikatakan terang-terangan bahwa salinan itu tidak bisa dikirim
  balik.
- **Panel Git**: daftar berkas yang berubah, *Simpan (commit)*, *Tarik*, dan
  *Kirim*, ditambah keterangan berapa commit yang belum dikirim atau menunggu
  ditarik.
- **Folder biasa bisa dijadikan repositori** dari dalam aplikasi, dengan remote
  apa pun. `.gitignore` untuk LaTeX disiapkan sebelumnya — dan PDF sengaja
  tidak diabaikan.
- **Tarik hanya yang maju lurus.** Kalau remote dan tablet sama-sama punya
  perubahan yang bertabrakan, aplikasi menolak menggabungkan dan meminta
  menyelesaikannya di komputer. Menyelesaikan konflik di tablet tanpa alat yang
  layak lebih mungkin merusak tulisan.
- **Pesan galat git yang menyebut sebabnya.** "too many redirects" dari
  libgit2 sebenarnya berarti token ditolak; aplikasi mengatakan itu di kalimat
  pertama, dan pesan aslinya tetap ditampilkan di bawah.
- **HTTPS dengan token, bukan SSH.** Alamat SSH yang ditempel diterjemahkan ke
  HTTPS. Token bisa dicabut satu per satu; kunci privat yang tertinggal di
  tablet tidak.

## Platform

| | Android (tablet, ponsel) | Linux |
|---|---|---|
| Mesin kompilasi | Tectonic, ikut di dalam aplikasi | `latexmk` + XeLaTeX dari TeX Live yang terpasang |
| Paket TeX | bundel di APK, sisanya diunduh sekali | milik TeX Live |
| Git | libgit2 di dalam aplikasi | biner `git` yang terpasang |
| Baris tombol `\ { } $ &` | ada | tidak (papan tik fisik) |
| Tawaran "Jalankan lengkap" | ada | belum |
| Buka folder dari baris perintah | — | `writepapertex ~/tulisan/paper` |

Tata letak mengikuti lebar layar: di atas 1100 dp (tablet mendatar, desktop)
pohon berkas, penyunting, dan PDF tampil sekaligus; di bawahnya pohon berkas
masuk laci. APK hanya untuk `arm64-v8a`.

Kedua mesin berbasis XeTeX, jadi dokumen yang terkompilasi di satu tempat
seharusnya terkompilasi juga di tempat lain.

## Batasan yang diketahui

Diambil dari butir yang belum selesai di [backlog.md](backlog.md):

- **Di layar ponsel (lebar di bawah 600 dp) hanya penyunting yang tampil**;
  pratinjau PDF belum punya tempatnya sendiri di sana. PDF tetap bisa disimpan
  lewat *Simpan PDF…*.
- Penyunting belum menampilkan nomor baris.
- Belum ada cari dan ganti, dan urungkan/ulangi masih yang bawaan kolom teks.
- Belum ada simpan otomatis; berkas tersimpan saat menekan simpan, berpindah
  berkas, mengompilasi, atau membuka panel Git.
- Belum ada SyncTeX dua arah (klik di PDF melompat ke sumbernya).
- Pratinjau belum punya lompat ke halaman dan zoom tersendiri; posisi gulir di
  dalam halaman belum dipertahankan, hanya halamannya.
- Penyunting tabel belum bisa menggabung sel atau menyunting tabel yang sudah
  ada di berkas.
- Kompilasi tidak bisa dihentikan sungguhan di tengah jalan, hanya
  ditinggalkan.
- **Font sistem Android tidak bisa dipanggil lewat nama** (mis.
  `\setmainfont{Roboto}`). Mesin TeX sengaja diarahkan ke folder font milik
  aplikasi: pencarian nama font yang tidak ada — gaya ITB menanyakan
  `Times New Roman` — dulu membuat XeTeX membuka seluruh font sistem satu per
  satu, sekitar 4 detik di setiap lintasan. Pakai font dari bundel (mis. TeX
  Gyre) atau berkas `.otf`/`.ttf` di proyek, keduanya dimuat lewat nama
  berkas, bukan nama keluarga font.
- APK sekitar 89 MB: pustaka mesin sekitar 51 MB (sebagian besar data ICU),
  bundel paket TeX 15 MB, dan runtime C++ 9 MB.
- Belum ada build Windows maupun paket Linux siap pasang (AppImage/deb).
- Antarmuka baru berbahasa Indonesia.
