import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/latex_engine.dart';

/// Compiles with the TeX Live installed on the machine.
///
/// This is the desktop engine. It exists first because it can be tested for
/// real today, and because on Linux and Windows a full TeX Live is what
/// people already have — bundling a second copy of it would be rude.
///
/// Android has no TeX Live at all and gets [TectonicEngine] instead, which is
/// why everything here goes through [LatexEngine].
class LatexmkEngine implements LatexEngine {
  const LatexmkEngine({this.executable = 'latexmk', this.tool = 'xelatex'});

  final String executable;

  /// `xelatex` rather than `pdflatex`: it reads UTF-8 and system fonts
  /// without ceremony, which matters for Indonesian text and for anything
  /// with a non-Latin quotation in it.
  final String tool;

  @override
  String get name => '$executable ($tool)';

  @override
  String get unavailableReason =>
      'TeX Live tidak ditemukan. Pasang dengan: sudo apt install texlive-xetex latexmk';

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await Process.run(executable, <String>['-version']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<CompileResult> compile({
    required String projectDir,
    required String mainFile,
    void Function(String line)? onOutput,
  }) async {
    final started = DateTime.now();
    final buildDir = await ensureBuildDir(projectDir);
    final buffer = StringBuffer();

    // -file-line-error is what makes the log carry "file:line:" prefixes,
    // without which a message cannot be shown next to the code that caused it.
    final args = <String>[
      '-$tool',
      '-interaction=nonstopmode',
      '-file-line-error',
      '-halt-on-error',
      '-synctex=1',
      '-output-directory=$buildDir',
      mainFile,
    ];

    final Process process;
    try {
      process = await Process.start(executable, args, workingDirectory: projectDir);
    } on ProcessException catch (e) {
      return CompileResult(
        ok: false,
        log: '$unavailableReason\n\n$e',
        messages: const <LatexMessage>[],
        duration: DateTime.now().difference(started),
      );
    }

    void collect(Stream<List<int>> stream) {
      stream.transform(const SystemEncoding().decoder).listen((chunk) {
        buffer.write(chunk);
        onOutput?.call(chunk);
      });
    }

    collect(process.stdout);
    collect(process.stderr);
    final exitCode = await process.exitCode;

    // latexmk's own output is a summary; the real errors are in the .log the
    // engine wrote, so both are parsed together.
    final logFile = File(p.join(buildDir, '${p.basenameWithoutExtension(mainFile)}.log'));
    final engineLog = logFile.existsSync() ? await logFile.readAsString() : '';
    final wholeLog = '${buffer.toString()}\n$engineLog';

    final pdf = File(p.join(buildDir, '${p.basenameWithoutExtension(mainFile)}.pdf'));
    final ok = exitCode == 0 && pdf.existsSync();

    return CompileResult(
      ok: ok,
      log: wholeLog,
      messages: const LatexLogParser().parse(wholeLog),
      pdfPath: pdf.existsSync() ? pdf.path : null,
      duration: DateTime.now().difference(started),
    );
  }
}
