import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:writepapertex/src/features/compile/domain/latex_engine.dart';
import 'package:writepapertex/src/features/compile/domain/source_stamp.dart';

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('wptex-stamp');
    File(p.join(project.path, 'main.tex')).writeAsStringSync('\\documentclass{article}');
  });

  tearDown(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  void compiled({CompilePass pass = CompilePass.quick}) {
    final pdf = File(p.join(buildDirFor(project.path), 'main.pdf'))..createSync(recursive: true);
    pdf.writeAsStringSync('%PDF-1.4');
    SourceStamp.remember(projectDir: project.path, mainFile: 'main.tex', pass: pass);
  }

  String? reuse({CompilePass pass = CompilePass.quick}) =>
      SourceStamp.reusablePdf(projectDir: project.path, mainFile: 'main.tex', pass: pass);

  test('tanpa kompilasi sebelumnya tidak ada yang bisa dipakai lagi', () {
    expect(reuse(), isNull);
  });

  test('sumber yang tidak berubah boleh memakai PDF terakhir', () {
    compiled();
    expect(reuse(), isNotNull);
  });

  test('mengubah sumber membatalkan pemakaian ulang', () {
    compiled();
    final tex = File(p.join(project.path, 'main.tex'));
    tex.writeAsStringSync('\\documentclass{article}\\begin{document}halo\\end{document}');
    expect(reuse(), isNull);
  });

  test('menambah berkas sumber baru membatalkan pemakaian ulang', () {
    compiled();
    File(p.join(project.path, 'bab1.tex')).writeAsStringSync('halo');
    expect(reuse(), isNull);
  });

  test('menghapus berkas sumber membatalkan pemakaian ulang', () {
    File(p.join(project.path, 'bab1.tex')).writeAsStringSync('halo');
    compiled();
    File(p.join(project.path, 'bab1.tex')).deleteSync();
    expect(reuse(), isNull);
  });

  test('hasil lintasan cepat tidak menjawab permintaan lintasan penuh', () {
    compiled();
    expect(reuse(pass: CompilePass.full), isNull);
    expect(reuse(), isNotNull);
  });

  test('PDF hasil kompilasi yang terbit di akar proyek tidak membatalkan sidiknya', () {
    compiled();
    // Inilah yang disalin `_publishPdf` setelah kompilasi berhasil.
    File(p.join(project.path, 'main.pdf')).writeAsStringSync('%PDF-1.4');
    expect(reuse(), isNotNull);
  });

  test('gambar PDF yang berubah tetap membatalkan sidiknya', () {
    File(p.join(project.path, 'gambar', 'grafik.pdf'))
      ..createSync(recursive: true)
      ..writeAsStringSync('satu');
    compiled();
    File(p.join(project.path, 'gambar', 'grafik.pdf')).writeAsStringSync('dua berbeda');
    expect(reuse(), isNull);
  });

  test('berkas hasil build dan isi git tidak ikut dihitung', () {
    compiled();
    File(p.join(project.path, '.git', 'objects', 'aa', 'bb.pdf'))
      ..createSync(recursive: true)
      ..writeAsStringSync('objek git');
    File(p.join(buildDirFor(project.path), 'main.log')).writeAsStringSync('log');
    expect(reuse(), isNotNull);
  });

  test('PDF yang hilang membatalkan pemakaian ulang walau sidiknya cocok', () {
    compiled();
    File(p.join(buildDirFor(project.path), 'main.pdf')).deleteSync();
    expect(reuse(), isNull);
  });

  test('melupakan sidiknya memaksa kompilasi berikutnya berjalan', () {
    compiled();
    SourceStamp.forget(project.path);
    expect(reuse(), isNull);
  });

  test('PDF yang sudah ada ditemukan saat proyek dibuka', () {
    expect(SourceStamp.existingPdf(projectDir: project.path, mainFile: 'main.tex'), isNull);

    // Repositori yang baru di-clone membawa PDF di akar proyeknya.
    final published = File(p.join(project.path, 'main.pdf'))..writeAsStringSync('%PDF-1.4');
    expect(SourceStamp.existingPdf(projectDir: project.path, mainFile: 'main.tex'), published.path);

    // Hasil build lebih baru, jadi ia yang didahulukan.
    final built = File(p.join(buildDirFor(project.path), 'main.pdf'))..createSync(recursive: true);
    built.writeAsStringSync('%PDF-1.4');
    expect(SourceStamp.existingPdf(projectDir: project.path, mainFile: 'main.tex'), built.path);
  });

  test('sidiknya tidak bergantung pada urutan pemindaian', () {
    const files = <({String path, int size, int modifiedMs})>[
      (path: 'a.tex', size: 1, modifiedMs: 10),
      (path: 'b.tex', size: 2, modifiedMs: 20),
    ];
    final forward = SourceStamp.from(files, pass: 'quick', mainFile: 'a.tex');
    final backward = SourceStamp.from(files.reversed, pass: 'quick', mainFile: 'a.tex');
    expect(forward, backward);
  });
}
