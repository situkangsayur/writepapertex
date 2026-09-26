import 'package:path/path.dart' as p;

/// Jenis berkas yang bisa ditambahkan ke sebuah proyek.
enum NewFileKind {
  chapter('Bab atau bagian', 'tex', 'dipanggil dari berkas utama dengan \\input'),
  bibliography('Daftar pustaka', 'bib', 'entri BibTeX, dipakai \\cite'),
  style('Berkas gaya', 'sty', 'paket sendiri, dipanggil \\usepackage'),
  documentClass('Kelas dokumen', 'cls', 'templat kampus atau penerbit'),
  plain('Berkas kosong', '', 'nama dan isinya bebas');

  const NewFileKind(this.label, this.extension, this.hint);

  final String label;

  /// Akhiran yang dipaksakan, kosong berarti apa pun yang ditulis pengguna.
  final String extension;
  final String hint;
}

/// Membuat nama berkas yang tidak menyusahkan LaTeX.
///
/// Spasi di dalam `\input{}` dan `\includegraphics{}` adalah sumber kesalahan
/// yang paling sering terjadi dan pesan errornya paling tidak membantu, jadi
/// namanya dirapikan sebelum dipakai, bukan sesudah gagal.
String sanitiseFileName(String raw, {String extension = ''}) {
  var name = raw.trim().replaceAll(RegExp(r'\s+'), '-');
  name = name.replaceAll(RegExp(r'[^A-Za-z0-9._/-]'), '');
  name = name.replaceAll(RegExp(r'-{2,}'), '-');
  // Path yang naik ke atas folder proyek tidak pernah disengaja.
  name = p.normalize(name).replaceAll(RegExp(r'^(\.\.[/\\])+'), '');
  if (name.startsWith('/')) name = name.substring(1);
  // `normalize` mengubah nama yang habis dirapikan menjadi `.`, dan itu bukan
  // nama berkas — tanpa jaring ini hasilnya `..tex`.
  if (name.isEmpty || name == '.') {
    return extension.isEmpty ? 'berkas' : 'berkas.$extension';
  }
  if (extension.isNotEmpty && p.extension(name) != '.$extension') {
    name = '$name.$extension';
  }
  return name;
}

/// Isi awal sebuah berkas baru.
///
/// Berkas kosong membuat orang harus mengingat susunan yang tidak sering
/// dipakai — apa yang harus ada di baris pertama sebuah `.sty`, misalnya.
String starterContent(NewFileKind kind, String relative) {
  final stem = p.basenameWithoutExtension(relative);
  return switch (kind) {
    NewFileKind.chapter =>
      '% $relative\n'
          '\\section{${_titleCase(stem)}}\n'
          '\\label{sec:$stem}\n\n',
    NewFileKind.bibliography =>
      '% $relative\n'
          '@article{contoh2025,\n'
          '  author  = {Nama Penulis},\n'
          '  title   = {Judul Tulisan},\n'
          '  journal = {Nama Jurnal},\n'
          '  year    = {2025},\n'
          '  volume  = {1},\n'
          '  pages   = {1--10},\n'
          '}\n',
    NewFileKind.style =>
      '\\NeedsTeXFormat{LaTeX2e}\n'
          '\\ProvidesPackage{$stem}[${_today()} gaya proyek]\n\n'
          '% Perintah dan pengaturan sendiri ditulis di bawah ini.\n',
    NewFileKind.documentClass =>
      '\\NeedsTeXFormat{LaTeX2e}\n'
          '\\ProvidesClass{$stem}[${_today()} kelas dokumen]\n\n'
          '% Mewarisi article, lalu diubah seperlunya.\n'
          '\\LoadClass[11pt,a4paper]{article}\n',
    NewFileKind.plain => '',
  };
}

String _titleCase(String slug) {
  final words = slug.split(RegExp(r'[-_]+')).where((w) => w.isNotEmpty);
  return words
      .map((w) => w.length == 1 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _today() {
  final now = DateTime.now();
  return '${now.year}/${now.month.toString().padLeft(2, '0')}/'
      '${now.day.toString().padLeft(2, '0')}';
}

/// Baris yang harus masuk ke *preamble* supaya berkas baru itu terpakai.
///
/// Null berarti tidak ada yang perlu ditambahkan di preamble.
String? preambleLineFor(NewFileKind kind, String relative, {required bool usesBiblatex}) =>
    switch (kind) {
      NewFileKind.style => '\\usepackage{${_withoutExtension(relative)}}',
      NewFileKind.bibliography => usesBiblatex ? '\\addbibresource{$relative}' : null,
      _ => null,
    };

/// Baris yang harus masuk ke badan dokumen.
String? bodyLineFor(NewFileKind kind, String relative, {required bool usesBiblatex}) =>
    switch (kind) {
      NewFileKind.chapter => '\\input{${_withoutExtension(relative)}}',
      NewFileKind.bibliography =>
        usesBiblatex
            ? '\\printbibliography'
            : '\\bibliographystyle{plain}\n\\bibliography{${_withoutExtension(relative)}}',
      _ => null,
    };

/// `\input` dan kawan-kawannya tidak memakai akhiran `.tex`.
String _withoutExtension(String relative) => p.join(
  p.dirname(relative) == '.' ? '' : p.dirname(relative),
  p.basenameWithoutExtension(relative),
);

/// True kalau dokumennya memakai biblatex, bukan BibTeX lama.
///
/// Keduanya dipanggil dengan cara yang sama sekali berbeda, dan mencampurnya
/// menghasilkan daftar pustaka yang kosong tanpa pesan kesalahan.
bool usesBiblatex(String source) =>
    source.contains(RegExp(r'\\usepackage(\[[^\]]*\])?\{biblatex\}'));

/// Tempat menyisipkan baris preamble.
///
/// Sesudah `\usepackage` yang terakhir kalau ada — urutan paket kadang penting
/// dan yang ditambahkan orang biasanya bergantung pada yang sudah ada.
/// Kalau tidak ada, tepat sebelum `\begin{document}`.
int preambleInsertionPoint(String source) {
  final begin = source.indexOf(r'\begin{document}');
  final limit = begin < 0 ? source.length : begin;
  final matches = RegExp(
    r'\\(?:usepackage|RequirePackage)(?:\[[^\]]*\])?\{[^}]*\}',
  ).allMatches(source.substring(0, limit)).toList();
  if (matches.isNotEmpty) return _lineEndAfter(source, matches.last.end);
  if (begin >= 0) return begin;
  return source.length;
}

/// Tempat menyisipkan baris badan dokumen: tepat sebelum `\end{document}`.
///
/// Apa pun yang ditulis sesudahnya diabaikan LaTeX tanpa keluhan, jadi
/// sisipan yang mendarat di sana menghasilkan berkas yang seolah tidak pernah
/// ikut terkompilasi.
int bodyInsertionPoint(String source) {
  final end = source.lastIndexOf(r'\end{document}');
  return end < 0 ? source.length : end;
}

int _lineEndAfter(String source, int offset) {
  final newline = source.indexOf('\n', offset);
  return newline < 0 ? source.length : newline + 1;
}

/// Menyisipkan [line] sekali saja.
///
/// Menambahkan berkas gaya yang sama dua kali tidak boleh menghasilkan dua
/// `\usepackage` — LaTeX akan menolaknya dengan "Option clash".
String insertOnce(String source, String line, {required bool preamble}) {
  if (source.contains(line.trim())) return source;
  final at = preamble ? preambleInsertionPoint(source) : bodyInsertionPoint(source);
  return source.replaceRange(at, at, '$line\n');
}

/// Akhiran berkas gambar yang bisa dipakai LaTeX lewat graphicx.
const Set<String> graphicsExtensions = <String>{'.pdf', '.png', '.jpg', '.jpeg', '.eps', '.svg'};

bool isGraphic(String relative) => graphicsExtensions.contains(p.extension(relative).toLowerCase());

/// Lingkungan `figure` untuk sebuah gambar yang baru ditambahkan.
String figureSnippet(String relative, {String? caption}) {
  final stem = p.basenameWithoutExtension(relative);
  return '\\begin{figure}[ht]\n'
      '  \\centering\n'
      '  \\includegraphics[width=0.8\\linewidth]{$relative}\n'
      '  \\caption{${caption == null || caption.isEmpty ? _titleCase(stem) : caption}}\n'
      '  \\label{fig:$stem}\n'
      '\\end{figure}\n';
}

/// Nama folder yang enak dipakai untuk menaruh berkas pendukung.
///
/// Folder yang sudah ada di proyek dipakai lagi daripada membuat yang baru
/// dengan nama berbeda — proyek yang sudah punya `gambar/` tidak butuh
/// `figures/` di sebelahnya.
String preferredAssetDir(Iterable<String> existing, {required bool graphic}) {
  final dirs = existing.map(p.dirname).where((d) => d != '.').toSet();
  final wanted = graphic
      ? <String>['gambar', 'figures', 'figs', 'images', 'img']
      : <String>['data', 'berkas', 'assets'];
  for (final candidate in wanted) {
    if (dirs.any((d) => p.split(d).first == candidate)) return candidate;
  }
  return wanted.first;
}

/// Jenis yang cocok untuk sebuah akhiran berkas.
///
/// Dipakai saat berkas diambil dari perangkat: yang menentukan cara
/// memanggilnya bukan pilihan pengguna, melainkan berkasnya sendiri.
NewFileKind? kindForExtension(String relative) => switch (p.extension(relative).toLowerCase()) {
  '.tex' => NewFileKind.chapter,
  '.bib' => NewFileKind.bibliography,
  '.sty' => NewFileKind.style,
  '.cls' => NewFileKind.documentClass,
  _ => null,
};
