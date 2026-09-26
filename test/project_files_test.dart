import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/features/project/domain/project_files.dart';

void main() {
  group('sanitiseFileName', () {
    test('mengganti spasi dan memaksa akhiran', () {
      expect(sanitiseFileName('Bab Satu', extension: 'tex'), 'Bab-Satu.tex');
    });

    test('tidak menumpuk akhiran yang sudah benar', () {
      expect(sanitiseFileName('pustaka.bib', extension: 'bib'), 'pustaka.bib');
    });

    test('subfolder tetap boleh', () {
      expect(sanitiseFileName('bab/pendahuluan', extension: 'tex'), 'bab/pendahuluan.tex');
    });

    test('menolak naik ke atas folder proyek', () {
      expect(sanitiseFileName('../../etc/passwd'), 'etc/passwd');
    });

    test('nama yang habis dirapikan tetap punya nama', () {
      expect(sanitiseFileName('!!!', extension: 'tex'), 'berkas.tex');
    });
  });

  group('titik sisip', () {
    const document = r'''
\documentclass{article}
\usepackage{graphicx}
\usepackage{booktabs}

\begin{document}
Isi.
\end{document}
''';

    test('preamble mendarat sesudah usepackage terakhir', () {
      final after = insertOnce(document, r'\usepackage{amsmath}', preamble: true);
      final lines = after.split('\n');
      expect(lines[3], r'\usepackage{amsmath}');
    });

    test('badan mendarat sebelum end document', () {
      final after = insertOnce(document, r'\input{bab/pendahuluan}', preamble: false);
      final lines = after.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines[lines.length - 2], r'\input{bab/pendahuluan}');
      expect(lines.last, r'\end{document}');
    });

    test('baris yang sama tidak disisipkan dua kali', () {
      final once = insertOnce(document, r'\usepackage{booktabs}', preamble: true);
      expect(once, document);
    });

    test('dokumen tanpa usepackage tetap dapat preamble sebelum begin', () {
      const bare = '\\documentclass{article}\n\\begin{document}\n\\end{document}\n';
      final after = insertOnce(bare, r'\usepackage{graphicx}', preamble: true);
      expect(after, contains('\\usepackage{graphicx}\n\\begin{document}'));
    });
  });

  group('menyambungkan berkas', () {
    test('bab dipanggil dengan input tanpa akhiran', () {
      expect(
        bodyLineFor(NewFileKind.chapter, 'bab/metode.tex', usesBiblatex: false),
        r'\input{bab/metode}',
      );
    });

    test('gaya dipanggil dengan usepackage', () {
      expect(
        preambleLineFor(NewFileKind.style, 'gaya-saya.sty', usesBiblatex: false),
        r'\usepackage{gaya-saya}',
      );
    });

    test('bibtex lama memakai bibliography, biblatex memakai addbibresource', () {
      expect(
        bodyLineFor(NewFileKind.bibliography, 'pustaka.bib', usesBiblatex: false),
        contains(r'\bibliography{pustaka}'),
      );
      expect(
        preambleLineFor(NewFileKind.bibliography, 'pustaka.bib', usesBiblatex: false),
        isNull,
      );
      expect(
        preambleLineFor(NewFileKind.bibliography, 'pustaka.bib', usesBiblatex: true),
        r'\addbibresource{pustaka.bib}',
      );
      expect(
        bodyLineFor(NewFileKind.bibliography, 'pustaka.bib', usesBiblatex: true),
        r'\printbibliography',
      );
    });

    test('kelas dokumen tidak disambungkan sendiri', () {
      expect(bodyLineFor(NewFileKind.documentClass, 'tazkia.cls', usesBiblatex: false), isNull);
      expect(preambleLineFor(NewFileKind.documentClass, 'tazkia.cls', usesBiblatex: false), isNull);
    });

    test('biblatex dikenali dari opsinya juga', () {
      expect(usesBiblatex(r'\usepackage[backend=biber]{biblatex}'), isTrue);
      expect(usesBiblatex(r'\usepackage{natbib}'), isFalse);
    });
  });

  group('berkas dari perangkat', () {
    test('akhiran menentukan jenisnya', () {
      expect(kindForExtension('pustaka.bib'), NewFileKind.bibliography);
      expect(kindForExtension('GAYA.STY'), NewFileKind.style);
      expect(kindForExtension('data.csv'), isNull);
    });

    test('gambar dikenali tanpa peduli huruf besar kecil', () {
      expect(isGraphic('gambar/Foto.JPG'), isTrue);
      expect(isGraphic('catatan.txt'), isFalse);
    });

    test('folder yang sudah ada dipakai lagi', () {
      expect(
        preferredAssetDir(<String>['main.tex', 'figures/alur.pdf'], graphic: true),
        'figures',
      );
      expect(preferredAssetDir(<String>['main.tex'], graphic: true), 'gambar');
      expect(preferredAssetDir(<String>['main.tex'], graphic: false), 'data');
    });

    test('figure memuat includegraphics, caption, dan label', () {
      final snippet = figureSnippet('gambar/alur-kerja.png');
      expect(snippet, contains(r'\includegraphics[width=0.8\linewidth]{gambar/alur-kerja.png}'));
      expect(snippet, contains(r'\caption{Alur Kerja}'));
      expect(snippet, contains(r'\label{fig:alur-kerja}'));
    });
  });

  group('isi awal', () {
    test('bab memuat section dan label', () {
      final text = starterContent(NewFileKind.chapter, 'bab/pendahuluan.tex');
      expect(text, contains(r'\section{Pendahuluan}'));
      expect(text, contains(r'\label{sec:pendahuluan}'));
    });

    test('sty menyebut namanya sendiri', () {
      expect(
        starterContent(NewFileKind.style, 'gaya-saya.sty'),
        contains(r'\ProvidesPackage{gaya-saya}'),
      );
    });

    test('berkas kosong memang kosong', () {
      expect(starterContent(NewFileKind.plain, 'catatan.txt'), isEmpty);
    });
  });
}
