import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/features/editor/domain/latex_syntax.dart';
import 'package:writepapertex/src/features/project/domain/file_tree.dart';

void main() {
  /// Jenis potongan yang menutupi [needle] pada [source].
  SyntaxKind kindOf(String source, String needle) {
    final at = source.indexOf(needle);
    expect(at, isNonNegative, reason: 'tidak ada "$needle" di dalam contohnya');
    final token = tokenizeLatex(source).firstWhere((t) => t.start <= at && at < t.end);
    return token.kind;
  }

  group('pewarnaan LaTeX', () {
    test('potongannya menutupi seluruh teks tanpa celah', () {
      const source = '% halo\n\\section{Judul}\nIsi \$x^2\$ dan \\ref{sec:a}.\n';
      final tokens = tokenizeLatex(source);
      var cursor = 0;
      for (final token in tokens) {
        expect(token.start, cursor, reason: 'ada celah atau tumpang tindih di $token');
        cursor = token.end;
      }
      expect(cursor, source.length);
    });

    test('komentar sampai akhir baris saja', () {
      const source = '% ini komentar\nini bukan';
      expect(kindOf(source, 'ini komentar'), SyntaxKind.comment);
      expect(kindOf(source, 'ini bukan'), SyntaxKind.text);
    });

    test('persen yang dilarikan bukan komentar', () {
      // Satuan persen di dalam tulisan ditulis `\%`, dan mewarnai sisa
      // barisnya sebagai komentar akan menyesatkan.
      const source = r'Naik 20\% pada tahun itu.';
      expect(kindOf(source, 'pada tahun'), SyntaxKind.text);
    });

    test('perintah biasa dan perintah kerangka dibedakan', () {
      expect(kindOf(r'\usepackage{amsmath}', r'\usepackage'), SyntaxKind.command);
      expect(kindOf(r'\section{Judul}', r'\section'), SyntaxKind.sectioning);
    });

    test('nama lingkungan diwarnai sendiri', () {
      expect(kindOf(r'\begin{tabular}{ll}', 'tabular'), SyntaxKind.environment);
      expect(kindOf(r'\end{tabular}', 'tabular'), SyntaxKind.environment);
    });

    test('kunci rujukan dan sitasi diwarnai sendiri', () {
      expect(kindOf(r'lihat \ref{tab:hasil}', 'tab:hasil'), SyntaxKind.reference);
      expect(kindOf(r'\cite{contoh2025}', 'contoh2025'), SyntaxKind.reference);
      expect(kindOf(r'\input{bab/pendahuluan}', 'bab/pendahuluan'), SyntaxKind.reference);
    });

    test('pilihan dalam kurung siku dilewati sebelum nama berkas', () {
      const source = r'\includegraphics[width=0.8\linewidth]{gambar/alur.png}';
      expect(kindOf(source, 'gambar/alur.png'), SyntaxKind.reference);
    });

    test('rumus sebaris dan blok', () {
      expect(kindOf(r'nilai $x^2$ besar', r'x^2'), SyntaxKind.math);
      expect(kindOf(r'\[ E = mc^2 \]', 'E = mc'), SyntaxKind.math);
    });

    test('dolar yang tidak pernah ditutup tidak memakan seluruh berkas', () {
      // Satu `$` yang lupa adalah kesalahan ketik yang lazim; kalau ia
      // mewarnai sisa dokumennya sebagai rumus, barisnya sendiri justru
      // tersembunyi.
      const source = 'harga \$100 per bulan\n\nParagraf berikutnya biasa saja.';
      expect(kindOf(source, 'Paragraf berikutnya'), SyntaxKind.text);
    });

    test('teks biasa tetap tanpa jenis khusus', () {
      expect(kindOf('Kalimat biasa.', 'Kalimat'), SyntaxKind.text);
    });
  });

  group('pohon berkas', () {
    test('folder didahulukan, lalu berkas, keduanya urut', () {
      final tree = buildFileTree(<String>[
        'main.tex',
        'bab/02-metode.tex',
        'bab/01-pendahuluan.tex',
        'gambar/alur.png',
        'README.md',
      ]);

      expect(tree.map((n) => n.name), <String>['bab', 'gambar', 'main.tex', 'README.md']);
      expect(tree.first.isDirectory, isTrue);
      expect(
        tree.first.children.map((n) => n.name),
        <String>['01-pendahuluan.tex', '02-metode.tex'],
      );
    });

    test('jalur berkas tetap utuh di dalam simpulnya', () {
      final tree = buildFileTree(<String>['bab/01.tex']);
      expect(tree.single.children.single.path, 'bab/01.tex');
    });

    test('folder bersarang ikut terbentuk', () {
      final tree = buildFileTree(<String>['gambar/src/alur.tex']);
      expect(tree.single.name, 'gambar');
      expect(tree.single.children.single.name, 'src');
      expect(tree.single.children.single.children.single.name, 'alur.tex');
    });

    test('jumlah berkas dihitung sampai ke dalam', () {
      final tree = buildFileTree(<String>['a/b/satu.tex', 'a/dua.tex', 'tiga.tex']);
      expect(tree.first.fileCount, 2);
    });

    test('folder induk sebuah berkas terdaftar semuanya', () {
      expect(ancestorsOf('gambar/src/alur.tex'), <String>{'gambar', 'gambar/src'});
      expect(ancestorsOf('main.tex'), isEmpty);
    });
  });
}
