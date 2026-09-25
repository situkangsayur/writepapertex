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
  /// document on its own.
  static Future<String> _guessMainFile(String directory, List<String> files) async {
    final texFiles = files.where((f) => p.extension(f) == '.tex').toList();
    if (texFiles.isEmpty) return 'main.tex';

    for (final candidate in texFiles) {
      try {
        final text = await File(p.join(directory, candidate)).readAsString();
        if (text.contains(RegExp(r'\\documentclass'))) return candidate;
      } on FileSystemException {
        continue;
      }
    }
    // Nothing declared a class; the shallowest file is the best remaining bet.
    texFiles.sort((a, b) => p.split(a).length.compareTo(p.split(b).length));
    return texFiles.first;
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
