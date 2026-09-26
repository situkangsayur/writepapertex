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

cd "$work"
for f in *.tex; do
  echo "--- $f ---"
  TECTONIC_APP_DIR="$cache" "$SRC/target/release/tectonic" -X compile --outdir "$work" "$f"
done

dest="$here/assets/bundle"
mkdir -p "$dest"
( cd "$cache" && zip -qr9 "$dest/tectonic-cache.zip" . )

echo
echo "Bundel siap:"
ls -la "$dest/tectonic-cache.zip"
du -sh "$cache"
