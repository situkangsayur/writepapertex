import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:writepapertex/src/features/compile/domain/latex_engine.dart';
import 'package:writepapertex/src/features/project/domain/latex_project.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wptex_proj_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String relative, String content) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  group('gitignore', () {
    test('proyek baru dapat .gitignore LaTeX', () async {
      final target = Directory(p.join(dir.path, 'baru'));
      await ProjectTemplate.all.first.create(target.path);

      final text = File(p.join(target.path, '.gitignore')).readAsStringSync();
      expect(text, contains('*.aux'));
      expect(text, contains('*.synctex.gz'));
      expect(text, contains('.writepapertex/'));
    });

    test('PDF sengaja tidak diabaikan', () {
      // Yang membaca paper adalah pembimbing tanpa TeX; PDF-nya harus ikut.
      final lines = latexGitignore
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'));
      expect(lines, isNot(contains('*.pdf')));
      expect(lines, isNot(contains('/*.pdf')));
    });
  });

  group('menebak berkas utama', () {
    const proposal = r'''
\documentclass[11pt,a4paper]{report}
\begin{document}
\maketitle
\tableofcontents
\input{bab/01-pendahuluan}
\input{bab/02-tinjauan}
\bibliography{pustaka}
\end{document}
''';
    const gambar = r'''
\documentclass[border=4pt]{standalone}
\begin{document}
\begin{tikzpicture}\end{tikzpicture}
\end{document}
''';

    test('gambar standalone kalah dari dokumen utama', () {
      expect(
        LatexProject.mainFileScore('proposal.tex', proposal),
        greaterThan(LatexProject.mainFileScore('gambar/src/alur-penelitian.tex', gambar)),
      );
    });

    test('berkas tanpa documentclass bukan calon', () {
      expect(LatexProject.mainFileScore('bab/01-pendahuluan.tex', '\\section{Awal}'), 0);
    });

    test('yang di akar menang dari yang dalam, isinya sama', () {
      expect(
        LatexProject.mainFileScore('main.tex', proposal),
        greaterThan(LatexProject.mainFileScore('draf/lama/main.tex', proposal)),
      );
    });
  });

  group('finding the main file', () {
    test('is the one declaring a document class, whatever it is called', () async {
      write('bab1.tex', r'\chapter{Satu}');
      write(
        'skripsi.tex',
        '\\documentclass{report}\n\\begin{document}\\input{bab1}\\end{document}',
      );
      final project = await LatexProject.open(dir.path);
      expect(project.mainFile, 'skripsi.tex');
    });

    test('a chapter included by another is not mistaken for the document', () async {
      write('main.tex', r'\documentclass{article}');
      write('bagian/metode.tex', r'\section{Metode}');
      expect((await LatexProject.open(dir.path)).mainFile, 'main.tex');
    });

    test('with no document class at all, the shallowest .tex is used', () async {
      write('bab/satu.tex', r'\chapter{Satu}');
      write('catatan.tex', r'Tidak ada documentclass.');
      expect((await LatexProject.open(dir.path)).mainFile, 'catatan.tex');
    });

    test('an empty folder still opens', () async {
      final project = await LatexProject.open(dir.path);
      expect(project.files, isEmpty);
      expect(project.mainFile, 'main.tex');
    });
  });

  group('the file list', () {
    test('leaves out build output and hidden folders', () async {
      write('main.tex', r'\documentclass{article}');
      write('ref.bib', '@article{a, title={A}}');
      write('main.aux', 'x');
      write('main.log', 'x');
      write('main.synctex.gz', 'x');
      write('.writepapertex/build/main.pdf', 'x');
      write('.git/config', 'x');

      final project = await LatexProject.open(dir.path);
      expect(project.files, <String>['main.tex', 'ref.bib']);
    });

    test('keeps figures and sub-folders, sorted', () async {
      write('main.tex', r'\documentclass{article}');
      write('gambar/plot.png', 'x');
      write('bagian/metode.tex', r'\section{M}');
      final project = await LatexProject.open(dir.path);
      expect(project.files, <String>['bagian/metode.tex', 'gambar/plot.png', 'main.tex']);
    });
  });

  group('templates', () {
    test('every template compiles as far as having a document body', () {
      for (final template in ProjectTemplate.all) {
        expect(template.source, contains(r'\documentclass'), reason: template.id);
        expect(template.source, contains(r'\begin{document}'), reason: template.id);
        expect(template.source, contains(r'\end{document}'), reason: template.id);
      }
    });

    test('the table template brings booktabs, not bare hlines', () {
      final table = ProjectTemplate.all.firstWhere((t) => t.id == 'table');
      expect(table.source, contains(r'\usepackage{booktabs}'));
      expect(table.source, contains(r'\toprule'));

      // Comments are stripped first: the template explains in a comment why
      // it avoids \hline, and that mention is not a use of it.
      final code = table.source.split('\n').where((l) => !l.trimLeft().startsWith('%')).join('\n');
      expect(code, isNot(contains(r'\hline')));
    });

    test('creating writes main.tex and opens the project', () async {
      final template = ProjectTemplate.all.first;
      final project = await template.create(p.join(dir.path, 'baru'));
      expect(project.files, <String>['main.tex']);
      expect(project.mainFile, 'main.tex');
      expect(File(project.absolute('main.tex')).readAsStringSync(), contains(r'\documentclass'));
    });

    test('refuses to overwrite a folder that already has a main.tex', () async {
      write('main.tex', 'punya orang');
      expect(() => ProjectTemplate.all.first.create(dir.path), throwsA(isA<StateError>()));
      expect(File(p.join(dir.path, 'main.tex')).readAsStringSync(), 'punya orang');
    });
  });
}
