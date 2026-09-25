import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/features/editor/domain/cwl.dart';
import 'package:writepapertex/src/features/editor/domain/latex_language.dart';

void main() {
  const parser = CwlParser();

  Completion one(String line) {
    final parsed = parser.parse(line);
    expect(parsed.length, 1, reason: 'baris "$line" seharusnya menghasilkan satu pelengkapan');
    return parsed.single;
  }

  group('commands', () {
    test('a command with no arguments inserts itself', () {
      final c = one(r'\toprule');
      expect(c.label, r'\toprule');
      expect(c.insert, r'\toprule');
      expect(c.cursorOffset, isNull);
      expect(c.kind, CompletionKind.command);
    });

    test('argument names are dropped and the caret lands in the first group', () {
      final c = one(r'\section{title}');
      expect(c.insert, r'\section{}');
      // Right between the braces.
      expect(c.insert.substring(c.cursorOffset!), '}');
    });

    test('several arguments become several empty groups', () {
      final c = one(r'\multicolumn{cols}{pos}{text}');
      expect(c.insert, r'\multicolumn{}{}{}');
      expect(c.insert.substring(c.cursorOffset!), r'}{}{}');
    });

    test('optional arguments keep their brackets', () {
      final c = one(r'\includegraphics[options]{file}');
      expect(c.insert, r'\includegraphics[]{}');
      expect(c.insert.substring(c.cursorOffset!), r']{}');
    });

    test('nested groups in the argument name do not leak out', () {
      final c = one(r'\cmidrule(trim){a-b}');
      expect(c.insert, r'\cmidrule{}');
    });

    test('a starred command keeps its star', () {
      expect(one(r'\section*{title}').label, r'\section*');
    });

    test("TeXstudio's classification suffix is stripped", () {
      expect(one(r'\alpha#m').label, r'\alpha');
      expect(one(r'\footnote{text}#*').insert, r'\footnote{}');
    });

    test('placeholder marks from the extended format are removed', () {
      expect(one(r'\frac{%<num%>}{%<den%>}').insert, r'\frac{}{}');
    });
  });

  group('environments', () {
    test(r'\begin{...} declares an environment, offered by name', () {
      final c = one(r'\begin{tabularx}{width}{preamble}');
      expect(c.kind, CompletionKind.environment);
      expect(c.label, 'tabularx');
      expect(c.insert, 'tabularx');
    });

    test(r'\end{...} is not a separate completion', () {
      expect(parser.parse('\\begin{quote}\n\\end{quote}').length, 1);
    });
  });

  group('the file as a whole', () {
    const file = '''
# booktabs.cwl
# Comments and directives are skipped.
#include:array
\\toprule
\\midrule
\\bottomrule
\\cmidrule(trim){a-b}

not a command at all
\\toprule
''';

    test('comments, directives and prose are skipped', () {
      final commands = parser.parse(file).map((c) => c.label).toList();
      expect(commands, <String>[r'\toprule', r'\midrule', r'\bottomrule', r'\cmidrule']);
    });

    test('a command repeated in one file is kept once', () {
      expect(parser.parse(file).where((c) => c.label == r'\toprule').length, 1);
    });

    test('includes are reported so dependent files can be loaded too', () {
      expect(parser.includesOf(file), <String>['array']);
    });

    test('the source package is carried into the detail line', () {
      final c = parser.parse(r'\toprule', from: 'booktabs').single;
      expect(c.detail, 'booktabs');
    });

    test('an empty file yields nothing rather than throwing', () {
      expect(parser.parse(''), isEmpty);
      expect(parser.includesOf(''), isEmpty);
    });
  });

  group('scanning a document for its packages', () {
    test('finds every package, including several in one call', () {
      final packages = scanPackages(r'''
\documentclass[11pt]{article}
\usepackage{booktabs}
\usepackage[utf8]{inputenc}
\usepackage{graphicx, amsmath , siunitx}
\RequirePackage{etoolbox}
''');
      expect(
        packages,
        containsAll(<String>['booktabs', 'inputenc', 'graphicx', 'amsmath', 'siunitx', 'etoolbox']),
      );
    });

    test('the document class is reported too, marked as a class', () {
      expect(scanPackages(r'\documentclass{report}'), contains('class-report'));
    });

    test('a document loading nothing yields nothing', () {
      expect(scanPackages('Teks biasa saja.'), isEmpty);
    });

    test('the same package twice is listed once', () {
      final packages = scanPackages('\\usepackage{booktabs}\n\\usepackage{booktabs}');
      expect(packages.where((p) => p == 'booktabs').length, 1);
    });
  });
}
