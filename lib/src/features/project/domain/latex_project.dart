import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../compile/domain/latex_engine.dart';

/// One folder holding a LaTeX document.
@immutable
class LatexProject {
  const LatexProject({required this.directory, required this.mainFile, required this.files});

  final String directory;

  /// The file passed to the engine, relative to [directory].
  final String mainFile;

  /// Every source file, relative to [directory], sorted.
  final List<String> files;

  String get name => p.basename(directory);

  String absolute(String relative) => p.join(directory, relative);

  /// Opens a folder, working out which file to compile.
  static Future<LatexProject> open(String directory) async {
    final files = await _sourceFiles(directory);
    return LatexProject(
      directory: directory,
      mainFile: await _guessMainFile(directory, files),
      files: files,
    );
  }

  /// Every file worth showing: build output is left out, because after one
  /// compilation it outnumbers the real files.
  static Future<List<String>> _sourceFiles(String directory) async {
    final root = Directory(directory);
    if (!root.existsSync()) return const <String>[];
    final out = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: directory);
      if (p.split(relative).any((s) => s.startsWith('.'))) continue;
      if (isGeneratedFile(relative)) continue;
      out.add(relative);
    }
    out.sort();
    return out;
  }

  /// The main file is the one with `\documentclass` in it.
  ///
  /// Guessing by name would pick `main.tex` even in a project whose entry
  /// point is `skripsi.tex`, and a chapter file included by another is not a
  /// document on its own. But `\documentclass` alone is not enough either:
  /// a real thesis keeps each figure as its own `standalone` document, and
  /// those sort before the thesis itself. So the candidates are scored.
  static Future<String> _guessMainFile(String directory, List<String> files) async {
    final texFiles = files.where((f) => p.extension(f) == '.tex').toList();
    if (texFiles.isEmpty) return 'main.tex';

    ({String file, int score})? best;
    for (final candidate in texFiles) {
      final String text;
      try {
        text = await File(p.join(directory, candidate)).readAsString();
      } on FileSystemException {
        continue;
      }
      final score = mainFileScore(candidate, text);
      if (score <= 0) continue;
      if (best == null || score > best.score) best = (file: candidate, score: score);
    }
    if (best != null) return best.file;

    // Nothing declared a class; the shallowest file is the best remaining bet.
    texFiles.sort((a, b) => p.split(a).length.compareTo(p.split(b).length));
    return texFiles.first;
  }

  /// Seberapa mungkin sebuah berkas adalah berkas utama proyek. 0 berarti
  /// bukan dokumen sama sekali.
  ///
  /// Dipisahkan supaya bisa diuji tanpa menyiapkan folder di disk.
  static int mainFileScore(String relative, String text) {
    if (!text.contains(RegExp(r'\\documentclass'))) return 0;
    var score = 100;

    // Gambar dan potongan yang berdiri sendiri memakai kelas `standalone`.
    // Sebuah tesis bisa punya belasan di antaranya, dan semuanya bukan
    // dokumen utama.
    if (text.contains(RegExp(r'\\documentclass(\[[^\]]*\])?\{standalone\}'))) score -= 80;

    // Berkas utama hampir selalu ada di akar proyek.
    score -= (p.split(relative).length - 1) * 12;

    // Yang memanggil berkas lain adalah induknya, bukan yang dipanggil.
    score += RegExp(r'\\(input|include|subfile)\{').allMatches(text).length.clamp(0, 10) * 4;

    // Penanda dokumen panjang: daftar isi, judul, daftar pustaka.
    for (final marker in <String>[
      r'\tableofcontents',
      r'\maketitle',
      r'\bibliography',
      r'\printbibliography',
      r'\frontmatter',
    ]) {
      if (text.contains(marker)) score += 6;
    }

    // Nama yang lazim dipakai orang untuk berkas utama.
    final stem = p.basenameWithoutExtension(relative).toLowerCase();
    if (<String>{
      'main',
      'utama',
      'proposal',
      'skripsi',
      'tesis',
      'disertasi',
      'paper',
      'artikel',
      'laporan',
      'thesis',
      'root',
    }.contains(stem)) {
      score += 15;
    }

    return score;
  }

  LatexProject copyWith({String? mainFile, List<String>? files}) => LatexProject(
    directory: directory,
    mainFile: mainFile ?? this.mainFile,
    files: files ?? this.files,
  );
}

/// A starting document.
@immutable
class ProjectTemplate {
  const ProjectTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
  });

  final String id;
  final String name;
  final String description;
  final String source;

  /// Writes the template into [directory] and opens it.
  Future<LatexProject> create(String directory) async {
    await ensureDir(directory);
    final main = File(p.join(directory, 'main.tex'));
    if (main.existsSync()) {
      throw StateError('Folder ini sudah berisi main.tex');
    }
    await main.writeAsString(source);

    // Proyek baru hampir selalu berakhir di git, dan tanpa ini commit
    // pertamanya ikut membawa belasan berkas keluaran yang tidak ada gunanya
    // bagi siapa pun.
    final ignore = File(p.join(directory, '.gitignore'));
    if (!ignore.existsSync()) await ignore.writeAsString(latexGitignore);

    return LatexProject.open(directory);
  }

  static const List<ProjectTemplate> all = <ProjectTemplate>[
    ProjectTemplate(
      id: 'article',
      name: 'Artikel',
      description: 'Satu berkas, siap ditulisi',
      source: r'''
\documentclass[11pt,a4paper]{article}
\usepackage[T1]{fontenc}
\usepackage[bahasa]{babel}
\usepackage{graphicx}
\usepackage{booktabs}
\usepackage{hyperref}

\title{Judul Tulisan}
\author{Nama Penulis}
\date{\today}

\begin{document}
\maketitle

\begin{abstract}
Ringkasan satu paragraf.
\end{abstract}

\section{Pendahuluan}
Tulis di sini.

\end{document}
''',
    ),
    ProjectTemplate(
      id: 'table',
      name: 'Artikel dengan tabel',
      description: 'Sudah memuat booktabs dan satu tabel contoh',
      source: r'''
\documentclass[11pt,a4paper]{article}
\usepackage[T1]{fontenc}
\usepackage[bahasa]{babel}
\usepackage{booktabs}
\usepackage{tabularx}
\usepackage{longtable}
\usepackage{multirow}
\usepackage{siunitx}

\title{Judul Tulisan}
\author{Nama Penulis}

\begin{document}
\maketitle

\section{Hasil}

% booktabs, bukan \hline: garis ganda hampir tidak pernah benar.
\begin{table}[ht]
  \centering
  \caption{Perbandingan metode}
  \label{tab:hasil}
  \begin{tabular}{lrr}
    \toprule
    Metode & Akurasi & Waktu (s) \\
    \midrule
    Dasar    & 0,91 & 12 \\
    Usulan   & 0,97 &  9 \\
    \bottomrule
  \end{tabular}
\end{table}

Tabel~\ref{tab:hasil} merangkum hasilnya.

\end{document}
''',
    ),
    ProjectTemplate(
      id: 'report',
      name: 'Laporan / skripsi',
      description: 'Berbab, dengan daftar isi',
      source: r'''
\documentclass[11pt,a4paper]{report}
\usepackage[T1]{fontenc}
\usepackage[bahasa]{babel}
\usepackage{graphicx}
\usepackage{booktabs}
\usepackage{hyperref}

\title{Judul Laporan}
\author{Nama Penulis}

\begin{document}
\maketitle
\tableofcontents

\chapter{Pendahuluan}
Tulis di sini.

\chapter{Metode}

\end{document}
''',
    ),
  ];
}
