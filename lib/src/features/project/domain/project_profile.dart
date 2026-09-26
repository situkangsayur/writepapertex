import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Satu proyek yang dikenal aplikasi, beserta repositori tempatnya tinggal.
///
/// Berpindah proyek berarti berpindah profil: tiap profil memegang foldernya
/// sendiri, jadi proyek yang sudah ada di perangkat tidak pernah disalin ulang.
/// Tokennya sengaja bukan bagian dari kelas ini — lihat `WorkspaceStore`.
@immutable
class ProjectProfile {
  const ProjectProfile({
    required this.id,
    required this.name,
    required this.directory,
    this.remoteUrl = '',
    this.branch = '',
    this.httpsUsername = '',
    this.authorName = '',
    this.authorEmail = '',
    this.mainFile = '',
    required this.openedAt,
  });

  factory ProjectProfile.fromJson(Map<String, dynamic> json) => ProjectProfile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    directory: json['directory'] as String? ?? '',
    remoteUrl: json['remoteUrl'] as String? ?? '',
    branch: json['branch'] as String? ?? '',
    httpsUsername: json['httpsUsername'] as String? ?? '',
    authorName: json['authorName'] as String? ?? '',
    authorEmail: json['authorEmail'] as String? ?? '',
    mainFile: json['mainFile'] as String? ?? '',
    openedAt: DateTime.tryParse(json['openedAt'] as String? ?? '') ?? DateTime(1970),
  );

  /// Profil baru untuk sebuah folder.
  ///
  /// Idnya diturunkan dari path, bukan diacak, supaya membuka folder yang sama
  /// dua kali lewat jalan berbeda — pemilih folder dan clone, misalnya —
  /// tetap satu proyek.
  factory ProjectProfile.forDirectory(
    String directory, {
    String? name,
    String remoteUrl = '',
    String branch = '',
    String httpsUsername = '',
    String authorName = '',
    String authorEmail = '',
  }) => ProjectProfile(
    id: idForDirectory(directory),
    name: (name == null || name.isEmpty) ? p.basename(directory) : name,
    directory: directory,
    remoteUrl: remoteUrl,
    branch: branch,
    httpsUsername: httpsUsername,
    authorName: authorName,
    authorEmail: authorEmail,
    openedAt: DateTime.now(),
  );

  final String id;
  final String name;

  /// Path mutlak folder proyeknya.
  final String directory;

  /// Alamat remote yang diingat untuk proyek ini.
  ///
  /// Disimpan terpisah dari `.git/config` supaya proyek yang belum jadi
  /// repositori pun bisa mengingat ke mana kelak akan dikirim.
  final String remoteUrl;

  /// Cabang yang dipakai; kosong berarti apa pun bawaan repositorinya.
  final String branch;

  /// Nama pengguna untuk HTTPS.
  ///
  /// GitHub menerima apa pun asal tokennya benar, tetapi Gitea dan GitLab
  /// memeriksanya, jadi menebak sendiri berarti gagal di sebagian tempat.
  /// Kosong berarti `x-access-token`, nama yang dipakai GitHub sendiri.
  final String httpsUsername;

  /// Nama dan surel yang tercantum pada commit.
  ///
  /// Tanpa ini semua commit ditandatangani atas nama aplikasi, dan riwayat
  /// sebuah paper kehilangan satu-satunya keterangan tentang siapa menulis apa.
  final String authorName;
  final String authorEmail;

  /// Berkas yang dikompilasi, kalau pengguna memilihnya sendiri.
  ///
  /// Kosong berarti biarkan proyeknya menebak. Tebakan itu bagus tapi tidak
  /// sempurna — sebuah tesis berisi belasan gambar `standalone` yang juga
  /// punya `\documentclass` — dan orang yang tahu jawabannya harus bisa
  /// mengatakannya sekali lalu tidak ditanya lagi.
  final String mainFile;
  final DateTime openedAt;

  /// Nama pengguna yang benar-benar dikirim ke server.
  String get effectiveUsername => httpsUsername.isEmpty ? 'x-access-token' : httpsUsername;

  /// True kalau identitas penulisnya sudah lengkap.
  bool get hasIdentity => authorName.isNotEmpty && authorEmail.isNotEmpty;

  bool get hasRemote => remoteUrl.isNotEmpty;

  /// Folder yang sudah dihapus tidak layak ditawarkan lagi.
  bool get stillThere => Directory(directory).existsSync();

  /// Alamat yang enak dibaca di daftar: `github.com/pemilik/nama`.
  String get remoteLabel {
    if (remoteUrl.isEmpty) return '';
    final ssh = RegExp(r'^[^@]+@([^:]+):(.+?)(?:\.git)?$').firstMatch(remoteUrl);
    if (ssh != null) return '${ssh.group(1)}/${ssh.group(2)}';
    final uri = Uri.tryParse(remoteUrl);
    if (uri == null || uri.host.isEmpty) return remoteUrl;
    final path = uri.path.replaceAll(RegExp(r'\.git$'), '');
    return '${uri.host}$path';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'directory': directory,
    'remoteUrl': remoteUrl,
    'branch': branch,
    'httpsUsername': httpsUsername,
    'authorName': authorName,
    'authorEmail': authorEmail,
    'mainFile': mainFile,
    'openedAt': openedAt.toIso8601String(),
  };

  ProjectProfile copyWith({
    String? name,
    String? directory,
    String? remoteUrl,
    String? branch,
    String? httpsUsername,
    String? authorName,
    String? authorEmail,
    String? mainFile,
    DateTime? openedAt,
  }) => ProjectProfile(
    id: id,
    name: name ?? this.name,
    directory: directory ?? this.directory,
    remoteUrl: remoteUrl ?? this.remoteUrl,
    branch: branch ?? this.branch,
    httpsUsername: httpsUsername ?? this.httpsUsername,
    authorName: authorName ?? this.authorName,
    authorEmail: authorEmail ?? this.authorEmail,
    mainFile: mainFile ?? this.mainFile,
    openedAt: openedAt ?? this.openedAt,
  );

  /// Id yang selalu sama untuk folder yang sama.
  static String idForDirectory(String directory) {
    final normalised = p.normalize(directory);
    // Path apa pun harus jadi nama berkas yang sah, dan cukup bisa dibaca
    // manusia supaya berkas kredensialnya masih masuk akal saat diperiksa.
    return normalised.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'^_+'), '');
  }
}
