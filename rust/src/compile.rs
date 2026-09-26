//! Menjalankan Tectonic, dan menceritakan apa yang sedang dikerjakannya.
//!
//! Sebelumnya dipakai `tectonic::latex_to_pdf`, satu pemanggilan yang tidak
//! mengeluarkan sepatah kata pun sampai selesai. Untuk dokumen satu halaman
//! itu tidak terasa. Untuk sebuah disertasi — berpuluh berkas, bibliografi,
//! dan paket yang belum ada di cache sehingga harus diunduh satu per satu —
//! hasilnya adalah bilah kemajuan yang diam selama beberapa menit, yang tidak
//! bisa dibedakan dari aplikasi yang menggantung.
//!
//! Jadi sesinya dibangun sendiri, dengan penampung status yang menuliskan
//! setiap langkah ke sebuah berkas. Sisi Dart membaca berkas itu sambil
//! menunggu, dan yang menunggu bisa melihat pekerjaannya bergerak.

use std::fmt::Arguments;
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};

use tectonic::config::PersistentConfig;
use tectonic::driver::{OutputFormat, ProcessingSessionBuilder};
use tectonic::status::{MessageKind, StatusBackend};
// Dua tipe galat yang berbeda hidup berdampingan di sini: penampung status
// memakai `anyhow::Error` milik tectonic_errors, sedangkan API sesi masih
// memakai error_chain. Keduanya disebut dengan nama lengkap supaya tidak
// tertukar.
use tectonic_errors::Error as StatusError;

/// Menuliskan laporan Tectonic ke sebuah berkas, baris demi baris.
struct ProgressStatus {
    file: Option<File>,
}

impl ProgressStatus {
    fn new(path: &Path) -> Self {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        ProgressStatus {
            file: File::create(path).ok(),
        }
    }

    fn line(&mut self, text: &str) {
        let Some(file) = self.file.as_mut() else {
            return;
        };
        // Satu baris satu pesan, dan langsung disiram: yang membacanya sedang
        // menunggu sekarang, bukan nanti setelah semuanya selesai.
        for part in text.lines() {
            let _ = writeln!(file, "{part}");
        }
        let _ = file.flush();
    }
}

impl StatusBackend for ProgressStatus {
    fn report(&mut self, kind: MessageKind, args: Arguments, err: Option<&StatusError>) {
        let prefix = match kind {
            MessageKind::Note => "",
            MessageKind::Warning => "peringatan: ",
            MessageKind::Error => "galat: ",
        };
        let mut text = format!("{prefix}{args}");
        if let Some(e) = err {
            for item in e.chain() {
                text.push_str(&format!("\nsebab: {item}"));
            }
        }
        self.line(&text);
    }

    fn dump_error_logs(&mut self, output: &[u8]) {
        self.line(&String::from_utf8_lossy(output));
    }
}

/// Mengompilasi [tex] menjadi PDF di dalam [out_dir].
///
/// Mengembalikan jalur PDF-nya. Berbeda dari `latex_to_pdf`, berkasnya
/// diberikan lewat jalur — bukan isinya — supaya `\jobname`, `\input` yang
/// relatif, dan berkas bantu seperti `.aux` semuanya bernama seperti yang
/// diharapkan dokumen dan mesin bibliografinya.
pub fn run(tex: &str, out_dir: &str, progress: &str) -> tectonic::errors::Result<PathBuf> {
    let mut status = ProgressStatus::new(Path::new(progress));
    status.line("Menyiapkan sesi…");

    let config = PersistentConfig::open(false)?;
    let bundle = config.default_bundle(false, &mut status)?;
    let format_cache_path = config.format_cache_path()?;

    let tex_path = Path::new(tex);
    let name = tex_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("main.tex");

    let mut builder = ProcessingSessionBuilder::default();
    builder
        .bundle(bundle)
        .primary_input_path(tex_path)
        .tex_input_name(name)
        .format_name("latex")
        .format_cache_path(format_cache_path)
        .output_dir(Path::new(out_dir))
        // Berkas antara disimpan supaya lintasan kedua dan bibtex punya
        // `.aux` untuk dibaca, dan supaya kompilasi berikutnya tidak mulai
        // dari nol.
        .keep_intermediates(true)
        .keep_logs(true)
        .print_stdout(false)
        .output_format(OutputFormat::Pdf);

    status.line("Menjalankan LaTeX…");
    let mut session = builder.create(&mut status)?;
    session.run(&mut status)?;
    status.line("Selesai.");

    let stem = tex_path.file_stem().and_then(|s| s.to_str()).unwrap_or("main");
    Ok(Path::new(out_dir).join(format!("{stem}.pdf")))
}
