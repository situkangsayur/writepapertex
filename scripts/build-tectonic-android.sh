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

# (c) app_dirs2 menanyakan folder data aplikasi kepada konteks Java, dan tanpa
#     konteks itu ia panik dengan "android context was not initialized" yang
#     mematikan seluruh proses. Aplikasi pemanggil sudah tahu foldernya
#     sendiri, jadi dibuat bisa memberitahukannya lewat TECTONIC_APP_DIR.
python3 - <<'PATCH'
import pathlib
p = pathlib.Path('crates/io_base/src/app_dirs.rs')
s = p.read_text()
if 'forced_root' in s:
    raise SystemExit(0)
helper = '''
/// Akar yang dipaksakan lewat `TECTONIC_APP_DIR`, kalau disetel.
///
/// Ditambahkan untuk Android: di sana `app_dirs2` menanyakan folder data
/// aplikasi kepada konteks Java, dan tanpa konteks itu ia panik.
fn forced_root(sub: &str) -> Option<PathBuf> {
    let base = std::env::var_os("TECTONIC_APP_DIR")?;
    let mut path = PathBuf::from(base);
    if !sub.is_empty() {
        for part in sub.split('/') {
            if !part.is_empty() {
                path.push(part);
            }
        }
    }
    let _ = std::fs::create_dir_all(&path);
    Some(path)
}
'''
s = s.replace('pub fn get_user_config() -> Result<PathBuf> {\n    Ok(',
              helper + '\npub fn get_user_config() -> Result<PathBuf> {\n'
              '    if let Some(p) = forced_root("config") {\n        return Ok(p);\n    }\n    Ok(')
s = s.replace('pub fn ensure_user_config() -> Result<PathBuf> {\n    Ok(',
              'pub fn ensure_user_config() -> Result<PathBuf> {\n'
              '    if let Some(p) = forced_root("config") {\n        return Ok(p);\n    }\n    Ok(')
s = s.replace('pub fn ensure_user_cache_dir(path: &str) -> Result<PathBuf> {\n    Ok(',
              'pub fn ensure_user_cache_dir(path: &str) -> Result<PathBuf> {\n'
              '    if let Some(p) = forced_root(path) {\n        return Ok(p);\n    }\n    Ok(')
p.write_text(s)
PATCH

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

# --- 5. Bungkus jadi pustaka yang bisa dipanggil Dart ----------------------
#
# Crate jembatan disalin ke dalam pohon Tectonic supaya dependensi path-nya
# selalu menunjuk ke pohon yang sudah ditambal.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rm -rf "$WORK/tectonic-src/wptex_engine"
cp -r "$here/rust" "$WORK/tectonic-src/wptex_engine"

# --- 5a. OpenSSL yang bisa membaca berkas ---------------------------------
#
# `openssl-src` membangun OpenSSL untuk Android dengan `no-stdio`, dan itu
# mematikan seluruh pemuatan sertifikat dari berkas: `SSL_CTX_load_verify_
# locations` menjawab "BIO lib" apa pun berkas yang diberikan, dan setiap
# clone HTTPS berakhir dengan "the SSL certificate is invalid". Komentar di
# dalam crate itu sendiri mengakui hal ini ("most other platforms need it for
# things like loading system certificates").
#
# Alasan aslinya adalah kegagalan build pada NDK lama; NDK yang dipakai di
# sini punya stdio yang lengkap. Jadi barisnya dibuang, pada salinan — bukan
# pada isi ~/.cargo/registry, yang diperiksa checksum-nya oleh cargo.
srcdir="$(ls -d "$HOME"/.cargo/registry/src/*/openssl-src-* 2>/dev/null | sort | tail -1)"
if [ -n "$srcdir" ]; then
  patched="$WORK/openssl-src-stdio"
  if [ ! -d "$patched" ]; then
    echo "Menambal openssl-src: membuang no-stdio..."
    cp -r "$srcdir" "$patched"
    chmod -R u+w "$patched"
    sed -i 's/^\( *\)configure.arg("no-stdio");/\1let _ = "no-stdio dibuang: sertifikat harus bisa dibaca dari berkas";/' \
      "$patched/src/lib.rs"
    grep -q 'no-stdio dibuang' "$patched/src/lib.rs" || { echo "Tambalan openssl-src gagal"; exit 1; }
  fi
  cat >> "$WORK/tectonic-src/wptex_engine/Cargo.toml" <<EOF

[patch.crates-io]
openssl-src = { path = "$patched" }
EOF
fi

cd "$WORK/tectonic-src/wptex_engine"
cargo ndk -t arm64-v8a build --release

lib="$WORK/tectonic-src/wptex_engine/target/aarch64-linux-android/release/libwptex_engine.so"
dest="$here/android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$dest"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-all -o "$dest/libwptex_engine.so" "$lib"

# Runtime C++ milik NDK ikut disertakan: pustaka Rust ini menautnya secara
# dinamis, dan tanpa berkas ini dlopen gagal dengan "library not found" yang
# tidak menyebut nama yang kurang.
cp "$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$dest/"

echo
echo "Pustaka mesin terpasang:"
ls -la "$dest/"
