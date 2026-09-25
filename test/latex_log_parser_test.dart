import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:writepapertex/src/features/compile/domain/latex_engine.dart';

void main() {
  const parser = LatexLogParser();

  test('reads file:line: errors, keeping the line number', () {
    final messages = parser.parse('./main.tex:12: Undefined control sequence.');
    expect(messages.length, 1);
    expect(messages.first.severity, LatexSeverity.error);
    expect(messages.first.line, 12);
    expect(messages.first.file, './main.tex');
    expect(messages.first.text, 'Undefined control sequence.');
  });

  test('reads bang errors, which carry no line number', () {
    final messages = parser.parse("! LaTeX Error: File `foo.sty' not found.");
    expect(messages.single.severity, LatexSeverity.error);
    expect(messages.single.line, isNull);
    expect(messages.single.text, contains('not found'));
  });

  test('reads warnings and digs the line out of the prose', () {
    final messages = parser.parse(
      "LaTeX Warning: Reference `fig:1' on page 1 undefined on input line 42.",
    );
    expect(messages.single.severity, LatexSeverity.warning);
    expect(messages.single.line, 42);
  });

  test('a message appearing in both logs is reported once', () {
    // latexmk echoes the engine output, and the .log is read as well, so the
    // same line arrives twice. Showing it twice looks like two problems.
    final messages = parser.parse('''
./main.tex:4: Undefined control sequence.
some other output
./main.tex:4: Undefined control sequence.
''');
    expect(messages.length, 1);
  });

  test('the same text on different lines stays two messages', () {
    final messages = parser.parse('''
./main.tex:4: Undefined control sequence.
./main.tex:9: Undefined control sequence.
''');
    expect(messages.length, 2);
    expect(messages.map((m) => m.line), <int>[4, 9]);
  });

  test('errors are separated from warnings', () {
    final messages = parser.parse('''
./main.tex:4: Undefined control sequence.
LaTeX Warning: Citation `x' undefined on input line 7.
''');
    expect(messages.length, 2);
    final result = CompileResult(ok: false, log: '', messages: messages);
    expect(result.errors.length, 1);
    expect(result.errors.single.line, 4);
  });

  test('an empty or wordless log yields nothing', () {
    expect(parser.parse(''), isEmpty);
    expect(parser.parse('\n\n   \n'), isEmpty);
  });

  test('handles the lone carriage returns old distributions emit', () {
    final messages = parser.parse('./a.tex:1: A.\r./b.tex:2: B.\r\n./c.tex:3: C.');
    expect(messages.map((m) => m.line), <int>[1, 2, 3]);
  });

  _buildDirTests();

  group('generated files', () {
    test('build leftovers are recognised', () {
      for (final name in <String>[
        'main.aux',
        'main.log',
        'main.out',
        'main.toc',
        'main.fls',
        'main.fdb_latexmk',
        'main.synctex.gz',
        'refs.bbl',
        'refs.blg',
      ]) {
        expect(isGeneratedFile(name), isTrue, reason: name);
      }
    });

    test('things people wrote are not', () {
      for (final name in <String>['main.tex', 'refs.bib', 'gambar/plot.png', 'README.md']) {
        expect(isGeneratedFile(name), isFalse, reason: name);
      }
    });
  });
}

void _buildDirTests() {
  group('build directory', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('wptex_build_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('ignores itself, so git never reports the build output', () async {
      await ensureBuildDir(dir.path);
      final ignore = File(p.join(dir.path, '.writepapertex', '.gitignore'));
      expect(ignore.existsSync(), isTrue);
      expect(ignore.readAsStringSync(), contains('*'));
    });

    test('the build folder is inside the marker folder, not the project root', () async {
      final build = await ensureBuildDir(dir.path);
      expect(p.isWithin(p.join(dir.path, '.writepapertex'), build), isTrue);
      expect(Directory(dir.path).listSync().length, 1);
    });

    test('running twice does not overwrite an edited .gitignore', () async {
      await ensureBuildDir(dir.path);
      final ignore = File(p.join(dir.path, '.writepapertex', '.gitignore'));
      ignore.writeAsStringSync('punya orang');
      await ensureBuildDir(dir.path);
      expect(ignore.readAsStringSync(), 'punya orang');
    });
  });
}
