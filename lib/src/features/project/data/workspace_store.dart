import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/project_profile.dart';

/// Daftar proyek yang dikenal aplikasi, tersimpan di folder aplikasi.
///
/// Dua berkas, bukan satu: `projects.json` berisi keterangan proyeknya dan
/// aman disalin atau diperiksa, sedangkan token akses tinggal di
/// `credentials.json` dengan izin `0600`. Ini mengikuti pemisahan yang sama
/// dengan ReadPaper, dengan alasan yang sama — daftar proyek sering dilihat,
/// token tidak boleh ikut terlihat.
class WorkspaceStore {
  WorkspaceStore({Directory? baseDir}) : _override = baseDir;

  final Directory? _override;

  static const int max = 25;

  Future<Directory> _base() async => _override ?? await getApplicationSupportDirectory();

  Future<File> _projectsFile() async => File(p.join((await _base()).path, 'projects.json'));

  Future<File> _credentialsFile() async => File(p.join((await _base()).path, 'credentials.json'));

  /// Berkas dari versi sebelumnya, yang hanya mencatat path.
  Future<File> _legacyFile() async => File(p.join((await _base()).path, 'recent-projects.json'));

  // ------------------------------------------------------------------ profil

  Future<List<ProjectProfile>> load() async {
    final file = await _projectsFile();
    if (!file.existsSync()) return _migrateLegacy();
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const <ProjectProfile>[];
      final all = <ProjectProfile>[
        for (final entry in raw)
          if (entry is Map) ProjectProfile.fromJson(entry.cast<String, dynamic>()),
      ];
      return <ProjectProfile>[
        for (final profile in all)
          if (profile.directory.isNotEmpty && profile.stillThere) profile,
      ];
    } on FormatException {
      // Berkas rusak tidak layak membuat aplikasi gagal dibuka.
      return const <ProjectProfile>[];
    }
  }

  /// Memindahkan daftar "terakhir dibuka" versi lama menjadi profil.
  ///
  /// Tanpa ini setiap proyek yang pernah dibuka hilang dari layar pembuka saat
  /// aplikasinya diperbarui, dan orang menyangka datanya yang hilang.
  Future<List<ProjectProfile>> _migrateLegacy() async {
    final legacy = await _legacyFile();
    if (!legacy.existsSync()) return const <ProjectProfile>[];
    try {
      final raw = jsonDecode(await legacy.readAsString());
      if (raw is! List) return const <ProjectProfile>[];
      final profiles = <ProjectProfile>[
        for (final entry in raw)
          if (entry is Map && entry['directory'] is String)
            ProjectProfile(
              id: ProjectProfile.idForDirectory(entry['directory'] as String),
              name: p.basename(entry['directory'] as String),
              directory: entry['directory'] as String,
              openedAt: DateTime.tryParse(entry['openedAt'] as String? ?? '') ?? DateTime(1970),
            ),
      ];
      final kept = <ProjectProfile>[
        for (final profile in profiles)
          if (profile.stillThere) profile,
      ];
      await _write(kept);
      await legacy.delete();
      return kept;
    } on Object {
      return const <ProjectProfile>[];
    }
  }

  Future<void> _write(List<ProjectProfile> profiles) async {
    final file = await _projectsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final json = profiles.map((profile) => profile.toJson()).toList();
    await file.writeAsString('${encoder.convert(json)}\n', flush: true);
  }

  /// Mencatat sebuah folder sebagai proyek dan menaruhnya di puncak daftar.
  ///
  /// Folder yang sudah dikenal tidak diduplikasi: keterangannya diperbarui,
  /// dan alamat remote yang sudah tercatat tidak dihapus oleh pemanggilan yang
  /// tidak menyebutkannya.
  Future<ProjectProfile> remember(
    String directory, {
    String? name,
    String? remoteUrl,
    String? branch,
    String? httpsUsername,
  }) async {
    final all = await load();
    final id = ProjectProfile.idForDirectory(directory);
    final existing = all.where((profile) => profile.id == id).firstOrNull;

    // Proyek baru mewarisi identitas dari proyek terakhir yang punya: nama dan
    // surel penulis tidak berganti tiap kali orang memulai paper baru, dan
    // mengetiknya ulang setiap kali adalah cara paling cepat membuat orang
    // membiarkannya kosong.
    final inherited = _identityFrom(all);

    final profile =
        (existing ??
                ProjectProfile.forDirectory(
                  directory,
                  name: name,
                  httpsUsername: inherited?.httpsUsername ?? '',
                  authorName: inherited?.authorName ?? '',
                  authorEmail: inherited?.authorEmail ?? '',
                ))
            .copyWith(
              httpsUsername: (httpsUsername != null && httpsUsername.isNotEmpty)
                  ? httpsUsername
                  : null,
              name: name,
              remoteUrl: (remoteUrl != null && remoteUrl.isNotEmpty) ? remoteUrl : null,
              branch: (branch != null && branch.isNotEmpty) ? branch : null,
              openedAt: DateTime.now(),
            );

    final kept = <ProjectProfile>[
      profile,
      for (final other in all)
        if (other.id != id) other,
    ];
    await _write(kept.length <= max ? kept : kept.sublist(0, max));
    return profile;
  }

  /// Identitas yang dipakai terakhir kali, untuk diwariskan ke proyek baru.
  Future<ProjectProfile?> lastIdentity() async => _identityFrom(await load());

  static ProjectProfile? _identityFrom(List<ProjectProfile> all) =>
      all.firstWhereOrNull((profile) => profile.hasIdentity) ??
      all.firstWhereOrNull((profile) => profile.httpsUsername.isNotEmpty);

  Future<ProjectProfile> update(ProjectProfile profile) async {
    final all = await load();
    await _write(<ProjectProfile>[
      for (final other in all)
        if (other.id == profile.id) profile else other,
    ]);
    return profile;
  }

  /// Melupakan sebuah proyek. Foldernya tidak disentuh.
  Future<List<ProjectProfile>> forget(String id) async {
    final kept = <ProjectProfile>[
      for (final profile in await load())
        if (profile.id != id) profile,
    ];
    await _write(kept);
    await saveToken(id, null);
    return kept;
  }

  // ------------------------------------------------------------------- token

  Future<Map<String, String>> _credentials() async {
    final file = await _credentialsFile();
    if (!file.existsSync()) return <String, String>{};
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return <String, String>{};
      return json.map((key, value) => MapEntry(key.toString(), value.toString()));
    } on FormatException {
      return <String, String>{};
    }
  }

  Future<String?> tokenFor(String id) async {
    final token = (await _credentials())[id];
    return (token == null || token.isEmpty) ? null : token;
  }

  Future<void> saveToken(String id, String? token) async {
    final credentials = await _credentials();
    if (token == null || token.isEmpty) {
      if (!credentials.containsKey(id)) return;
      credentials.remove(id);
    } else {
      credentials[id] = token;
    }
    final file = await _credentialsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString('${jsonEncode(credentials)}\n', flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', file.path]);
    }
  }
}
