import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Sebuah proyek yang pernah dibuka.
@immutable
class RecentProject {
  const RecentProject({required this.directory, required this.openedAt});

  final String directory;
  final DateTime openedAt;

  String get name => p.basename(directory);

  /// Folder yang sudah dihapus tidak layak ditawarkan lagi.
  bool get stillThere => Directory(directory).existsSync();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'directory': directory,
    'openedAt': openedAt.toIso8601String(),
  };

  static RecentProject? fromJson(Map<String, dynamic> json) {
    final dir = json['directory'] as String?;
    if (dir == null || dir.isEmpty) return null;
    return RecentProject(
      directory: dir,
      openedAt: DateTime.tryParse(json['openedAt'] as String? ?? '') ?? DateTime(1970),
    );
  }
}

/// Daftar proyek yang pernah dibuka, tersimpan di folder aplikasi.
class RecentProjects {
  const RecentProjects();

  static const int max = 15;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'recent-projects.json'));
  }

  Future<List<RecentProject>> load() async {
    final file = await _file();
    if (!file.existsSync()) return const <RecentProject>[];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const <RecentProject>[];
      return <RecentProject>[
        for (final entry in raw)
          if (entry is Map)
            if (RecentProject.fromJson(entry.cast<String, dynamic>()) case final r?)
              if (r.stillThere) r,
      ];
    } catch (_) {
      // Berkas rusak tidak layak membuat aplikasi gagal dibuka.
      return const <RecentProject>[];
    }
  }

  Future<List<RecentProject>> remember(String directory) async {
    final entry = RecentProject(directory: directory, openedAt: DateTime.now());
    final kept = <RecentProject>[
      entry,
      for (final r in await load())
        if (r.directory != directory) r,
    ];
    final capped = kept.length <= max ? kept : kept.sublist(0, max);
    await (await _file()).writeAsString(jsonEncode(capped.map((r) => r.toJson()).toList()));
    return capped;
  }

  Future<List<RecentProject>> forget(String directory) async {
    final kept = <RecentProject>[
      for (final r in await load())
        if (r.directory != directory) r,
    ];
    await (await _file()).writeAsString(jsonEncode(kept.map((r) => r.toJson()).toList()));
    return kept;
  }
}
