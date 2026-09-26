/// Merapikan alamat repositori yang ditempel orang.
///
/// Yang ditempel jarang persis seperti yang dimaui git: alamat halaman web,
/// alamat SSH dari tombol "Code" di GitHub, atau alamat dengan spasi ikut
/// terbawa. Semuanya sah sebagai niat, jadi diperbaiki di sini daripada
/// ditolak dengan pesan kesalahan.
String normaliseRemoteUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return url;

  // Alamat SSH: git@github.com:pemilik/nama.git
  //
  // Di Android tidak ada SSH — kunci privat di tablet menimbulkan persoalan
  // yang lebih besar daripada manfaatnya — jadi bentuk itu diterjemahkan ke
  // HTTPS, yang memang cara yang dipakai aplikasi ini.
  final ssh = RegExp(r'^(?:ssh://)?([^@/\s]+)@([^:/\s]+)[:/](.+)$').firstMatch(url);
  if (ssh != null && !url.startsWith('http')) {
    final host = ssh.group(2)!;
    final path = ssh.group(3)!.replaceFirst(RegExp(r'^/+'), '');
    url = 'https://$host/$path';
  }

  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }

  // Halaman web, bukan repositori: .../pemilik/nama/tree/main, /blob/…, /pull/…
  url = url.replaceFirst(RegExp(r'/(tree|blob|pull|issues|commits|releases)(/.*)?$'), '');

  url = url.replaceFirst(RegExp(r'/+$'), '');
  return url;
}

/// Menerjemahkan keluhan git menjadi kalimat yang menyebut sebabnya.
///
/// Pesan asli git dan libgit2 tetap dibawa di bawahnya: itu yang berguna
/// kalau ternyata dugaannya meleset. Yang ditambahkan hanyalah kalimat
/// pertama, yang mengatakan apa yang sebenarnya terjadi.
String explainGitFailure(String output) {
  final text = output.toLowerCase();

  String? reason;
  if (text.contains('too many redirects') || text.contains('authentication replays')) {
    // Kalimat aslinya menyebut "redirects", dan orang lalu memeriksa
    // alamatnya berulang kali — padahal yang ditolak adalah kredensialnya.
    reason =
        'Nama pengguna atau token ditolak server. Yang salah hampir selalu '
        'tokennya: sudah kedaluwarsa, salah tempel, atau tidak punya izin '
        'untuk repositori ini.';
  } else if (text.contains('401') || text.contains('authentication required')) {
    reason = 'Repositori ini meminta kredensial. Isi nama pengguna dan token akses.';
  } else if (text.contains('403')) {
    reason =
        'Tokennya dikenali tetapi tidak berizin untuk repositori ini. '
        'Pada token halus (fine-grained), repositorinya harus dipilih '
        'satu per satu dan izin Contents perlu disetel.';
  } else if (text.contains('404') || text.contains('not found')) {
    reason =
        'Repositorinya tidak ditemukan. Kalau tertutup, tanpa token ia memang '
        'tampak tidak ada — periksa alamat dan tokennya sekaligus.';
  } else if (text.contains('could not resolve') ||
      text.contains('failed to resolve') ||
      text.contains('no address associated')) {
    reason = 'Alamat servernya tidak bisa dicari. Periksa sambungan jaringan.';
  } else if (text.contains('certificate')) {
    reason = 'Sertifikat server tidak bisa diperiksa.';
  } else if (text.contains('ssh') || text.contains('git@')) {
    reason = 'Alamat SSH tidak didukung. Pakai alamat HTTPS dengan token.';
  } else if (text.contains('non-fast-forward') || text.contains('fetch first')) {
    reason = 'Remote punya commit yang belum ada di sini. Tarik dulu, baru kirim.';
  } else if (text.contains('empty') && text.contains('repository')) {
    reason = 'Repositorinya masih kosong.';
  }

  final detail = output.trim();
  if (reason == null) return detail;
  return detail.isEmpty ? reason : '$reason\n\n$detail';
}
