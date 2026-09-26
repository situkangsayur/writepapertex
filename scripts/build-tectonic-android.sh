#!/usr/bin/env bash
# Membangun Tectonic (mesin TeX berbasis Rust) untuk aarch64-linux-android.
#
# Ini palang pintu terbesar proyek ini: Android tidak punya TeX Live, dan
# Tectonic bukan Rust murni — ia membungkus XeTeX dan menuntut tujuh pustaka C
# dari platform target. Skrip ini menyiapkan semuanya.
#
# Yang dibutuhkan lebih dulu:
#   rustup target add aarch64-linux-android
#   cargo install cargo-ndk
#   sudo apt install autoconf autoconf-archive automake libtool
#   Android NDK (dipakai versi 28.2)
#
# Hasilnya: libtectonic.rlib dan sekitar 170 objek AArch64 di
# $WORK/tectonic-src/target/aarch64-linux-android/release/
set -euo pipefail

WORK="${WORK:-$HOME/.cache/writepapertex-android}"
NDK="${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/28.2.13676358}"
TAG="${TECTONIC_TAG:-tectonic@0.15.0}"
TRIPLET=arm64-android

[ -d "$NDK" ] || { echo "NDK tidak ada di $NDK"; exit 1; }
mkdir -p "$WORK"

# --- 1. vcpkg: tujuh pustaka C untuk Android ------------------------------
#
# Tectonic mendukung vcpkg sebagai sumber dependensi lewat TECTONIC_DEP_BACKEND.
# Itu jauh lebih mudah daripada menyiapkan sysroot pkg-config sendiri — dan
# merupakan satu-satunya alasan seluruh pekerjaan ini selesai dalam hitungan
# menit alih-alih berhari-hari.
if [ ! -x "$WORK/vcpkg/vcpkg" ]; then
  git clone --depth 1 https://github.com/microsoft/vcpkg.git "$WORK/vcpkg"
  "$WORK/vcpkg/bootstrap-vcpkg.sh" -disableMetrics
fi

# fontconfig dipasang belakangan: ia butuh gperf, yang butuh autotools dari
# sistem. Kalau autotools belum ada, paket lain tetap terbangun dan hanya
# langkah ini yang gagal — pesannya jelas.
ANDROID_NDK_HOME="$NDK" VCPKG_DISABLE_METRICS=1 "$WORK/vcpkg/vcpkg" install \
  --triplet "$TRIPLET" \
  zlib libpng freetype graphite2 icu "harfbuzz[core,freetype,graphite2,icu]" fontconfig

# --- 2. Sumber Tectonic pada tag rilisnya ---------------------------------
#
# Dibangun dari repositorinya, bukan dari crates.io, karena repo membawa
# Cargo.lock yang cocok. Menarik `tectonic` sebagai dependensi biasa membuat
# cargo memilih versi sub-crate terbaru yang sudah tidak sejalan, dan itu
# berakhir jadi tarik-menarik versi tanpa ujung.
if [ ! -d "$WORK/tectonic-src" ]; then
  git clone --depth 1 --branch "$TAG" \
    https://github.com/tectonic-typesetting/tectonic.git "$WORK/tectonic-src"
fi
cd "$WORK/tectonic-src"

# --- 3. Dua tambalan untuk perkakas masa kini ------------------------------
#
# (a) Header ICU 78 menuntut C++17; Tectonic 0.15 masih menulis -std=c++14.
sed -i 's/"-std=c++14"/"-std=c++17"/' crates/engine_xetex/build.rs crates/xetex_layout/build.rs

# (b) Crate `time` yang terkunci tidak lagi terkompilasi dengan rustc baru.
cargo update -p time >/dev/null

# --- 4. Bangun ------------------------------------------------------------
#
# external-harfbuzz: pakai harfbuzz dari vcpkg, bukan submodule yang tidak
# ikut ter-clone pada --depth 1.
# -A dangerous_implicit_autorefs: lint yang kini berstatus galat dan mengenai
# kode bibtex lama; tidak ada hubungannya dengan Android.
export ANDROID_NDK_HOME="$NDK"
export VCPKG_ROOT="$WORK/vcpkg"
export TECTONIC_DEP_BACKEND=vcpkg
export VCPKGRS_TRIPLET="$TRIPLET"
export RUSTFLAGS="-A dangerous_implicit_autorefs"

cargo ndk -t arm64-v8a build --release --lib \
  --no-default-features --features external-harfbuzz

out="$WORK/tectonic-src/target/aarch64-linux-android/release"
echo
echo "Selesai."
ls -la "$out/libtectonic.rlib"
echo "Objek C/C++ AArch64: $(find "$out/build" -name '*.o' | wc -l)"
