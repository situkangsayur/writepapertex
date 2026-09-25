import 'latex_language.dart';

/// Reads TeXstudio/Kile **completion word list** files.
///
/// A CWL file lists the commands a package provides, one per line, with its
/// arguments written as placeholders:
///
/// ```
/// # comment
/// \includegraphics[options]{file}
/// \begin{tabularx}{width}{preamble}
/// \toprule
/// \cmidrule(trim){a-b}#*
/// ```
///
/// Reading this format matters more than the parser itself: thousands of CWL
/// files already exist for TeX Live packages, so supporting it means the
/// built-in command list never has to grow by hand again.
class CwlParser {
  const CwlParser();

  /// Lines TeXstudio uses for directives rather than commands.
  static final RegExp _directive = RegExp(r'^#');

  /// The classification TeXstudio appends after a command, e.g. `#*` or `#m`.
  static final RegExp _classification = RegExp(r'#[^#\s]*$');

  /// `%<name%>` is how the extended format writes a placeholder's name.
  static final RegExp _placeholderMarks = RegExp(r'%<|%>');

  /// Packages this file says it depends on, from `#include:name` lines.
  List<String> includesOf(String source) => <String>[
    for (final line in const LineSplitter().convert(source))
      if (line.startsWith('#include:')) line.substring('#include:'.length).trim(),
  ].where((s) => s.isNotEmpty).toList(growable: false);

  /// Every completion the file defines.
  List<Completion> parse(String source, {String from = ''}) {
    final commands = <Completion>[];
    final seen = <String>{};

    for (final raw in const LineSplitter().convert(source)) {
      final line = raw.trim();
      if (line.isEmpty || _directive.hasMatch(line)) continue;
      if (!line.startsWith('\\')) continue;

      final completion = _parseLine(line, from: from);
      if (completion == null) continue;
      // The same command often appears in several files; the first wins so
      // that a package cannot quietly override a core command.
      if (seen.add(completion.label)) commands.add(completion);
    }
    return commands;
  }

  Completion? _parseLine(String line, {required String from}) {
    var text = line.replaceAll(_classification, '').trim();
    text = text.replaceAll(_placeholderMarks, '');
    if (text.length < 2) return null;

    // `\begin{tabularx}{width}{preamble}` declares an environment, not a
    // command: the completer should offer "tabularx", and the editor wraps it
    // in begin/end itself.
    if (text.startsWith(r'\begin{')) {
      final close = text.indexOf('}');
      if (close < 0) return null;
      final name = text.substring(7, close);
      if (name.isEmpty) return null;
      return Completion(
        label: name,
        insert: name,
        kind: CompletionKind.environment,
        detail: from.isEmpty ? 'lingkungan' : from,
      );
    }
    if (text.startsWith(r'\end{')) return null;

    final name = RegExp(r'^\\([a-zA-Z@]+\*?)').firstMatch(text)?.group(1);
    if (name == null) return null;

    final rest = text.substring(name.length + 1);
    final (:insert, :caret) = _buildInsert('\\$name', rest);
    return Completion(
      label: '\\$name',
      insert: insert,
      kind: CompletionKind.command,
      detail: from.isEmpty ? '' : from,
      cursorOffset: caret,
    );
  }

  /// Turns `[options]{file}` into `[]{}` with the caret in the first one.
  ///
  /// The argument names are dropped rather than inserted: typing over
  /// pre-filled words is slower than typing into empty braces, and a
  /// forgotten placeholder compiles into the document as literal text.
  ({String insert, int? caret}) _buildInsert(String head, String rest) {
    final buffer = StringBuffer(head);
    int? caret;
    var depth = 0;

    for (var i = 0; i < rest.length; i++) {
      final ch = rest[i];
      if (ch == '{' || ch == '[') {
        if (depth == 0) {
          buffer.write(ch);
          caret ??= buffer.length;
        }
        depth++;
      } else if (ch == '}' || ch == ']') {
        depth--;
        if (depth == 0) buffer.write(ch);
        if (depth < 0) depth = 0;
      }
      // Characters inside a group are the argument's name; they are dropped.
    }

    return (insert: buffer.toString(), caret: caret);
  }
}

/// Splits on every line ending, including the lone `\r`.
class LineSplitter {
  const LineSplitter();
  List<String> convert(String s) => s.split(RegExp(r'\r\n|\r|\n'));
}

/// Finds the packages a document loads, so only their completions are offered.
///
/// TeXstudio does the same: a list holding every command in TeX Live is noise,
/// while the packages this document actually loads are exactly the relevant
/// ones.
List<String> scanPackages(String source) {
  final out = <String>{};
  final pattern = RegExp(r'\\(?:usepackage|RequirePackage)\s*(?:\[[^\]]*\])?\s*\{([^}]*)\}');
  for (final match in pattern.allMatches(source)) {
    for (final name in match.group(1)!.split(',')) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) out.add(trimmed);
    }
  }
  // The document class brings its own commands too.
  final klass = RegExp(r'\\documentclass\s*(?:\[[^\]]*\])?\s*\{([^}]*)\}').firstMatch(source);
  if (klass != null) {
    final name = klass.group(1)!.trim();
    if (name.isNotEmpty) out.add('class-$name');
  }
  return out.toList(growable: false);
}
