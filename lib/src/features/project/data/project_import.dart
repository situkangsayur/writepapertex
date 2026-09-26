import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/latex_project.dart';

/// Membawa proyek dari luar ke dalam aplikasi: berkas ZIP, atau repositori git.
///
/// Android tidak bisa bekerja langsung di folder mana pun yang dipilih
/// pengguna — sistemnya menyerahkan salinan, bukan foldernya. Jadi apa pun
/// asalnya, proyeknya diletakkan di folder milik aplikasi dan dikerjakan di
/// sana.
class ProjectImport {
  const ProjectImport();

  /// Membongkar [zipBytes] menjadi proyek bernama [name] di bawah [baseDir].
  Future<LatexProject> fromZip({
    required List<int> zipBytes,
    required String baseDir,
    required String name,
  }) async {
    final target = Directory(p.join(baseDir, _safeName(name)));
    if (target.existsSync() && target.listSync().isNotEmpty) {
      throw StateError('Folder "${p.basename(target.path)}" sudah ada dan tidak kosong');
    }
    await target.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(zipBytes);

    // Arsip dari GitHub, GitLab dan Gitea semuanya membungkus isinya dalam
    // satu folder bernama repo-cabang. Kalau itu dipertahankan, setiap proyek
    // punya satu lapis folder kosong yang tidak berarti apa-apa.
    final prefix = _commonPrefix(archive);

    for (final entry in archive) {
      final relative = prefix.isEmpty ? entry.name : entry.name.substring(prefix.length);
      if (relative.isEmpty) continue;

      // Nama di dalam arsip tidak tepercaya: satu entri "../../.." sudah cukup
      // untuk menulis ke luar folder proyek.
      final resolved = p.normalize(p.join(target.path, relative));
      if (!p.isWithin(target.path, resolved)) continue;

      if (entry.isFile) {
        final file = File(resolved);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.readBytes() ?? const <int>[]);
      } else {
        await Directory(resolved).create(recursive: true);
      }
    }

    return LatexProject.open(target.path);
  }

  /// Mengunduh sebuah repositori sebagai arsip, lalu membongkarnya.
  ///
  /// Ini HTTP biasa, bukan git. Android tidak punya biner git, dan protokol
  /// git-nya belum diterapkan — tapi hampir semua penyelenggara menyediakan
  /// arsip ZIP, jadi membaca repositori orang sudah bisa sekarang.
  ///
  /// Yang belum bisa: mengirim balik. Itu tetap menunggu git.
  Future<LatexProject> fromRepository({
    required String repoUrl,
    required String baseDir,
    String? branch,
    void Function(String message)? onProgress,
  }) async {
    final candidates = archiveUrlsFor(repoUrl, branch: branch);
    if (candidates.isEmpty) {
      throw StateError('Alamat repositori tidak dikenali: $repoUrl');
    }

    for (final url in candidates) {
      onProgress?.call('Mengunduh $url…');
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) continue;
        return await fromZip(
          zipBytes: response.bodyBytes,
          baseDir: baseDir,
          name: _repoName(repoUrl),
        );
      } on http.ClientException {
        continue;
      }
    }
    throw StateError(
      'Arsip tidak bisa diunduh. Pastikan repositorinya publik dan '
      'nama cabangnya benar.',
    );
  }

  /// Alamat arsip yang dicoba, berurutan.
  ///
  /// Bentuknya berbeda per penyelenggara, dan nama cabang bawaan bisa `main`
  /// atau `master`, jadi keduanya dicoba kalau tidak disebutkan.
  static List<String> archiveUrlsFor(String repoUrl, {String? branch}) {
    final cleaned = repoUrl.trim().replaceAll(RegExp(r'\.git/?$'), '');
    if (cleaned.isEmpty) return const <String>[];

    // git@host:pemilik/nama  ->  https://host/pemilik/nama
    final ssh = RegExp(r'^(?:ssh://)?git@([^:/]+)[:/](.+)$').firstMatch(cleaned);
    final https = ssh != null
        ? 'https://${ssh.group(1)}/${ssh.group(2)}'
        : (cleaned.startsWith('http') ? cleaned : 'https://$cleaned');

    final uri = Uri.tryParse(https);
    if (uri == null || uri.pathSegments.length < 2) return const <String>[];
    final owner = uri.pathSegments[0];
    final name = uri.pathSegments[1];
    final base = '${uri.scheme}://${uri.authority}/$owner/$name';
    final branches = branch == null || branch.isEmpty
        ? <String>['main', 'master']
        : <String>[branch];

    return <String>[
      for (final b in branches) ...<String>[
        // GitHub dan Gitea memakai bentuk ini; GitLab memakai yang di bawahnya.
        '$base/archive/refs/heads/$b.zip',
        '$base/archive/$b.zip',
        '$base/-/archive/$b/$name-$b.zip',
      ],
    ];
  }

  /// Awalan folder yang dimiliki semua entri, kalau ada.
  static String _commonPrefix(Archive archive) {
    final names = archive.map((e) => e.name).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return '';
    final first = names.first.split('/').first;
    if (first.isEmpty) return '';
    final all = names.every((n) => n == first || n.startsWith('$first/'));
    return all ? '$first/' : '';
  }

  static String _repoName(String repoUrl) {
    final cleaned = repoUrl.trim().replaceAll(RegExp(r'\.git/?$'), '');
    final parts = cleaned.split(RegExp(r'[/:]')).where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? 'proyek' : _safeName(parts.last);
  }

  /// Nama folder yang aman di semua sistem berkas.
  static String _safeName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[^\w.-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'proyek' : cleaned;
  }
}
