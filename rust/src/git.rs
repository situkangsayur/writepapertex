//! Operasi git untuk Android, di atas libgit2.
//!
//! Android tidak punya biner `git`, dan menulis protokolnya sendiri berarti
//! menegosiasi kemampuan, membaca dan menulis berkas *pack*, serta menghitung
//! ulang objek — pekerjaan berbulan yang sudah diselesaikan orang lain dengan
//! benar. Jadi libgit2 yang dipakai, di-vendor ke dalam pustaka ini supaya
//! tidak bergantung pada apa pun yang terpasang di perangkat.
//!
//! Semuanya lewat HTTPS dengan token. SSH sengaja tidak didukung: kunci privat
//! di tablet menimbulkan persoalan penyimpanan yang lebih besar daripada
//! manfaatnya, dan token bisa dicabut satu per satu.

use std::ffi::c_char;
use std::path::Path;

use git2::{
    BranchType, Cred, Direction, FetchOptions, PushOptions, RemoteCallbacks, Repository, Signature,
};

use crate::{to_str, write_err};

/// Kredensial: token dipakai sebagai kata sandi, nama pengguna boleh apa saja.
///
/// Itu yang diterima GitHub, GitLab, dan Gitea sama-sama.
/// Menyusun satu berkas sertifikat akar dari milik perangkat, lalu memakainya.
///
/// OpenSSL bisa diberi sebuah *folder* sertifikat, dan itulah yang dicoba
/// lebih dulu — tetapi Android menamai berkas di `cacerts` dengan hash gaya
/// lama, sedangkan OpenSSL modern mencari nama dengan hash yang berbeda.
/// Akibatnya tidak satu pun sertifikat ditemukan dan setiap sambungan HTTPS
/// ditolak dengan "the SSL certificate is invalid".
///
/// Jadi sertifikatnya disalin jadi satu berkas PEM, sekali saja, lalu berkas
/// itu yang ditunjuk. Yang dipakai tetap sertifikat milik perangkat, bukan
/// salinan bawaan aplikasi yang akan basi seiring waktu.
static CA_FILE: std::sync::OnceLock<String> = std::sync::OnceLock::new();

/// Menjalankan [f]; kalau gagal karena sertifikat, memasang bundelnya lagi
/// dan mencoba sekali lagi.
///
/// libgit2 membuat konteks TLS-nya saat sambungan pertama, bukan saat
/// dijalankan. Akibatnya pemasangan sertifikat sebelum itu mendarat di
/// konteks yang belum ada, dan percobaan pertama selalu ditolak. Sesudah
/// percobaan itu konteksnya sudah ada, jadi pemasangan kedua menempel.
fn with_certs<T>(mut f: impl FnMut() -> Result<T, git2::Error>) -> Result<T, git2::Error> {
    match f() {
        Err(e) if e.message().contains("certificate") => {
            let Some(path) = CA_FILE.get() else { return Err(e) };
            unsafe {
                git2::opts::set_ssl_cert_file(path.as_str())?;
            }
            f()
        }
        other => other,
    }
}

pub fn set_ca_bundle(path: &str) -> Result<(), git2::Error> {
    let _ = CA_FILE.set(path.to_string());
    const BEGIN: &str = "-----BEGIN CERTIFICATE-----";
    const END: &str = "-----END CERTIFICATE-----";

    let file = Path::new(path);
    if !file.exists() {
        let mut pem = String::new();
        for dir in [
            "/apex/com.android.conscrypt/cacerts",
            "/system/etc/security/cacerts",
            "/etc/ssl/certs",
        ] {
            let Ok(entries) = std::fs::read_dir(dir) else {
                continue;
            };
            for entry in entries.flatten() {
                let Ok(text) = std::fs::read_to_string(entry.path()) else {
                    continue;
                };
                // Berkas Android memuat satu sertifikat diikuti keterangan
                // yang bisa dibaca manusia; hanya blok PEM-nya yang diambil,
                // karena sisanya membuat pembacaan berurutan berhenti.
                let (Some(from), Some(to)) = (text.find(BEGIN), text.rfind(END)) else {
                    continue;
                };
                pem.push_str(&text[from..to + END.len()]);
                pem.push('\n');
            }
            if !pem.is_empty() {
                break;
            }
        }
        if pem.is_empty() {
            return Err(git2::Error::from_str(
                "tidak ada sertifikat akar yang bisa dibaca di perangkat ini",
            ));
        }
        if let Some(parent) = file.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        std::fs::write(file, pem)
            .map_err(|e| git2::Error::from_str(&format!("gagal menulis {path}: {e}")))?;
    }

    // `SSL_CERT_FILE` dibaca OpenSSL sendiri saat ia menyiapkan jalur
    // verifikasi bawaannya. Ini yang benar-benar bekerja di sini: opsi
    // libgit2 di bawah dipasang pada konteks TLS yang baru dibuat saat
    // sambungan pertama, jadi saat dipanggil sekarang konteksnya belum ada
    // dan OpenSSL menjawab "failed to load certificates".
    std::env::set_var("SSL_CERT_FILE", path);

    // Tetap dicoba: kalau konteksnya kebetulan sudah ada, ini memasangnya
    // langsung. Gagalnya bukan persoalan — jalur di atas sudah cukup.
    unsafe {
        let _ = git2::opts::set_ssl_cert_file(path);
    }
    Ok(())
}

fn callbacks<'a>(token: Option<&'a str>, user: Option<&'a str>) -> RemoteCallbacks<'a> {
    let mut cb = RemoteCallbacks::new();
    cb.credentials(move |_url, from_url, _allowed| match token {
        // Nama pengguna yang dipilih pemakai menang: GitHub menerima apa pun
        // bersama token, tetapi Gitea dan GitLab memeriksanya, jadi menebak
        // sendiri berarti gagal di dua dari tiga tempat.
        Some(t) if !t.is_empty() => Cred::userpass_plaintext(
            user.filter(|u| !u.is_empty())
                .or(from_url)
                .unwrap_or("x-access-token"),
            t,
        ),
        _ => Cred::default(),
    });
    cb
}

fn fetch_options<'a>(token: Option<&'a str>, user: Option<&'a str>) -> FetchOptions<'a> {
    let mut o = FetchOptions::new();
    o.remote_callbacks(callbacks(token, user));
    o
}

/// Menyalin repositori ke [dir].
pub fn clone(
    url: &str,
    dir: &str,
    token: Option<&str>,
    user: Option<&str>,
    branch: Option<&str>,
) -> Result<(), git2::Error> {
    with_certs(|| {
        let mut builder = git2::build::RepoBuilder::new();
        builder.fetch_options(fetch_options(token, user));
        // Cabang yang disebut pengguna dihormati; kalau tidak disebut, yang
        // diambil adalah cabang bawaan remote-nya — bukan dugaan bernama
        // `main`, karena repositori lama sering masih memakai `master`.
        if let Some(branch) = branch {
            builder.branch(branch);
        }
        // Percobaan kedua harus mulai dari folder bersih, atau libgit2
        // menolaknya karena foldernya sudah ada isinya.
        let target = Path::new(dir);
        if target.exists() {
            let _ = std::fs::remove_dir_all(target);
        }
        let repo = builder.clone(url, target)?;
        adopt_remote_branch(&repo, token, user, branch)?;
        Ok(())
    })
}

/// Menyamakan nama cabang dengan yang dipakai remote, pada repositori kosong.
///
/// Meng-clone repositori yang belum punya commit meninggalkan HEAD yang
/// menunjuk ke cabang bawaan libgit2, yaitu `master`. Padahal GitHub, GitLab,
/// dan Gitea membuat repositori baru dengan `main`. Commit pertama dari sini
/// akan mendarat di `master`, push-nya "berhasil", dan orang membuka
/// repositorinya lalu tidak menemukan apa-apa di tempat yang ia lihat.
fn adopt_remote_branch(
    repo: &Repository,
    token: Option<&str>,
    user: Option<&str>,
    branch: Option<&str>,
) -> Result<(), git2::Error> {
    if !repo.is_empty()? {
        return Ok(());
    }

    let wanted = branch.map(str::to_string).or_else(|| {
        let mut remote = repo.find_remote("origin").ok()?;
        remote
            .connect_auth(Direction::Fetch, Some(callbacks(token, user)), None)
            .ok()?;
        let head = remote.default_branch().ok()?;
        head.as_str().map(str::to_string)
    });

    let name = wanted.unwrap_or_else(|| "main".to_string());
    let full = if name.starts_with("refs/") {
        name
    } else {
        format!("refs/heads/{name}")
    };
    repo.set_head(&full)
}

/// Keadaan working tree, sebagai JSON supaya sisi Dart tidak perlu tahu
/// bentuk struktur Rust.
pub fn status(dir: &str) -> Result<String, git2::Error> {
    let repo = Repository::open(dir)?;

    let head = repo.head().ok();
    // Sebelum commit pertama, HEAD menunjuk ke cabang yang belum ada dan
    // `head()` gagal. Namanya tetap harus terbaca: orang perlu tahu ke cabang
    // mana commit pertamanya akan mendarat.
    let branch = match head.as_ref().and_then(|h| h.shorthand()) {
        Some(name) => name.to_string(),
        None => repo
            .find_reference("HEAD")
            .ok()
            .and_then(|r| r.symbolic_target().map(str::to_string))
            .map(|target| {
                let name = target.strip_prefix("refs/heads/").unwrap_or(&target).to_string();
                format!("{name} (belum ada commit)")
            })
            .unwrap_or_else(|| "(tanpa commit)".to_string()),
    };

    let last = head
        .as_ref()
        .and_then(|h| h.peel_to_commit().ok())
        .map(|c| {
            format!(
                "{} {}",
                &c.id().to_string()[..7],
                c.summary().unwrap_or("").replace('"', "'")
            )
        })
        .unwrap_or_default();

    let remote_url = repo
        .find_remote("origin")
        .ok()
        .and_then(|r| r.url().map(|s| s.to_string()))
        .unwrap_or_default();

    // ahead/behind dihitung terhadap cabang pelacak, kalau ada.
    let (mut ahead, mut behind) = (0usize, 0usize);
    if let Ok(local) = repo.find_branch(&branch, BranchType::Local) {
        if let Ok(upstream) = local.upstream() {
            if let (Some(l), Some(u)) = (
                local.get().target(),
                upstream.get().target(),
            ) {
                if let Ok((a, b)) = repo.graph_ahead_behind(l, u) {
                    ahead = a;
                    behind = b;
                }
            }
        }
    }

    let mut options = git2::StatusOptions::new();
    options.include_untracked(true).recurse_untracked_dirs(true);
    let mut changes = Vec::new();
    for entry in repo.statuses(Some(&mut options))?.iter() {
        let path = entry.path().unwrap_or("").replace('"', "'");
        if path.is_empty() {
            continue;
        }
        let s = entry.status();
        let label = if s.is_wt_new() || s.is_index_new() {
            "baru"
        } else if s.is_wt_deleted() || s.is_index_deleted() {
            "dihapus"
        } else if s.is_wt_renamed() || s.is_index_renamed() {
            "dipindah"
        } else {
            "diubah"
        };
        changes.push(format!(r#"{{"path":"{path}","label":"{label}"}}"#));
    }

    Ok(format!(
        r#"{{"branch":"{branch}","remote":"{remote_url}","last":"{last}","ahead":{ahead},"behind":{behind},"changes":[{}]}}"#,
        changes.join(",")
    ))
}

/// Menambahkan semua perubahan lalu membuat commit.
///
/// Mengembalikan false kalau memang tidak ada yang berubah — itu bukan
/// kegagalan, dan memperlakukannya sebagai error hanya membingungkan.
pub fn commit_all(
    dir: &str,
    message: &str,
    name: &str,
    email: &str,
) -> Result<bool, git2::Error> {
    let repo = Repository::open(dir)?;

    let mut index = repo.index()?;
    index.add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)?;
    index.write()?;
    let tree_id = index.write_tree()?;
    let tree = repo.find_tree(tree_id)?;

    let parent = repo.head().ok().and_then(|h| h.peel_to_commit().ok());

    // Pohon yang sama dengan induknya berarti tidak ada yang berubah.
    if let Some(p) = &parent {
        if p.tree_id() == tree_id {
            return Ok(false);
        }
    }

    let who = Signature::now(name, email)?;
    let parents: Vec<&git2::Commit> = parent.iter().collect();
    repo.commit(Some("HEAD"), &who, &who, message, &tree, &parents)?;
    Ok(true)
}

/// Menarik perubahan dari remote, lalu menggabungkannya kalau bisa maju lurus.
///
/// Sengaja hanya fast-forward. Penggabungan yang bertabrakan menuntut
/// penyelesaian konflik, dan menyelesaikannya di tablet tanpa alat yang layak
/// lebih mungkin merusak tulisan daripada menyelamatkannya.
pub fn pull(dir: &str, token: Option<&str>, user: Option<&str>) -> Result<String, git2::Error> {
    let repo = Repository::open(dir)?;
    let mut remote = repo.find_remote("origin")?;

    let head = repo.head()?;
    let branch = head.shorthand().unwrap_or("main").to_string();
    with_certs(|| remote.fetch(&[&branch], Some(&mut fetch_options(token, user)), None))?;

    let fetched = repo.find_reference("FETCH_HEAD")?;
    let target = repo.reference_to_annotated_commit(&fetched)?;
    let (analysis, _) = repo.merge_analysis(&[&target])?;

    if analysis.is_up_to_date() {
        return Ok("Sudah yang terbaru".to_string());
    }
    if !analysis.is_fast_forward() {
        return Ok(
            "Ada perubahan yang bertabrakan. Selesaikan di komputer — \
             menggabungkannya di sini lebih mungkin merusak daripada menolong."
                .to_string(),
        );
    }

    let refname = format!("refs/heads/{branch}");
    let mut reference = repo.find_reference(&refname)?;
    reference.set_target(target.id(), "pull: maju lurus")?;
    repo.set_head(&refname)?;
    repo.checkout_head(Some(git2::build::CheckoutBuilder::default().force()))?;
    Ok("Perubahan ditarik".to_string())
}

/// Mengirim cabang saat ini ke remote.
pub fn push(dir: &str, token: Option<&str>, user: Option<&str>) -> Result<(), git2::Error> {
    let repo = Repository::open(dir)?;
    let mut remote = repo.find_remote("origin")?;
    let head = repo.head()?;
    let branch = head.shorthand().unwrap_or("main").to_string();

    with_certs(|| {
        let mut options = PushOptions::new();
        options.remote_callbacks(callbacks(token, user));
        remote.push(
            &[format!("refs/heads/{branch}:refs/heads/{branch}")],
            Some(&mut options),
        )
    })?;
    Ok(())
}

/// Menjadikan sebuah folder repositori, dengan remote kalau disebutkan.
pub fn init(dir: &str, remote_url: Option<&str>, branch: Option<&str>) -> Result<(), git2::Error> {
    // Cabang awalnya `main`, bukan `master` yang jadi bawaan libgit2. GitHub,
    // GitLab, dan Gitea semuanya membuat repositori baru dengan `main`, dan
    // ketidakcocokan itu berakhir sebagai push yang "berhasil" ke cabang yang
    // tidak pernah dilihat siapa pun.
    let mut options = git2::RepositoryInitOptions::new();
    options.initial_head(branch.unwrap_or("main"));
    let repo = Repository::init_opts(dir, &options)?;
    if let Some(url) = remote_url {
        if !url.is_empty() {
            if repo.find_remote("origin").is_ok() {
                repo.remote_set_url("origin", url)?;
            } else {
                repo.remote("origin", url)?;
            }
        }
    }
    Ok(())
}

/// Menjalankan [f] dan menulis pesan kesalahannya ke [err_buf].
pub fn guard<T>(
    f: impl FnOnce() -> Result<T, git2::Error>,
    err_buf: *mut c_char,
    err_len: usize,
) -> Option<T> {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(Ok(value)) => Some(value),
        Ok(Err(e)) => {
            write_err(e.message(), err_buf, err_len);
            None
        }
        Err(_) => {
            write_err("git berhenti mendadak", err_buf, err_len);
            None
        }
    }
}

/// Membaca penunjuk teks yang boleh kosong.
pub fn opt_str<'a>(p: *const c_char) -> Option<&'a str> {
    to_str(p).filter(|s| !s.is_empty())
}
