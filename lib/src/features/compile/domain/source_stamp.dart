import 'dart:io';

import 'package:path/path.dart' as p;

import 'latex_engine.dart';

/// Menjawab satu pertanyaan: apakah PDF yang sudah ada masih mewakili sumbernya?
///
/// TeX tidak mengenal kompilasi bertahap — sekali dijalankan ia membaca seluruh
/// dokumen dari awal. Di tablet itu berarti satu setengah menit, dan menekan
/// Kompilasi setelah tidak mengubah apa pun membayar penuh untuk hasil yang
/// sudah ada di folder. Yang bisa dihemat bukan kompilasinya, melainkan
/// kompilasi yang memang tidak perlu terjadi.
///
/// Sidik jarinya sengaja murah: nama, ukuran, dan waktu ubah tiap berkas
/// sumber. Membaca isi 2 MB `.tex` beserta gambar-gambarnya hanya untuk
/// memutuskan akan memakan waktu yang justru sedang dihemat.
class SourceStamp {
  const SourceStamp._();

  /// Berkas yang isinya ikut menentukan hasil PDF.
  ///
  /// `.pdf` ikut karena gambar di LaTeX sering berupa PDF — kecuali hasil
  /// kompilasinya sendiri, yang dikecualikan di [collect]; kalau tidak,
  /// sidiknya berubah setiap kali dan tidak akan pernah cocok.
  static const Set<String> watched = <String>{
    '.tex',
    '.bib',
    '.cls',
    '.sty',
    '.bst',
    '.bbx',
    '.cbx',
    '.def',
    '.png',
    '.jpg',
    '.jpeg',
    '.pdf',
    '.eps',
    '.svg',
    '.gif',
    '.tiff',
  };

  /// Folder yang tidak pernah ikut: hasil build dan isi perut git.
  static const Set<String> skipped = <String>{'.git', '.writepapertex'};

  /// Sidik jari dari daftar berkas yang sudah dikumpulkan.
  ///
  /// Terpisah dari [collect] supaya bisa diuji tanpa menyentuh disk.
  static String from(
    Iterable<({String path, int size, int modifiedMs})> files, {
    required String pass,
    required String mainFile,
  }) {
    final rows = files.map((f) => '${f.path}|${f.size}|${f.modifiedMs}').toList(growable: false)
      ..sort();
    return <String>['pass=$pass', 'utama=$mainFile', ...rows].join('\n');
  }

  /// Mengumpulkan berkas sumber di bawah [projectDir].
  ///
  /// [publishedPdf] adalah salinan hasil kompilasi di akar proyek; ia ditulis
  /// oleh kompilasi itu sendiri, jadi ikut menghitungnya berarti sidiknya
  /// sudah basi begitu ia dibuat.
  static List<({String path, int size, int modifiedMs})> collect(
    String projectDir, {
    String? publishedPdf,
  }) {
    final out = <({String path, int size, int modifiedMs})>[];
    final root = Directory(projectDir);
    if (!root.existsSync()) return out;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: projectDir);
      if (p.split(relative).any(skipped.contains)) continue;
      if (!watched.contains(p.extension(relative).toLowerCase())) continue;
      if (publishedPdf != null && p.equals(entity.path, publishedPdf)) continue;
      try {
        final stat = entity.statSync();
        out.add((
          path: relative,
          size: stat.size,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
        ));
      } on FileSystemException {
        // Berkas yang hilang di tengah pemindaian cukup tidak dihitung.
      }
    }
    return out;
  }

  static File _file(String projectDir) => File(p.join(buildDirFor(projectDir), 'sidik-sumber.txt'));

  /// Sidik jari sumber proyek saat ini.
  static String now({
    required String projectDir,
    required String mainFile,
    required CompilePass pass,
  }) => from(
    collect(
      projectDir,
      publishedPdf: p.join(projectDir, '${p.basenameWithoutExtension(mainFile)}.pdf'),
    ),
    pass: pass.name,
    mainFile: mainFile,
  );

  /// PDF hasil kompilasi terakhir kalau sumbernya belum berubah sejak itu,
  /// atau null kalau ada yang berubah — atau PDF-nya sudah tidak ada.
  ///
  /// Lintasan ikut dihitung: hasil lintasan cepat tidak boleh menjawab
  /// permintaan lintasan penuh, karena daftar pustakanya memang belum
  /// dijalankan.
  static String? reusablePdf({
    required String projectDir,
    required String mainFile,
    required CompilePass pass,
  }) {
    final pdf = File(
      p.join(buildDirFor(projectDir), '${p.basenameWithoutExtension(mainFile)}.pdf'),
    );
    if (!pdf.existsSync()) return null;
    final stamp = _file(projectDir);
    if (!stamp.existsSync()) return null;
    try {
      if (stamp.readAsStringSync() != now(projectDir: projectDir, mainFile: mainFile, pass: pass)) {
        return null;
      }
    } on FileSystemException {
      return null;
    }
    return pdf.path;
  }

  /// Mencatat sidik sumber yang baru saja dikompilasi.
  static void remember({
    required String projectDir,
    required String mainFile,
    required CompilePass pass,
  }) {
    try {
      _file(projectDir)
        ..createSync(recursive: true)
        ..writeAsStringSync(now(projectDir: projectDir, mainFile: mainFile, pass: pass));
    } on FileSystemException {
      // Tidak bisa mencatat berarti kompilasi berikutnya berjalan penuh —
      // lebih lambat, tetapi tidak salah.
    }
  }

  /// Menghapus catatannya, supaya kompilasi berikutnya benar-benar berjalan.
  static void forget(String projectDir) {
    try {
      final file = _file(projectDir);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Sudah tidak ada berarti sudah tercapai.
    }
  }

  /// PDF yang sudah ada di proyek, tanpa mempedulikan sidiknya.
  ///
  /// Dipakai saat proyek baru dibuka: sebuah repositori yang baru di-clone
  /// sudah membawa PDF-nya, dan memaksa menunggu satu setengah menit sebelum
  /// boleh membacanya adalah cara tercepat membuat orang menutup aplikasi.
  /// Hasil build didahulukan karena ia yang paling baru; salinan di akar
  /// proyek adalah yang ikut ke repositori.
  static String? existingPdf({required String projectDir, required String mainFile}) {
    final stem = p.basenameWithoutExtension(mainFile);
    for (final candidate in <String>[
      p.join(buildDirFor(projectDir), '$stem.pdf'),
      p.join(projectDir, '$stem.pdf'),
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
