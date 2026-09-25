import 'package:meta/meta.dart';

/// What a completion will insert, and how it reads in the list.
enum CompletionKind { command, environment, reference, citation, package }

@immutable
class Completion {
  const Completion({
    required this.label,
    required this.insert,
    required this.kind,
    this.detail = '',
    this.cursorOffset,
  });

  /// What is shown in the list.
  final String label;

  /// What is put into the document.
  final String insert;

  final CompletionKind kind;
  final String detail;

  /// Where the caret should land inside [insert]; null means at its end.
  ///
  /// `\frac{}{}` is useless if the caret ends up after the last brace.
  final int? cursorOffset;

  @override
  String toString() => label;
}

/// The LaTeX WritePaperTeX knows about out of the box.
///
/// Deliberately not exhaustive. A list of every command in TeX Live would be
/// noise; this is the set someone writing a paper reaches for, plus
/// everything to do with tables, which is the part this editor is meant to
/// be good at.
class LatexLanguage {
  const LatexLanguage._();

  static const List<Completion> commands = <Completion>[
    // --- struktur ---
    Completion(
      label: r'\documentclass',
      insert: r'\documentclass{article}',
      kind: CompletionKind.command,
      detail: 'kelas dokumen',
      cursorOffset: 15,
    ),
    Completion(
      label: r'\usepackage',
      insert: r'\usepackage{}',
      kind: CompletionKind.command,
      detail: 'muat paket',
      cursorOffset: 12,
    ),
    Completion(
      label: r'\section',
      insert: r'\section{}',
      kind: CompletionKind.command,
      detail: 'bagian',
      cursorOffset: 9,
    ),
    Completion(
      label: r'\subsection',
      insert: r'\subsection{}',
      kind: CompletionKind.command,
      detail: 'subbagian',
      cursorOffset: 12,
    ),
    Completion(
      label: r'\subsubsection',
      insert: r'\subsubsection{}',
      kind: CompletionKind.command,
      detail: 'sub-subbagian',
      cursorOffset: 15,
    ),
    Completion(
      label: r'\paragraph',
      insert: r'\paragraph{}',
      kind: CompletionKind.command,
      detail: 'paragraf bernama',
      cursorOffset: 11,
    ),
    Completion(
      label: r'\title',
      insert: r'\title{}',
      kind: CompletionKind.command,
      detail: 'judul',
      cursorOffset: 7,
    ),
    Completion(
      label: r'\author',
      insert: r'\author{}',
      kind: CompletionKind.command,
      detail: 'pengarang',
      cursorOffset: 8,
    ),
    Completion(
      label: r'\maketitle',
      insert: r'\maketitle',
      kind: CompletionKind.command,
      detail: 'cetak judul',
    ),
    Completion(
      label: r'\tableofcontents',
      insert: r'\tableofcontents',
      kind: CompletionKind.command,
      detail: 'daftar isi',
    ),
    Completion(
      label: r'\label',
      insert: r'\label{}',
      kind: CompletionKind.command,
      detail: 'tandai untuk dirujuk',
      cursorOffset: 7,
    ),
    Completion(
      label: r'\ref',
      insert: r'\ref{}',
      kind: CompletionKind.command,
      detail: 'rujuk label',
      cursorOffset: 5,
    ),
    Completion(
      label: r'\eqref',
      insert: r'\eqref{}',
      kind: CompletionKind.command,
      detail: 'rujuk persamaan',
      cursorOffset: 7,
    ),
    Completion(
      label: r'\cite',
      insert: r'\cite{}',
      kind: CompletionKind.command,
      detail: 'sitasi',
      cursorOffset: 6,
    ),
    Completion(
      label: r'\footnote',
      insert: r'\footnote{}',
      kind: CompletionKind.command,
      detail: 'catatan kaki',
      cursorOffset: 10,
    ),
    Completion(
      label: r'\caption',
      insert: r'\caption{}',
      kind: CompletionKind.command,
      detail: 'keterangan',
      cursorOffset: 9,
    ),
    Completion(
      label: r'\includegraphics',
      insert: r'\includegraphics[width=\linewidth]{}',
      kind: CompletionKind.command,
      detail: 'sisipkan gambar',
      cursorOffset: 35,
    ),
    Completion(
      label: r'\input',
      insert: r'\input{}',
      kind: CompletionKind.command,
      detail: 'sisipkan berkas',
      cursorOffset: 7,
    ),
    Completion(
      label: r'\include',
      insert: r'\include{}',
      kind: CompletionKind.command,
      detail: 'sisipkan berkas (halaman baru)',
      cursorOffset: 9,
    ),
    Completion(
      label: r'\bibliography',
      insert: r'\bibliography{}',
      kind: CompletionKind.command,
      detail: 'berkas .bib',
      cursorOffset: 14,
    ),

    // --- teks ---
    Completion(
      label: r'\textbf',
      insert: r'\textbf{}',
      kind: CompletionKind.command,
      detail: 'tebal',
      cursorOffset: 8,
    ),
    Completion(
      label: r'\textit',
      insert: r'\textit{}',
      kind: CompletionKind.command,
      detail: 'miring',
      cursorOffset: 8,
    ),
    Completion(
      label: r'\texttt',
      insert: r'\texttt{}',
      kind: CompletionKind.command,
      detail: 'monospasi',
      cursorOffset: 8,
    ),
    Completion(
      label: r'\emph',
      insert: r'\emph{}',
      kind: CompletionKind.command,
      detail: 'penekanan',
      cursorOffset: 6,
    ),
    Completion(
      label: r'\url',
      insert: r'\url{}',
      kind: CompletionKind.command,
      detail: 'tautan',
      cursorOffset: 5,
    ),

    // --- matematika ---
    Completion(
      label: r'\frac',
      insert: r'\frac{}{}',
      kind: CompletionKind.command,
      detail: 'pecahan',
      cursorOffset: 6,
    ),
    Completion(
      label: r'\sqrt',
      insert: r'\sqrt{}',
      kind: CompletionKind.command,
      detail: 'akar',
      cursorOffset: 6,
    ),
    Completion(
      label: r'\sum',
      insert: r'\sum_{}^{}',
      kind: CompletionKind.command,
      detail: 'jumlah',
      cursorOffset: 6,
    ),
    Completion(
      label: r'\int',
      insert: r'\int_{}^{}',
      kind: CompletionKind.command,
      detail: 'integral',
      cursorOffset: 6,
    ),

    // --- tabel; bagian yang paling menyiksa ditulis tangan ---
    Completion(
      label: r'\toprule',
      insert: r'\toprule',
      kind: CompletionKind.command,
      detail: 'garis atas (booktabs)',
    ),
    Completion(
      label: r'\midrule',
      insert: r'\midrule',
      kind: CompletionKind.command,
      detail: 'garis tengah (booktabs)',
    ),
    Completion(
      label: r'\bottomrule',
      insert: r'\bottomrule',
      kind: CompletionKind.command,
      detail: 'garis bawah (booktabs)',
    ),
    Completion(
      label: r'\cmidrule',
      insert: r'\cmidrule(lr){}',
      kind: CompletionKind.command,
      detail: 'garis sebagian kolom',
      cursorOffset: 14,
    ),
    Completion(
      label: r'\multicolumn',
      insert: r'\multicolumn{2}{c}{}',
      kind: CompletionKind.command,
      detail: 'gabung kolom',
      cursorOffset: 19,
    ),
    Completion(
      label: r'\multirow',
      insert: r'\multirow{2}{*}{}',
      kind: CompletionKind.command,
      detail: 'gabung baris',
      cursorOffset: 16,
    ),
    Completion(
      label: r'\hline',
      insert: r'\hline',
      kind: CompletionKind.command,
      detail: 'garis (lebih baik pakai booktabs)',
    ),
  ];

  static const List<Completion> environments = <Completion>[
    Completion(
      label: 'document',
      insert: 'document',
      kind: CompletionKind.environment,
      detail: 'badan dokumen',
    ),
    Completion(
      label: 'abstract',
      insert: 'abstract',
      kind: CompletionKind.environment,
      detail: 'abstrak',
    ),
    Completion(
      label: 'itemize',
      insert: 'itemize',
      kind: CompletionKind.environment,
      detail: 'daftar bertitik',
    ),
    Completion(
      label: 'enumerate',
      insert: 'enumerate',
      kind: CompletionKind.environment,
      detail: 'daftar bernomor',
    ),
    Completion(
      label: 'figure',
      insert: 'figure',
      kind: CompletionKind.environment,
      detail: 'gambar mengambang',
    ),
    Completion(
      label: 'table',
      insert: 'table',
      kind: CompletionKind.environment,
      detail: 'tabel mengambang',
    ),
    Completion(
      label: 'tabular',
      insert: 'tabular',
      kind: CompletionKind.environment,
      detail: 'isi tabel',
    ),
    Completion(
      label: 'tabularx',
      insert: 'tabularx',
      kind: CompletionKind.environment,
      detail: 'tabel selebar teks',
    ),
    Completion(
      label: 'longtable',
      insert: 'longtable',
      kind: CompletionKind.environment,
      detail: 'tabel lintas halaman',
    ),
    Completion(
      label: 'equation',
      insert: 'equation',
      kind: CompletionKind.environment,
      detail: 'persamaan bernomor',
    ),
    Completion(
      label: 'align',
      insert: 'align',
      kind: CompletionKind.environment,
      detail: 'persamaan sejajar',
    ),
    Completion(
      label: 'verbatim',
      insert: 'verbatim',
      kind: CompletionKind.environment,
      detail: 'apa adanya',
    ),
    Completion(
      label: 'quote',
      insert: 'quote',
      kind: CompletionKind.environment,
      detail: 'kutipan',
    ),
    Completion(
      label: 'thebibliography',
      insert: 'thebibliography',
      kind: CompletionKind.environment,
      detail: 'daftar pustaka',
    ),
  ];

  /// Environments whose body is indented and that carry a starting line.
  static const Map<String, String> environmentBody = <String, String>{
    'itemize': r'  \item ',
    'enumerate': r'  \item ',
    'figure': '  \\centering\n  ',
    'table': '  \\centering\n  ',
    'tabular': r'  ',
    'equation': r'  ',
    'align': r'  ',
  };
}
