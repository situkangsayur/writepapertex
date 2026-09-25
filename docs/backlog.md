# WritePaperTeX — Backlog

Status per 2026-09-25. Baru dimulai hari ini. Yang sudah jalan dan teruji
hanyalah mesin kompilasinya; sisanya rencana.

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
- [ ] **Pelengkapan otomatis**: perintah, nama lingkungan, kunci `\ref`/`\cite`
      yang dibaca dari berkas proyek sendiri
- [ ] `\begin{...}` melengkapi `\end{...}` sendiri
- [ ] Nomor baris, dan error ditandai di baris yang bersangkutan
- [ ] Cari dan ganti
- [ ] Urungkan/ulangi yang layak dipakai
- [ ] Papan tik tambahan di layar sentuh untuk `\`, `{`, `}`, `$`, `&` — di
      papan tik Android, karakter-karakter ini semuanya di balik satu tombol
      lagi, dan itu melumpuhkan pengetikan LaTeX

## Fase 3 — Proyek

- [ ] Buat proyek baru dari templat: artikel, laporan, IEEE, skripsi
- [ ] Buka folder yang sudah ada
- [ ] Pohon berkas, dengan berkas hasil build disembunyikan
- [ ] Tentukan berkas utama; deteksi otomatis dari `\documentclass`
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

- [ ] Pratinjau berdampingan dengan editor (`pdfrx`, sama seperti ReadPaper)
- [ ] Posisi gulir dipertahankan saat dikompilasi ulang — tanpa ini, setiap
      kompilasi melempar penulis kembali ke halaman 1
- [ ] Lompat ke halaman, zoom
- [ ] Panel error yang bisa diketuk untuk melompat ke barisnya

## Fase 6 — GitHub

- [ ] Muat proyek dari repositori
- [ ] Commit dan push perubahan
- [ ] Profil repositori, sama seperti ReadPaper
- [ ] Android tidak punya biner git: pakai GitHub REST API, seperti ReadPaper

## Fase 7 — Tablet & desktop

- [ ] Tata letak tablet: pohon berkas · editor · PDF berdampingan
- [ ] Dukungan stylus dan papan tik luar
- [ ] Pintasan papan tik
- [ ] Build Linux (AppImage/deb)
- [ ] Build Windows

---

## Lintas fase

- [x] Lisensi AGPL-3.0-or-later
- [ ] Uji pada perangkat sungguhan (tablet Moto Pad 60 Neo)
- [ ] Publikasi APK ke `http://10.100.21.22:8899`, pola sama dengan ReadPaper
- [ ] Rilis GitHub
- [ ] Dwibahasa (Indonesia/Inggris), sejak awal supaya tidak menumpuk utang
