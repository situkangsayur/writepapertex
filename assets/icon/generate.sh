#!/usr/bin/env bash
# Renders the Android launcher icons from the SVGs next to this script.
#
# Needs rsvg-convert (librsvg2-bin) and convert (imagemagick):
#   sudo apt install librsvg2-bin imagemagick
#
# Run from anywhere:  assets/icon/generate.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
res="$here/../../android/app/src/main/res"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# density : legacy icon px : adaptive layer px (108dp)
densities="mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432"

for entry in $densities; do
  dpi="${entry%%:*}"; rest="${entry#*:}"
  legacy="${rest%%:*}"; adaptive="${rest#*:}"
  dir="$res/mipmap-$dpi"
  mkdir -p "$dir"

  # Adaptive layers, used from Android 8 on.
  rsvg-convert -w "$adaptive" -h "$adaptive" "$here/foreground.svg" \
    -o "$dir/ic_launcher_foreground.png"
  rsvg-convert -w "$adaptive" -h "$adaptive" "$here/monochrome.svg" \
    -o "$dir/ic_launcher_monochrome.png"

  # Legacy icon: older launchers do not mask, so bake in a rounded square.
  rsvg-convert -w "$adaptive" -h "$adaptive" "$here/background.svg" -o "$work/bg.png"
  rsvg-convert -w "$adaptive" -h "$adaptive" "$here/foreground.svg" -o "$work/fg.png"
  radius=$((adaptive * 22 / 100))
  convert "$work/bg.png" "$work/fg.png" -composite \
    \( +clone -alpha transparent -fill white \
       -draw "roundrectangle 0,0 $((adaptive - 1)),$((adaptive - 1)) $radius,$radius" \) \
    -compose DstIn -composite \
    -resize "${legacy}x${legacy}" "$dir/ic_launcher.png"

  echo "mipmap-$dpi: ic_launcher ${legacy}px, layers ${adaptive}px"
done

echo "Selesai. Jalankan 'flutter build apk' untuk memakai ikon baru."
