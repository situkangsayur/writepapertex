import 'package:meta/meta.dart';

/// Bagian-bagian LaTeX yang pantas dibedakan warnanya.
///
/// Sengaja sedikit. Pewarnaan yang membedakan dua puluh hal sama sulitnya
/// dibaca dengan yang tidak membedakan apa pun; yang benar-benar menolong
/// adalah tahu dengan sekali lihat mana komentar, mana perintah, dan mana
/// nama lingkungan yang harus cocok antara `\begin` dan `\end`.
enum SyntaxKind {
  /// Teks biasa — isi tulisannya sendiri.
  text,

  /// `% sampai akhir baris`.
  comment,

  /// `\section`, `\usepackage`, dan kawan-kawannya.
  command,

  /// Perintah yang membentuk kerangka dokumen, dibuat menonjol.
  sectioning,

  /// Nama lingkungan di dalam `\begin{...}` dan `\end{...}`.
  environment,

  /// Kunci di dalam `\ref{...}`, `\cite{...}`, `\label{...}`.
  reference,

  /// Rumus di antara `$…$`, `\(…\)`, atau `\[…\]`.
  math,

  /// `{ } [ ]` dan `&`, `~`, `\\` — penanda struktur, bukan isi.
  delimiter,
}

/// Satu potongan teks yang sewarna.
@immutable
class SyntaxToken {
  const SyntaxToken(this.start, this.end, this.kind);

  final int start;
  final int end;
  final SyntaxKind kind;

  int get length => end - start;

  @override
  String toString() => '$kind($start..$end)';

  @override
  bool operator ==(Object other) =>
      other is SyntaxToken && other.start == start && other.end == end && other.kind == kind;

  @override
  int get hashCode => Object.hash(start, end, kind);
}

/// Perintah yang membentuk kerangka dokumen.
const Set<String> _sectioning = <String>{
  'part',
  'chapter',
  'section',
  'subsection',
  'subsubsection',
  'paragraph',
  'subparagraph',
  'title',
  'author',
  'date',
  'maketitle',
  'documentclass',
  'begin',
  'end',
};

/// Perintah yang argumennya adalah kunci, bukan tulisan yang dibaca orang.
const Set<String> _keyTaking = <String>{
  'ref',
  'eqref',
  'pageref',
  'autoref',
  'cref',
  'Cref',
  'nameref',
  'label',
  'cite',
  'citep',
  'citet',
  'citeauthor',
  'citeyear',
  'parencite',
  'textcite',
  'input',
  'include',
  'usepackage',
  'RequirePackage',
  'bibliography',
  'addbibresource',
  'includegraphics',
};

/// Membagi sumber LaTeX menjadi potongan-potongan sewarna.
///
/// Keluarannya menutup seluruh teks tanpa celah dan tanpa tumpang tindih,
/// supaya yang memakainya cukup menyusun ulang tanpa menghitung apa pun.
List<SyntaxToken> tokenizeLatex(String source) {
  final tokens = <SyntaxToken>[];
  var plainFrom = 0;
  var i = 0;

  void flushPlain(int until) {
    if (until > plainFrom) tokens.add(SyntaxToken(plainFrom, until, SyntaxKind.text));
  }

  void add(int start, int end, SyntaxKind kind) {
    flushPlain(start);
    tokens.add(SyntaxToken(start, end, kind));
    plainFrom = end;
  }

  bool isLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  /// Melewati ruang putih, lalu mengambil satu kelompok `{...}` kalau ada.
  ///
  /// Dipakai untuk mewarnai isi `\begin{...}` dan `\ref{...}` berbeda dari
  /// tulisan biasa. Kurung yang tidak pernah ditutup tidak dianggap kelompok:
  /// mewarnai sisa berkas karena satu kurung yang lupa adalah kebisingan.
  int? takeGroup(int from, SyntaxKind inner) {
    var j = from;
    while (j < source.length && (source[j] == ' ' || source[j] == '\t')) {
      j++;
    }
    if (j >= source.length || source[j] != '{') return null;
    final close = source.indexOf('}', j + 1);
    if (close < 0) return null;
    final newline = source.indexOf('\n', j + 1);
    if (newline >= 0 && newline < close) return null;

    add(j, j + 1, SyntaxKind.delimiter);
    if (close > j + 1) add(j + 1, close, inner);
    add(close, close + 1, SyntaxKind.delimiter);
    return close + 1;
  }

  while (i < source.length) {
    final ch = source[i];

    // Komentar: sampai akhir baris. `\%` bukan komentar — dan itu sering
    // muncul pada satuan persen di dalam tulisan.
    if (ch == '%') {
      final end = source.indexOf('\n', i);
      final stop = end < 0 ? source.length : end;
      add(i, stop, SyntaxKind.comment);
      i = stop;
      continue;
    }

    if (ch == r'\') {
      if (i + 1 >= source.length) {
        add(i, i + 1, SyntaxKind.command);
        i += 1;
        continue;
      }
      final next = source.codeUnitAt(i + 1);

      // `\\`, `\%`, `\&`, `\{` — satu huruf yang dilarikan, bukan perintah.
      if (!isLetter(next)) {
        // `\[` dan `\(` membuka rumus.
        final opener = source[i + 1];
        if (opener == '[' || opener == '(') {
          final closer = opener == '[' ? r'\]' : r'\)';
          final close = source.indexOf(closer, i + 2);
          final stop = close < 0 ? source.length : close + 2;
          add(i, stop, SyntaxKind.math);
          i = stop;
          continue;
        }
        add(i, i + 2, SyntaxKind.delimiter);
        i += 2;
        continue;
      }

      var j = i + 1;
      while (j < source.length && isLetter(source.codeUnitAt(j))) {
        j++;
      }
      if (j < source.length && source[j] == '*') j++;
      final name = source.substring(i + 1, j).replaceAll('*', '');

      add(i, j, _sectioning.contains(name) ? SyntaxKind.sectioning : SyntaxKind.command);
      i = j;

      if (name == 'begin' || name == 'end') {
        i = takeGroup(i, SyntaxKind.environment) ?? i;
      } else if (_keyTaking.contains(name)) {
        // `\includegraphics[width=…]{berkas}` — pilihan dalam kurung siku
        // dilewati dulu supaya yang diwarnai memang nama berkasnya.
        if (i < source.length && source[i] == '[') {
          final close = source.indexOf(']', i);
          if (close > 0) i = close + 1;
        }
        i = takeGroup(i, SyntaxKind.reference) ?? i;
      }
      continue;
    }

    // Rumus sebaris: `$…$` dan `$$…$$`.
    if (ch == r'$') {
      final double = source.startsWith(r'$$', i);
      final marker = double ? r'$$' : r'$';
      final close = source.indexOf(marker, i + marker.length);
      // `$` yang tidak pernah ditutup hampir selalu kesalahan ketik; mewarnai
      // sisa berkas sebagai rumus hanya menyembunyikan barisnya sendiri.
      final lineEnd = source.indexOf('\n\n', i);
      if (close < 0 || (lineEnd >= 0 && close > lineEnd)) {
        add(i, i + marker.length, SyntaxKind.delimiter);
        i += marker.length;
        continue;
      }
      final stop = close + marker.length;
      add(i, stop, SyntaxKind.math);
      i = stop;
      continue;
    }

    if (ch == '{' || ch == '}' || ch == '[' || ch == ']' || ch == '&' || ch == '~') {
      add(i, i + 1, SyntaxKind.delimiter);
      i += 1;
      continue;
    }

    i++;
  }

  flushPlain(source.length);
  return tokens;
}
