//! Menjembatani Tectonic ke Dart lewat antarmuka C yang sesempit mungkin.
//!
//! Sengaja bukan `flutter_rust_bridge`: yang dibutuhkan hanya satu fungsi —
//! "kompilasi berkas ini, tulis PDF-nya ke sini, dan kalau gagal katakan
//! kenapa". Codegen sebesar itu untuk satu fungsi hanya menambah bagian yang
//! bisa rusak.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::path::Path;

/// Menyalin [text] ke [buf], selalu diakhiri NUL.
fn write_err(text: &str, buf: *mut c_char, len: usize) {
    if buf.is_null() || len == 0 {
        return;
    }
    // Dipotong di batas karakter, bukan byte, supaya UTF-8-nya tidak rusak.
    let mut cut = text.len().min(len - 1);
    while cut > 0 && !text.is_char_boundary(cut) {
        cut -= 1;
    }
    let owned = CString::new(&text[..cut]).unwrap_or_default();
    let bytes = owned.as_bytes_with_nul();
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, buf, bytes.len().min(len));
    }
}

fn to_str<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

/// Mengompilasi `tex_path` menjadi PDF di `out_path`.
///
/// Mengembalikan 0 kalau berhasil. Selain itu, `err_buf` berisi penjelasannya.
///
/// # Safety
/// Semua penunjuk harus berupa string C yang sah, dan `err_buf` harus menunjuk
/// ke setidaknya `err_len` bita yang boleh ditulisi.
#[no_mangle]
pub unsafe extern "C" fn wptex_compile(
    tex_path: *const c_char,
    out_path: *const c_char,
    cache_dir: *const c_char,
    err_buf: *mut c_char,
    err_len: usize,
) -> c_int {
    let (Some(tex), Some(out)) = (to_str(tex_path), to_str(out_path)) else {
        write_err("jalur berkas tidak sah", err_buf, err_len);
        return 2;
    };

    // Tectonic menyimpan paket TeX yang diunduhnya di sini. Di Android itu
    // harus folder milik aplikasi; tidak ada HOME yang bisa ditulisi.
    if let Some(cache) = to_str(cache_dir) {
        // TECTONIC_APP_DIR dibaca oleh tambalan pada tectonic_io_base. Tanpa
        // itu, app_dirs2 menanya konteks Java dan panik di Android.
        std::env::set_var("TECTONIC_APP_DIR", cache);
        std::env::set_var("TECTONIC_CACHE_DIR", cache);
    }

    let source = match std::fs::read_to_string(tex) {
        Ok(s) => s,
        Err(e) => {
            write_err(&format!("tidak bisa membaca {tex}: {e}"), err_buf, err_len);
            return 3;
        }
    };

    // Dijalankan dengan direktori kerja di sebelah berkasnya, supaya
    // \input dan \includegraphics yang relatif tetap ketemu.
    if let Some(dir) = Path::new(tex).parent() {
        let _ = std::env::set_current_dir(dir);
    }

    // Tectonic bisa panic — berkas bundel rusak, jaringan mati di tengah,
    // atau asersi di dalam mesin XeTeX. Tanpa penangkap ini, panic itu
    // mematikan seluruh aplikasi; di perangkat hasilnya SIGABRT dan layar
    // kembali ke peluncur tanpa penjelasan apa pun.
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        tectonic::latex_to_pdf(&source)
    }));

    let result = match outcome {
        Ok(r) => r,
        Err(payload) => {
            let what = payload
                .downcast_ref::<&str>()
                .map(|s| (*s).to_string())
                .or_else(|| payload.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "sebab tidak diketahui".to_string());
            write_err(&format!("mesin berhenti mendadak: {what}"), err_buf, err_len);
            return 5;
        }
    };

    match result {
        Ok(pdf) => match std::fs::write(out, &pdf) {
            Ok(()) => 0,
            Err(e) => {
                write_err(&format!("tidak bisa menulis {out}: {e}"), err_buf, err_len);
                4
            }
        },
        Err(e) => {
            // Rantai sebabnya ikut ditulis: pesan teratas Tectonic sering
            // hanya "engine failed", dan yang menjelaskan ada di bawahnya.
            let mut text = format!("{e}");
            let mut source = std::error::Error::source(&e);
            while let Some(inner) = source {
                text.push_str(&format!("\n  disebabkan: {inner}"));
                source = inner.source();
            }
            write_err(&text, err_buf, err_len);
            1
        }
    }
}

/// Versi mesin, supaya aplikasinya bisa menunjukkan apa yang sedang dipakai.
#[no_mangle]
pub extern "C" fn wptex_version() -> *const c_char {
    concat!("tectonic ", env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}
