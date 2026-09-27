#!/usr/bin/env bash
# Menyiapkan cache Tectonic yang sudah terisi, untuk dibundel ke APK.
#
# Tanpa ini, kompilasi pertama mengunduh paket TeX satu per satu. Di tablet itu
# makan menit, bergantung jaringan, dan satu unduhan yang gagal berakhir
# sebagai "failed to open input file hyph-en-us.tex" — pesan yang tidak
# menyebut jaringan sama sekali.
#
# Jalankan setelah scripts/build-tectonic-android.sh, karena skrip ini memakai
# pohon Tectonic yang sudah ditambal olehnya.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$HOME/.cache/writepapertex-android}"
SRC="$WORK/tectonic-src"
[ -d "$SRC" ] || { echo "Jalankan build-tectonic-android.sh dulu"; exit 1; }

# CLI untuk mesin ini, dipakai hanya untuk mengisi cache-nya.
cd "$SRC"
RUSTFLAGS="-A dangerous_implicit_autorefs" cargo build --release --bin tectonic \
  --no-default-features --features "geturl-reqwest,serialization,external-harfbuzz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cache="$tmp/cache"
work="$tmp/work"
mkdir -p "$cache" "$work"

# Templatnya diambil dari kode, bukan disalin, supaya bundelnya persis
# mencakup paket yang benar-benar dipakai.
python3 - "$here" "$work" <<'PY'
import pathlib, re, sys
here, work = sys.argv[1], pathlib.Path(sys.argv[2])
src = (pathlib.Path(here) / 'lib/src/features/project/domain/latex_project.dart').read_text()
blocks = re.findall(r"id: '([a-z]+)',.*?source: r'''(.*?)''',", src, re.S)
assert blocks, 'templat tidak ditemukan'
for name, body in blocks:
    (work / f'{name}.tex').write_text(body)
    print('templat:', name)
PY

# Dokumen "serba ada": memuat paket yang paling sering dipakai paper
# sungguhan — amsmath, booktabs, TikZ, pgfplots, biblatex, dan font TeX Gyre
# lewat fontspec. Templat aplikasi saja tidak cukup: sebuah disertasi
# mengunduh berpuluh paket yang tak satu pun dipakai templat sederhana, dan
# itulah lima menit yang dirasakan pada kompilasi pertama.
cp "$here/scripts/bundle-docs/"*.tex "$work/"

# Proyek sungguhan boleh ikut, supaya paket khas kampus atau penerbitnya —
# kelas dokumen, gaya sitasi, font — ikut terbawa:
#
#   WPTEX_BUNDLE_REPO=https://user:token@github.com/pemilik/nama.git \
#     ./scripts/build-tectonic-bundle.sh
if [ -n "${WPTEX_BUNDLE_REPO:-}" ]; then
  echo "Mengambil proyek contoh…"
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$WPTEX_BUNDLE_REPO" "$work/contoh" >/dev/null 2>&1 \
    || echo "  (gagal, dilewati)"
fi

mkdir -p "$work/out"
cd "$work"
for f in *.tex; do
  echo "--- $f ---"
  # Gagal tidak menghentikan: yang dikumpulkan adalah berkas yang terlanjur
  # diunduh, dan sebagian dokumen contoh memang butuh alat luar seperti biber
  # yang tidak ada di sini.
  TECTONIC_APP_DIR="$cache" "$SRC/target/release/tectonic" \
    -X compile --outdir "$work/out" "$f" 2>&1 | tail -2 || true
done

if [ -d "$work/contoh" ]; then
  main="$(grep -rl '\\documentclass' "$work/contoh" --include='*.tex' | head -1)"
  if [ -n "$main" ]; then
    echo "--- $(basename "$main") (proyek contoh) ---"
    ( cd "$(dirname "$main")" && TECTONIC_APP_DIR="$cache" \
        "$SRC/target/release/tectonic" -X compile --outdir "$work/out" \
        "$(basename "$main")" 2>&1 | tail -2 ) || true
  fi
fi

dest="$here/assets/bundle"
mkdir -p "$dest"
( cd "$cache" && zip -qr9 "$dest/tectonic-cache.zip" . )

echo
echo "Bundel siap:"
ls -la "$dest/tectonic-cache.zip"
du -sh "$cache"
