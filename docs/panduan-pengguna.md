# Panduan pengguna WritePaperTeX

Panduan ini untuk yang menulis, bukan yang membangun aplikasinya. Label tombol
dan menu ditulis persis seperti di layar. Daftar fiturnya ada di
[fitur.md](fitur.md); untuk pengembang, [panduan-teknis.md](panduan-teknis.md).

---

## 1. Memasang

**Android.** Pasang APK dari halaman rilis GitHub
(`writepapertex_vX.Y.Z.apk`). APK-nya hanya untuk perangkat 64-bit ARM
(`arm64-v8a`) — hampir semua tablet dan ponsel beberapa tahun terakhir.
Mesin TeX dan paket-paketnya sudah di dalamnya; tidak ada yang perlu dipasang
lagi.

**Linux.** Aplikasinya memakai TeX Live yang sudah terpasang:

```sh
sudo apt install texlive-xetex latexmk git
```

Tanpa TeX Live, ruang kerja menampilkan *"TeX Live tidak ditemukan. Pasang
dengan: sudo apt install texlive-xetex latexmk"* dan tombol Kompilasi mati.

---

## 2. Memulai proyek

Layar pembuka punya tiga bagian: **Lanjutkan** (proyek yang pernah dibuka),
**Buka**, dan **Mulai baru**.

### Membuat proyek baru

Di **Mulai baru**, pilih salah satu templat:

- **Artikel** — satu berkas, siap ditulisi
- **Artikel dengan tabel** — sudah memuat `booktabs` dan satu tabel contoh
- **Laporan / skripsi** — berbab, dengan daftar isi

Isi **Nama folder**, lalu **Buat**. Di Android proyeknya disimpan di folder
milik aplikasi; di sana tidak ada folder lain yang boleh ditulisi aplikasi.

### Membuka yang sudah ada

Di **Buka**:

- **Folder proyek** — berkas utamanya dicari dari `\documentclass`
- **Berkas .tex** — satu berkas, tanpa folder proyek. Di Android berkasnya
  disalin ke folder aplikasi, karena pemilih berkas Android hanya menyerahkan
  salinan sementara.
- **Arsip ZIP** — dibongkar jadi proyek baru
- **Repositori git** — clone dari GitHub, GitLab, atau Gitea sendiri

### Clone dari repositori

Pilih **Repositori git**. Dialog **Buka dari repositori** meminta:

| Kolom | Isinya |
|---|---|
| **Alamat repositori** | mis. `https://github.com/pemilik/nama.git`. Alamat halaman web atau alamat SSH (`git@github.com:…`) juga diterima; aplikasi merapikannya sendiri jadi HTTPS |
| **Cabang (boleh dikosongkan)** | kosong berarti cabang bawaan repositori |
| **Nama pengguna git (boleh dikosongkan)** | GitHub menerima nama apa pun asal tokennya benar; Gitea dan GitLab memeriksanya |
| **Token (untuk repositori tertutup)** | repositori publik tidak perlu token |

Lalu **Salin**. Selama menyalin, layar pembuka menulis apa yang sedang
dikerjakan.

### Token akses

Repositori tertutup butuh token, bukan kata sandi. Di GitHub: *Settings →
Developer settings → Personal access tokens*. Kalau memakai token halus
(*fine-grained*), pilih repositorinya satu per satu dan beri izin
**Contents: Read and write** — tanpa izin tulis, clone berhasil tetapi
**Kirim** ditolak.

Token disimpan per proyek, terpisah dari daftar proyek, di berkas yang hanya
bisa dibaca pemiliknya. Untuk mengganti token belakangan: ketuk nama proyek di
bilah atas, lalu ikon awan (**Alamat git dan token**) di sebelah proyeknya —
atau ikon akun (**Akun dan identitas**) di panel Git.

### Kalau clone gagal

- Repositori **publik** dan clone gagal: aplikasi mencoba mengunduh arsip ZIP-nya.
  Kalau berhasil, muncul keterangan *"Diambil sebagai arsip, bukan clone git —
  riwayatnya tidak ikut dan perubahan tidak bisa dikirim balik."* Proyeknya
  bisa disunting dan dikompilasi, tetapi tidak bisa di-push.
- Token **diisi** dan clone gagal: arsip tidak dicoba (repositori tertutup
  memang tidak punya arsip publik), dan sebabnya ditampilkan langsung.
- *"Folder "nama" sudah ada dan bukan repositori git"* — ada folder dengan nama
  yang sama di folder aplikasi. Kalau folder itu sendiri hasil clone, ia
  langsung dibuka tanpa diunduh ulang.

---

## 3. Mengenal ruang kerja

Bilah atas, dari kiri:

- **Nama proyek** — ketuk untuk berpindah proyek. Di bawahnya: berkas yang
  terbuka (titik `•` berarti belum disimpan), `utama: …`, dan lama kompilasi
  terakhir.
- **Simpan (Ctrl+S)**
- **Warna editor** — palet *Tenang*, *Tegas*, *Kertas*, atau *Tanpa warna*
- **Sisipkan tabel**
- **Kompilasi otomatis** — sakelar; menyala berarti kompilasi cepat berjalan
  sendiri dua detik setelah berhenti mengetik. Mati setiap kali ruang kerja
  dibuka.
- **Simpan dan bagikan** — *Simpan berkas*, *Simpan PDF…*, *Ekspor proyek
  sebagai ZIP*
- **Git**
- **Lihat** — kompilasi cepat untuk melihat hasil
- **Lengkap** — kompilasi dengan daftar pustaka, PDF siap dibagikan
- **Cara kompilasi** (panah kecil) — rincian waktu, paksa kompilasi lengkap,
  dan paket TeX

Di bawahnya: pohon berkas (di layar sempit, masuk laci — geser dari kiri),
penyunting, dan pratinjau PDF. Pemisah antara penyunting dan PDF bisa diseret.

Di layar sentuh, di bawah penyunting ada baris tombol
`\ {} $ & % _ ^ ~ \\ []`. Tombol `{ }` dan `[ ]` menaruh kursor di antara
kurungnya.

---

## 4. Menulis

### Pelengkapan

Saran muncul di bawah penyunting saat mengetik:

- setelah `\` — perintah (`\sec` → `\section`, `\subsection`, …)
- di dalam `\begin{` — nama lingkungan. Memilihnya sekaligus menulis
  `\end{…}`, dengan kursor di dalam.
- di dalam `\ref{`, `\eqref{`, `\autoref{`, `\pageref{` — label dari semua
  berkas `.tex` proyek
- di dalam `\cite{` — kunci dari semua berkas `.bib` proyek

Saran hanya muncul di tempat-tempat itu, tidak saat menulis kalimat biasa.
Perintah dari paket (mis. `\toprule`, `\SI`, `\includegraphics`) baru
ditawarkan setelah paketnya dimuat dengan `\usepackage`.

Label dan kunci pustaka dibaca ulang setiap kali membuka berkas atau selesai
mengompilasi. Label yang baru saja diketik belum ditawarkan sampai salah satu
itu terjadi.

### Rujukan yang menggantung

Kalau berkas yang terbuka memuat `\ref` ke label yang tidak ada di mana pun,
muncul bilah *"Rujukan ke label yang tidak ada: fig:… (baris 42)"*. LaTeX
tidak gagal karena ini; ia hanya mencetak `??` di PDF.

### Menambah berkas

Di kepala pohon berkas, **Tambah berkas**:

- **Buat baru** — *Bab atau bagian (.tex)*, *Daftar pustaka (.bib)*, *Berkas
  gaya (.sty)*, *Kelas dokumen (.cls)*, *Berkas kosong*. Boleh pakai garis
  miring untuk subfolder (`bab/pendahuluan`). Bab langsung di-`\input` dari
  berkas utama, daftar pustaka langsung disebut.
- **Ambil dari perangkat** — *Gambar* (disalin ke folder gambar proyek dan
  disisipkan sebagai `figure` di tempat kursor) atau *Berkas lain*.

Nama berkas dirapikan: spasi jadi `-`, karakter aneh dibuang. Spasi di dalam
`\input{}` dan `\includegraphics{}` adalah sumber galat yang pesannya paling
tidak membantu.

### Berkas utama

Berkas utama ditandai tebal di pohon berkas. Untuk menggantinya, **tekan lama**
berkas `.tex` lain.

### Tabel

**Sisipkan tabel** membuka kisi. Sel disunting langsung; Tab berpindah ke sel
berikutnya. **Tempel dari spreadsheet** mengambil isi papan klip (dari
spreadsheet atau CSV). Atur perataan per kolom, jumlah **Baris judul**, dan
sakelar **booktabs**, lalu **Sisipkan**. Kalau kursor berada setelah
`\end{document}`, tabelnya dipindah ke sebelumnya — LaTeX mengabaikan apa pun
setelah itu.

---

## 5. Mengompilasi

### Cepat atau lengkap

| | **Cepat** | **Lengkap** |
|---|---|---|
| Yang dijalankan | TeX sekali, lalu PDF | BibTeX, lalu TeX diulang sampai rujukannya mantap |
| Tombol | **Lihat** | **Lengkap** |
| Lama (proposal disertasi, tablet) | ±6 detik | ±16 detik |
| PDF-nya | tidak dimampatkan (±10 MB), hanya untuk pratinjau | dimampatkan (±1 MB), siap dikirim |
| Cocok untuk | melihat paragraf yang baru diubah | sebelum PDF dibaca orang lain |
| Kekurangannya | rujukan dan kutipan **baru** bisa tampil `??` | lebih lama |

Masing-masing punya tombolnya sendiri, jadi tidak ada mode yang harus diingat.
Kompilasi otomatis selalu lintasan cepat. Sebelum menyimpan atau membagikan
PDF ke orang lain, tekan **Lengkap**: PDF dari **Lihat** sengaja tidak
dimampatkan supaya lebih cepat, dan ukurannya sekitar sepuluh kali lipat.

Setelah lintasan cepat, kalau TeX sendiri melaporkan ada yang belum mantap,
muncul *"Rujukan atau daftar pustakanya belum mantap."* dengan tombol
**Jalankan lengkap**. Tidak perlu ditekan setiap kali — hanya saat ingin
melihat nomor rujukan dan daftar pustaka yang benar. (Tawaran ini hanya ada
di Android.)

### "Tidak ada yang berubah"

Kalau tidak ada berkas sumber yang berubah sejak kompilasi terakhir dengan
lintasan yang sama, muncul *"Tidak ada yang berubah — PDF terakhir dipakai
lagi."* dan mesinnya tidak dijalankan. Untuk tetap mengompilasi: **Cara
kompilasi → Paksa kompilasi lengkap**.

### Selama kompilasi

Bilah di atas penyunting menunjukkan langkah yang sedang dikerjakan dan waktu
yang berjalan (`0:07`). Urutan yang biasa terlihat di Android:

1. *Menyiapkan paket TeX (sekali saja)…* — hanya pada kompilasi pertama
   setelah memasang atau memperbarui aplikasi
2. *Menjalankan Tectonic…*, *Menyiapkan sesi…*
3. *Menjalankan LaTeX (satu lintasan)…* atau *Menjalankan LaTeX, BibTeX, lalu
   mengulang…*
4. *Selesai.*

**Batal** melepaskan kompilasi dari layar: *"Kompilasi ditinggalkan. Mesinnya
masih menyelesaikan di latar."* Ruang kerja bisa dipakai lagi, tetapi mesinnya
tidak bisa dihentikan di tengah jalan.

**Cara kompilasi → Rincian waktu kompilasi** memperlihatkan cap waktu tiap
langkah kompilasi terakhir, dan bisa disalin.

### Kompilasi pertama dan paket TeX

Di Android, paket TeX yang paling sering dipakai — LaTeX dasar, `amsmath`,
`booktabs`, TikZ, `pgfplots`, `biblatex`, font TeX Gyre, dan lain-lain — ikut
di dalam APK. Pada kompilasi pertama paket itu dibongkar sekali (*Menyiapkan
paket TeX (sekali saja)…*), lalu kompilasi berjalan **tanpa jaringan**.

Kalau dokumen memakai paket yang tidak ada di bundel, mesin mengunduhnya saat
itu juga — perlu jaringan, sekali saja. Paket yang sudah diunduh dipakai
bersama semua proyek. **Cara kompilasi → Unduh paket yang dibutuhkan**
menjalankan satu kompilasi lengkap untuk mengambil semuanya sekaligus; cocok
dilakukan selagi ada Wi-Fi. **Paket yang tersimpan** menunjukkan berapa berkas
dan berapa MB yang sudah ada. Pembaruan aplikasi hanya menambah paket, tidak
pernah menghapus yang sudah tersimpan.

### Font di Android

Font sistem Android (Roboto, Noto, dan seterusnya) **tidak** bisa dipanggil
lewat nama, misalnya `\setmainfont{Roboto}`. Mesin TeX sengaja hanya melihat
folder font milik aplikasi: dulu, satu pertanyaan tentang font yang tidak ada
(gaya ITB menanyakan `Times New Roman`) membuat XeTeX membuka seluruh font
sistem satu per satu, sekitar 4 detik di setiap lintasan.

Yang bisa dipakai — keduanya dimuat lewat **nama berkas**, bukan nama
keluarga font:

- font dari bundel, mis. TeX Gyre Termes sebagai pengganti Times:
  ```latex
  \setmainfont{texgyretermes-regular.otf}[
    BoldFont = texgyretermes-bold.otf,
    ItalicFont = texgyretermes-italic.otf,
    BoldItalicFont = texgyretermes-bolditalic.otf]
  ```
  `\setmainfont{TeX Gyre Termes}` (nama keluarga) **tidak** akan ketemu.
- berkas `.otf`/`.ttf` yang ditaruh di proyek, mis. di folder `fonts/`:
  ```latex
  \setmainfont{NamaFont}[Path=fonts/, Extension=.otf,
    UprightFont=*-Regular, BoldFont=*-Bold]
  ```

Dokumen yang memakai `\IfFontExistsTF` untuk memilih font cadangan tetap
jalan; jawabannya hanya "tidak ada", dan cadangannya yang dipakai.

### Arti pesan kompilasi

Pesan muncul di bilah di atas penyunting:

- **Merah, "N galat"** — kompilasi gagal. Daftarnya selalu terbuka. Tiap
  baris berbentuk `berkas:baris — teks`, mis.
  `bab/03-metode.tex:42 — Undefined control sequence.`
  Perbaiki yang pertama dulu; galat berikutnya sering hanya akibat dari yang
  pertama.
- **Netral, "N peringatan — PDF-nya tetap terbit"** — tidak ada galat.
  Daftarnya terlipat; ketuk **Lihat peringatan** untuk membukanya (dan
  **Lipat peringatan** untuk menutupnya lagi). `Underfull \hbox`,
  `Overfull \hbox`, dan peringatan LaTeX/paket adalah keluhan penataan huruf
  atau rujukan yang belum mantap, mis.
  `bab/02-tinjauan-pustaka.tex:142 — Underfull \hbox (badness 10000) …`.
  PDF-nya sudah jadi; boleh diabaikan sampai tahap merapikan.

**Ketuk sebuah pesan** yang punya nomor baris untuk membuka berkasnya dengan
kursor di baris itu. Kalau berkas yang disebut tidak ada di proyek (misalnya
berkas paket TeX), muncul *"Berkas … tidak ada di proyek ini."* Ikon **Salin
semua pesan** menyalin seluruh daftar.

Kalau kompilasi gagal tanpa pesan LaTeX yang bisa diurai, pesan dari mesinnya
ditampilkan apa adanya, kadang dengan baris `disebabkan: …` yang menjelaskan
sebab di baliknya.

### PDF

Pratinjau tetap di halaman yang sama setelah kompilasi ulang. Bilah gulir di
kanan bisa diseret dan menunjukkan nomor halaman. PDF hasil kompilasi juga
disalin ke akar proyek dengan nama berkas utama (`proposal.tex` →
`proposal.pdf`), supaya ikut terkirim ke git dan bisa dibaca pembimbing tanpa
TeX. **Simpan dan bagikan → Simpan PDF…** menyimpannya ke tempat lain.

---

## 6. Mengirim perubahan lewat git

Ketuk **Git** di bilah atas. Berkas yang terbuka disimpan dulu.

### Sekali saja: identitas

Kalau panel menulis *"Commit atas nama aplikasi — isi nama dan surel lewat
ikon akun."*, ketuk ikon akun (**Akun dan identitas**) dan isi **Nama
penulis** dan **Surel penulis**. Tanpa itu riwayat paper tidak mencatat siapa
menulis apa.

### Alur biasa

1. Panel menunjukkan cabang, alamat remote, commit terakhir, dan *"N berkas
   berubah"* beserta daftarnya.
2. Isi **Pesan commit**, lalu **Simpan (commit)**. Ini menyimpan ke riwayat di
   perangkat; belum ke server.
3. **Kirim** untuk mengirim ke server. Panel menulis *"Terkirim"*.
4. **Tarik** untuk mengambil perubahan dari server (mis. yang ditulis di
   komputer). Berkas yang terbuka dimuat ulang setelahnya.

Keterangan *"N commit belum dikirim"* dan *"N commit menunggu ditarik"*
menunjukkan selisih dengan server.

Kebiasaan yang aman: **Tarik dulu sebelum mulai menulis**, dan **Kirim setelah
selesai**. Aplikasi hanya bisa menarik perubahan yang maju lurus; kalau tablet
dan server sama-sama punya commit baru yang berbeda, muncul *"Ada perubahan
yang bertabrakan. Selesaikan di komputer — menggabungkannya di sini lebih
mungkin merusak daripada menolong."*

### Folder yang belum jadi repositori

Panel menulis *"Folder ini belum berupa repositori git."* Isi **Alamat remote
(boleh dikosongkan)**, lalu **Jadikan repositori**. Cabang awalnya `main`, dan
`.gitignore` untuk LaTeX sudah disiapkan — PDF sengaja tidak diabaikan.
Repositori kosong di GitHub/Gitea harus dibuat dulu lewat situsnya.

---

## 7. Kiat

- Pakai **Lihat** selama menulis. Tekan **Lengkap** sekali sebelum mengirim
  PDF ke orang lain, atau saat tawaran *Jalankan lengkap*
  muncul dan nomor rujukannya sedang dilihat.
- Nyalakan **Kompilasi otomatis** saat merapikan tulisan, matikan saat
  mengetik panjang — tiap jeda dua detik berarti satu kompilasi.
- Tablet dalam posisi mendatar memberi tiga panel sekaligus; posisi tegak
  menyembunyikan pohon berkas di laci.
- Pakai **Unduh paket yang dibutuhkan** sekali selagi ada Wi-Fi untuk proyek
  dengan kelas dokumen kampus atau penerbit.
- Untuk dokumen besar, pecah per bab (`\input{bab/…}`) — lebih mudah
  disunting di layar sentuh.
- **Hapus dari daftar** (ikon ×) di layar pembuka atau pemilih proyek tidak
  menghapus berkasnya.

---

## 8. Masalah yang sering ditemui

**Tombol Kompilasi mati, ada bilah "Mesin Tectonic tidak ikut pada build
ini…"** — APK-nya dibangun tanpa mesin TeX. Pasang APK dari halaman rilis.

**"Pratinjau menunggu mesin kompilasi."** — sama dengan di atas, atau TeX Live
belum terpasang (Linux).

**"Kompilasi gagal. Pesan errornya ada di atas."** — baca bilah merah di atas
penyunting.

**`??` di tempat nomor rujukan atau kutipan** — jalankan **Kompilasi lengkap**.
Kalau tetap `??`, periksa bilah *Rujukan ke label yang tidak ada*, atau
apakah kunci `\cite` ada di berkas `.bib`.

**"Mesin berhenti melapor selama 3 menit, jadi kompilasinya dihentikan…"** —
biasanya mesin sedang mengunduh paket yang tidak ada di bundel dan jaringannya
putus. Sambungkan lagi dan kompilasi ulang; paket yang sudah sempat terunduh
tidak diunduh lagi.

**"mesin berhenti mendadak: …"** — mesin TeX mengalami kegagalan di dalam;
aplikasinya tetap hidup. Salin pesannya, lalu coba **Paksa kompilasi lengkap**.

**"mesin selesai tanpa keluhan, tetapi PDF-nya tidak ada"** — jarang terjadi;
coba **Paksa kompilasi lengkap**.

**Font yang diminta tidak ditemukan (`The font "…" cannot be found`)** — di
Android font sistem tidak dicari lewat nama. Lihat *Font di Android* di atas.

**PDF tidak berubah padahal sudah menyunting** — pastikan berkasnya tersimpan
(tidak ada `•`). Kalau masih, **Paksa kompilasi lengkap**.

**"Belum ada PDF. Tekan Kompilasi dulu."** — *Simpan PDF…* hanya menyimpan
hasil kompilasi di sesi ini.

### Pesan git

| Pesan | Artinya |
|---|---|
| *Nama pengguna atau token ditolak server…* | token kedaluwarsa, salah tempel, atau tanpa izin untuk repositori itu |
| *Repositori ini meminta kredensial. Isi nama pengguna dan token akses.* | repositori tertutup, token belum diisi |
| *Tokennya dikenali tetapi tidak berizin untuk repositori ini…* | token halus tanpa repositori ini atau tanpa izin Contents |
| *Repositorinya tidak ditemukan…* | alamat salah, atau repositori tertutup dan token belum diisi |
| *Alamat servernya tidak bisa dicari. Periksa sambungan jaringan.* | tidak ada jaringan, atau nama server salah |
| *Alamat SSH tidak didukung. Pakai alamat HTTPS dengan token.* | ganti alamat `git@…` dengan `https://…` |
| *Remote punya commit yang belum ada di sini. Tarik dulu, baru kirim.* | tekan **Tarik**, lalu **Kirim** |
| *Ada perubahan yang bertabrakan. Selesaikan di komputer…* | gabungkan di komputer, kirim dari sana, lalu **Tarik** di tablet |
| *Sertifikat server tidak bisa diperiksa.* | perangkat tidak memercayai sertifikat server — misalnya Gitea dengan sertifikat buatan sendiri, atau jam perangkat yang salah |
| *Repositorinya masih kosong.* | repositori di server belum punya commit sama sekali |
| *Tidak ada perubahan untuk disimpan* | tidak ada yang perlu di-commit |
| *Sudah yang terbaru* | tidak ada yang perlu ditarik |
| *git tidak ditemukan di mesin ini…* | Linux: `sudo apt install git` |

Pesan asli git tetap ditampilkan di bawah kalimat penjelasnya, dan bisa
disalin.

**Kirim dan Tarik tidak bisa ditekan** — proyeknya belum punya remote. Isi
alamatnya lewat ikon awan di pemilih proyek, atau lewat **Jadikan repositori**.
