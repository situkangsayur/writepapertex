import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:writepapertex/src/features/compile/data/latexmk_engine.dart';
import 'package:writepapertex/src/features/compile/domain/latex_engine.dart';

/// These run against the TeX Live on this machine. Without one they skip
/// rather than fail: a missing TeX Live is a fact about the machine, not a
/// bug in the engine wrapper.
void main() {
  const engine = LatexmkEngine();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('wptex_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<CompileResult> compileSource(String source, {String name = 'main.tex'}) async {
    File(p.join(dir.path, name)).writeAsStringSync(source);
    return engine.compile(projectDir: dir.path, mainFile: name);
  }

  test('a document that is correct produces a PDF', () async {
    if (!await engine.isAvailable()) {
      markTestSkipped('TeX Live tidak terpasang di mesin ini');
      return;
    }
    final result = await compileSource(r'''
\documentclass{article}
\begin{document}
Halo dari WritePaperTeX.
\end{document}
''');
    expect(result.ok, isTrue, reason: result.log.split('\n').take(40).join('\n'));
    expect(result.pdfPath, isNotNull);
    expect(File(result.pdfPath!).lengthSync(), greaterThan(500));
    expect(result.errors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('build output stays out of the project directory', () async {
    if (!await engine.isAvailable()) {
      markTestSkipped('TeX Live tidak terpasang di mesin ini');
      return;
    }
    await compileSource(r'''
\documentclass{article}
\begin{document}A\end{document}
''');
    // Only the source the author wrote should be sitting in the project root;
    // a project cloned from GitHub must not fill up with .aux and .log.
    final stray = Directory(dir.path)
        .listSync()
        .map((e) => p.basename(e.path))
        .where((n) => n != 'main.tex' && n != '.writepapertex')
        .toList();
    expect(stray, isEmpty, reason: 'berkas nyasar: $stray');
    expect(Directory(buildDirFor(dir.path)).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a broken document fails and says which line', () async {
    if (!await engine.isAvailable()) {
      markTestSkipped('TeX Live tidak terpasang di mesin ini');
      return;
    }
    final result = await compileSource(r'''
\documentclass{article}
\begin{document}
Baris ini benar.
\tidakAdaPerintahIni
\end{document}
''');
    expect(result.ok, isFalse);
    expect(result.errors, isNotEmpty);
    final undefined = result.errors.where((e) => e.text.contains('Undefined control sequence'));
    expect(undefined, isNotEmpty, reason: result.errors.join('\n'));
    expect(undefined.first.line, 4, reason: 'nomor baris harus menunjuk ke perintah yang salah');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('reports plainly when there is no TeX Live to run', () async {
    const missing = LatexmkEngine(executable: 'latexmk-yang-tidak-ada');
    expect(await missing.isAvailable(), isFalse);
    final result = await missing.compile(projectDir: dir.path, mainFile: 'main.tex');
    expect(result.ok, isFalse);
    expect(result.log, contains('TeX Live tidak ditemukan'));
  });
}
