import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// What came back from one compilation.
@immutable
class CompileResult {
  const CompileResult({
    required this.ok,
    required this.log,
    required this.messages,
    this.pdfPath,
    this.duration = Duration.zero,
  });

  final bool ok;

  /// The engine's own log, kept whole — LaTeX errors are often only
  /// understandable from the lines around them.
  final String log;

  /// Errors and warnings picked out of the log, ready to show beside the
  /// line they belong to.
  final List<LatexMessage> messages;

  final String? pdfPath;
  final Duration duration;

  List<LatexMessage> get errors =>
      messages.where((m) => m.severity == LatexSeverity.error).toList(growable: false);
}

enum LatexSeverity { error, warning, info }

/// One line of the log, tied back to the source line that caused it.
@immutable
class LatexMessage {
  const LatexMessage({required this.severity, required this.text, this.file, this.line});

  final LatexSeverity severity;
  final String text;
  final String? file;
  final int? line;

  @override
  String toString() => '${severity.name}: $text${line == null ? '' : ' (baris $line)'}';
}

/// Turns a LaTeX project into a PDF.
///
/// There is more than one way to do this and they are not interchangeable:
/// a desktop has TeX Live installed, an Android tablet has nothing at all.
/// The editor talks to this interface so that neither has to know about the
/// other.
abstract class LatexEngine {
  /// A name for the user, e.g. "latexmk (TeX Live)".
  String get name;

  /// False when the engine cannot run here; the reason is in [unavailableReason].
  Future<bool> isAvailable();

  String get unavailableReason;

  /// Compiles [mainFile], writing output next to it.
  Future<CompileResult> compile({
    required String projectDir,
    required String mainFile,
    void Function(String line)? onOutput,
  });
}

/// Reads LaTeX's log format into something that can be shown next to the code.
///
/// The log is not structured, so this is pattern matching; it is deliberately
/// forgiving, because a message half-understood is still better than a wall
/// of text.
class LatexLogParser {
  const LatexLogParser();

  /// `./main.tex:12: Undefined control sequence.` — the form latexmk and
  /// `-file-line-error` produce, which is the only one carrying a line number
  /// reliably.
  static final RegExp _fileLine = RegExp(r'^(.+?):(\d+):\s*(.*)$');

  /// `! LaTeX Error: File `foo.sty' not found.` — no line number here.
  static final RegExp _bang = RegExp(r'^!\s*(.*)$');

  /// `LaTeX Warning: Reference `fig:1' on page 1 undefined on input line 42.`
  static final RegExp _warning = RegExp(r'^(?:LaTeX|Package|Class)\s+(?:\w+\s+)?Warning:\s*(.*)$');
  static final RegExp _warningLine = RegExp(r'input line (\d+)');

  List<LatexMessage> parse(String log) {
    final out = <LatexMessage>[];
    for (final raw in const LineSplitter().convert(log)) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;

      final fileLine = _fileLine.firstMatch(line);
      if (fileLine != null && !line.startsWith('!')) {
        final text = fileLine.group(3)!.trim();
        if (text.isNotEmpty) {
          out.add(
            LatexMessage(
              severity: LatexSeverity.error,
              text: text,
              file: fileLine.group(1),
              line: int.tryParse(fileLine.group(2)!),
            ),
          );
          continue;
        }
      }

      final bang = _bang.firstMatch(line);
      if (bang != null) {
        out.add(LatexMessage(severity: LatexSeverity.error, text: bang.group(1)!.trim()));
        continue;
      }

      final warning = _warning.firstMatch(line);
      if (warning != null) {
        final text = warning.group(1)!.trim();
        final at = _warningLine.firstMatch(text);
        out.add(
          LatexMessage(
            severity: LatexSeverity.warning,
            text: text,
            line: at == null ? null : int.tryParse(at.group(1)!),
          ),
        );
      }
    }
    return out;
  }
}

/// Splits on every line ending, including the lone `\r` that older TeX
/// distributions still emit.
class LineSplitter {
  const LineSplitter();
  List<String> convert(String s) => s.split(RegExp(r'\r\n|\r|\n'));
}

/// Where a project's build output goes.
///
/// Kept out of the project directory: a LaTeX build leaves a dozen files
/// behind, and a project loaded from GitHub would show every one of them as
/// an uncommitted change.
String buildDirFor(String projectDir) => p.join(projectDir, '.writepapertex', 'build');

/// True when [path] is a file LaTeX generated rather than one someone wrote.
bool isGeneratedFile(String path) {
  const extensions = <String>{
    '.aux',
    '.log',
    '.out',
    '.toc',
    '.lof',
    '.lot',
    '.fls',
    '.fdb_latexmk',
    '.synctex.gz',
    '.bbl',
    '.blg',
    '.nav',
    '.snm',
    '.vrb',
    '.run.xml',
    '.bcf',
  };
  final name = p.basename(path);
  if (name.endsWith('.synctex.gz')) return true;
  return extensions.contains(p.extension(name));
}

/// Ensures a directory exists and hands back its path.
Future<String> ensureDir(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir.path;
}
