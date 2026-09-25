import 'package:meta/meta.dart';

import 'latex_language.dart';

/// What the caret is sitting in, which decides what may be offered.
enum CompletionContext {
  /// After a backslash: `\sec|`
  command,

  /// Inside `\begin{...}` or `\end{...}`
  environment,

  /// Inside `\ref{...}` or `\eqref{...}`
  reference,

  /// Inside `\cite{...}`
  citation,

  /// Inside `\usepackage{...}`
  package,

  /// Ordinary prose — nothing is offered, because a list that pops up while
  /// writing a sentence is worse than no list at all.
  none,
}

/// What the caret is doing, and the word being typed.
@immutable
class CompletionRequest {
  const CompletionRequest({required this.context, required this.prefix, required this.replaceFrom});

  final CompletionContext context;

  /// The part already typed, e.g. `sec` in `\sec`.
  final String prefix;

  /// Offset where the replacement starts, so accepting a suggestion swaps out
  /// what was typed rather than appending to it.
  final int replaceFrom;
}

/// Decides what to offer at the caret.
///
/// Labels and keys that exist in the project — `\label{...}` and BibTeX keys —
/// are passed in rather than hard-coded, because those are the completions
/// that actually save time: nobody misremembers `\section`, everybody
/// misremembers whether the figure was `fig:overview` or `fig:overview-2`.
class LatexAutocomplete {
  const LatexAutocomplete({
    this.labels = const <String>[],
    this.citationKeys = const <String>[],
    this.packageCommands = const <Completion>[],
  });

  final List<String> labels;
  final List<String> citationKeys;

  /// Read from the CWL files of the packages this document loads.
  final List<Completion> packageCommands;

  static final RegExp _command = RegExp(r'\\([a-zA-Z@]*)$');
  static final RegExp _braceArg = RegExp(r'\\([a-zA-Z@]+)\{([^{}]*)$');

  /// Works out what is being typed just before [offset].
  CompletionRequest requestAt(String text, int offset) {
    if (offset < 0 || offset > text.length) {
      return const CompletionRequest(context: CompletionContext.none, prefix: '', replaceFrom: 0);
    }
    final before = text.substring(0, offset);

    // An argument in braces is checked first: inside `\ref{fig` the backslash
    // rule would otherwise match the `\ref` and offer commands.
    final brace = _braceArg.firstMatch(before);
    if (brace != null) {
      final command = brace.group(1)!;
      final typed = brace.group(2)!;
      final from = offset - typed.length;
      final context = switch (command) {
        'begin' || 'end' => CompletionContext.environment,
        'ref' || 'eqref' || 'autoref' || 'pageref' => CompletionContext.reference,
        'cite' || 'citep' || 'citet' || 'parencite' => CompletionContext.citation,
        'usepackage' || 'RequirePackage' => CompletionContext.package,
        _ => CompletionContext.none,
      };
      return CompletionRequest(context: context, prefix: typed, replaceFrom: from);
    }

    final command = _command.firstMatch(before);
    if (command != null) {
      final typed = command.group(1)!;
      return CompletionRequest(
        context: CompletionContext.command,
        prefix: typed,
        // Includes the backslash, so accepting replaces `\sec` whole.
        replaceFrom: offset - typed.length - 1,
      );
    }

    return const CompletionRequest(context: CompletionContext.none, prefix: '', replaceFrom: 0);
  }

  /// The suggestions for [request], best first.
  List<Completion> suggest(CompletionRequest request) {
    final source = switch (request.context) {
      // Built-ins first: those are the commands everyone reaches for, and a
      // package must not push \section down the list.
      CompletionContext.command => <Completion>[
        ...LatexLanguage.commands,
        ...packageCommands.where((c) => c.kind == CompletionKind.command),
      ],
      CompletionContext.environment => <Completion>[
        ...LatexLanguage.environments,
        ...packageCommands.where((c) => c.kind == CompletionKind.environment),
      ],
      CompletionContext.reference => <Completion>[
        for (final l in labels)
          Completion(label: l, insert: l, kind: CompletionKind.reference, detail: 'label'),
      ],
      CompletionContext.citation => <Completion>[
        for (final k in citationKeys)
          Completion(label: k, insert: k, kind: CompletionKind.citation, detail: 'sitasi'),
      ],
      CompletionContext.package => _packages,
      CompletionContext.none => const <Completion>[],
    };
    if (source.isEmpty) return const <Completion>[];

    final needle = request.prefix.toLowerCase();
    if (needle.isEmpty) return source;

    final starts = <Completion>[];
    final contains = <Completion>[];
    final seen = <String>{};
    for (final c in source) {
      // A package may redefine a built-in; the first definition wins, so the
      // list never shows the same name twice.
      if (!seen.add(c.label)) continue;
      // The label carries a leading backslash for commands; the typed prefix
      // never does.
      final plain = c.label.startsWith('\\') ? c.label.substring(1) : c.label;
      final lower = plain.toLowerCase();
      if (lower.startsWith(needle)) {
        starts.add(c);
      } else if (lower.contains(needle)) {
        contains.add(c);
      }
    }
    // A prefix match is almost always what was meant; the rest follow so a
    // half-remembered name still turns something up.
    return <Completion>[...starts, ...contains];
  }

  static const List<Completion> _packages = <Completion>[
    Completion(
      label: 'booktabs',
      insert: 'booktabs',
      kind: CompletionKind.package,
      detail: 'garis tabel yang benar',
    ),
    Completion(
      label: 'tabularx',
      insert: 'tabularx',
      kind: CompletionKind.package,
      detail: 'tabel selebar teks',
    ),
    Completion(
      label: 'longtable',
      insert: 'longtable',
      kind: CompletionKind.package,
      detail: 'tabel lintas halaman',
    ),
    Completion(
      label: 'multirow',
      insert: 'multirow',
      kind: CompletionKind.package,
      detail: 'gabung baris tabel',
    ),
    Completion(
      label: 'graphicx',
      insert: 'graphicx',
      kind: CompletionKind.package,
      detail: 'gambar',
    ),
    Completion(
      label: 'amsmath',
      insert: 'amsmath',
      kind: CompletionKind.package,
      detail: 'matematika',
    ),
    Completion(
      label: 'amssymb',
      insert: 'amssymb',
      kind: CompletionKind.package,
      detail: 'simbol matematika',
    ),
    Completion(
      label: 'hyperref',
      insert: 'hyperref',
      kind: CompletionKind.package,
      detail: 'tautan dalam PDF',
    ),
    Completion(
      label: 'geometry',
      insert: 'geometry',
      kind: CompletionKind.package,
      detail: 'margin',
    ),
    Completion(label: 'babel', insert: 'babel', kind: CompletionKind.package, detail: 'bahasa'),
    Completion(label: 'natbib', insert: 'natbib', kind: CompletionKind.package, detail: 'sitasi'),
    Completion(
      label: 'biblatex',
      insert: 'biblatex',
      kind: CompletionKind.package,
      detail: 'sitasi',
    ),
    Completion(
      label: 'siunitx',
      insert: 'siunitx',
      kind: CompletionKind.package,
      detail: 'satuan dan angka',
    ),
  ];
}

/// Pulls out `\label{...}` keys so `\ref{` can offer them.
List<String> scanLabels(String text) => RegExp(
  r'\\label\{([^}]+)\}',
).allMatches(text).map((m) => m.group(1)!).toSet().toList(growable: false);

/// Pulls BibTeX keys out of a `.bib` file: `@article{kunci,`.
List<String> scanCitationKeys(String bib) => RegExp(
  r'@\w+\s*\{\s*([^,\s}]+)\s*,',
).allMatches(bib).map((m) => m.group(1)!).toSet().toList(growable: false);

/// A `\ref` pointing at a label no document in the project defines.
///
/// Cheap to find, because every label is already collected for completion —
/// and an undefined reference compiles into the PDF as a bare `??`, which is
/// easy to miss until someone else reads it.
@immutable
class DanglingReference {
  const DanglingReference({required this.key, required this.line});

  final String key;
  final int line;
}

/// Finds `\ref`-like commands whose key is not in [known].
List<DanglingReference> findDanglingReferences(String source, Set<String> known) {
  final out = <DanglingReference>[];
  final pattern = RegExp(r'\\(?:ref|eqref|autoref|pageref|nameref)\{([^}]*)\}');
  final lines = source.split(RegExp(r'\r\n|\r|\n'));
  for (var i = 0; i < lines.length; i++) {
    for (final match in pattern.allMatches(lines[i])) {
      final key = match.group(1)!.trim();
      if (key.isEmpty || known.contains(key)) continue;
      out.add(DanglingReference(key: key, line: i + 1));
    }
  }
  return out;
}

/// Builds the text of a `\begin{...}...\end{...}` pair.
///
/// Returns the text and where the caret should go inside it, because landing
/// after `\end{itemize}` means deleting your way back in.
({String text, int caret}) expandEnvironment(String name, {String indent = ''}) {
  final body = LatexLanguage.environmentBody[name] ?? '  ';
  final head = '$indent\\begin{$name}\n$indent$body';
  final tail = '\n$indent\\end{$name}';
  return (text: head + tail, caret: head.length);
}
