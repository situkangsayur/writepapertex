import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Satu simpul di pohon berkas: folder atau berkas.
@immutable
class FileNode {
  const FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children = const <FileNode>[],
  });

  /// Nama yang ditampilkan — bagian terakhir dari jalurnya saja.
  final String name;

  /// Jalur relatif terhadap folder proyek. Untuk folder, tanpa garis miring
  /// di ujung.
  final String path;
  final bool isDirectory;
  final List<FileNode> children;

  /// Berapa berkas di dalamnya, termasuk yang bersarang.
  int get fileCount => isDirectory ? children.fold(0, (sum, child) => sum + child.fileCount) : 1;
}

/// Menyusun daftar jalur rata menjadi pohon folder.
///
/// Daftar rata cukup untuk proyek satu berkas. Sebuah disertasi punya
/// `bab/`, `gambar/`, `data/`, dan `alat/` dengan berpuluh berkas di
/// dalamnya, dan menggulungnya satu per satu untuk mencari satu bab adalah
/// pekerjaan yang tidak ada gunanya.
///
/// Folder muncul sebelum berkas, dan keduanya urut menurut abjad — urutan
/// yang sama dengan yang dipakai hampir semua penjelajah berkas, jadi tidak
/// perlu dipelajari.
List<FileNode> buildFileTree(Iterable<String> paths) {
  // Simpul sementara yang masih bisa ditumbuhi.
  final root = <String, dynamic>{};

  for (final relative in paths) {
    final parts = p.split(relative).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    var level = root;
    for (var i = 0; i < parts.length; i++) {
      final isLast = i == parts.length - 1;
      if (isLast) {
        level[parts[i]] = relative;
      } else {
        final existing = level[parts[i]];
        if (existing is Map<String, dynamic>) {
          level = existing;
        } else {
          // Sebuah nama tidak bisa menjadi berkas dan folder sekaligus; yang
          // datang belakangan sebagai folder menang, karena isinya nyata.
          final child = <String, dynamic>{};
          level[parts[i]] = child;
          level = child;
        }
      }
    }
  }

  List<FileNode> convert(Map<String, dynamic> level, String prefix) {
    final directories = <FileNode>[];
    final files = <FileNode>[];

    final names = level.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in names) {
      final value = level[name];
      final path = prefix.isEmpty ? name : '$prefix/$name';
      if (value is Map<String, dynamic>) {
        directories.add(
          FileNode(name: name, path: path, isDirectory: true, children: convert(value, path)),
        );
      } else {
        files.add(FileNode(name: name, path: value as String, isDirectory: false));
      }
    }
    return <FileNode>[...directories, ...files];
  }

  return convert(root, '');
}

/// Folder mana saja yang harus terbuka supaya [path] terlihat.
///
/// Dipakai saat sebuah berkas dibuka dari tempat lain — hasil pencarian,
/// pilihan berkas utama, atau tarikan git — supaya pohonnya ikut membuka
/// sendiri alih-alih menyembunyikan berkas yang sedang disunting.
Set<String> ancestorsOf(String path) {
  final parts = p.split(p.dirname(path)).where((s) => s.isNotEmpty && s != '.').toList();
  final out = <String>{};
  var prefix = '';
  for (final part in parts) {
    prefix = prefix.isEmpty ? part : '$prefix/$part';
    out.add(prefix);
  }
  return out;
}
