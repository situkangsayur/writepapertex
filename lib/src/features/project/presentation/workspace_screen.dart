import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../core/utils/layout_size.dart';
import '../../compile/data/latexmk_engine.dart';
import '../../compile/domain/latex_engine.dart';
import '../../editor/data/cwl_repository.dart';
import '../../editor/domain/autocomplete.dart';
import '../../editor/presentation/latex_editor.dart';
import '../../git/data/git_cli_backend.dart';
import '../../git/domain/git_backend.dart';
import '../../git/presentation/git_panel.dart';
import '../../table/presentation/table_editor_sheet.dart';
import '../domain/latex_project.dart';

/// Everything at once: files on the left, source in the middle, PDF on the
/// right — as much of it as the window can hold.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({required this.project, super.key});

  final LatexProject project;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final TextEditingController _editor = TextEditingController();
  final PdfViewerController _pdf = PdfViewerController();
  final LatexmkEngine _engine = const LatexmkEngine();
  final GitBackend _git = const GitCliBackend();

  late final LatexProject _project = widget.project;

  /// True while a file is being put into the editor, so filling it does not
  /// count as the user typing.
  bool _loadingFile = false;

  /// Null until checked; false means there is no engine on this platform.
  bool? _engineReady;
  String? _openFile;
  bool _dirty = false;
  bool _compiling = false;
  CompileResult? _result;
  LatexAutocomplete _autocomplete = const LatexAutocomplete();
  late final CwlRepository _cwl = CwlRepository(projectDir: _project.directory);

  /// `\ref` keys nothing in the project defines.
  List<DanglingReference> _dangling = const <DanglingReference>[];

  /// Kept across rebuilds so a recompile does not throw the writer back to
  /// page one — which is what makes an iterative document unbearable.
  int _pdfPage = 1;

  @override
  void initState() {
    super.initState();
    _editor.addListener(_onEdited);
    _openRelative(_project.mainFile);
    _checkEngine();
  }

  /// Marks the file as changed.
  ///
  /// Without this the save button stayed disabled forever and the modified
  /// dot never appeared, so the only way to save was to compile.
  void _onEdited() {
    if (_loadingFile || _dirty) return;
    setState(() => _dirty = true);
  }

  /// Android has no TeX Live and Tectonic is not bundled yet, so compilation
  /// is simply unavailable there. Saying so once, plainly, beats a button
  /// that fails every time it is pressed.
  Future<void> _checkEngine() async {
    final ready = await _engine.isAvailable();
    if (mounted) setState(() => _engineReady = ready);
  }

  @override
  void dispose() {
    _editor.removeListener(_onEdited);
    _editor.dispose();
    super.dispose();
  }

  Future<void> _openRelative(String relative) async {
    if (_dirty) await _save();
    final file = File(_project.absolute(relative));
    final text = file.existsSync() ? await file.readAsString() : '';
    if (!mounted) return;
    _loadingFile = true;
    setState(() {
      _openFile = relative;
      _editor.text = text;
      _dirty = false;
    });
    _loadingFile = false;
    await _rescanProject();
  }

  /// Rebuilds the completion lists from the project's own files.
  ///
  /// These are the completions worth having: nobody misremembers `\section`,
  /// everybody misremembers whether the figure was `fig:overview` or
  /// `fig:overview-2`.
  Future<void> _rescanProject() async {
    final labels = <String>{};
    final keys = <String>{};
    for (final relative in _project.files) {
      final ext = p.extension(relative);
      if (ext != '.tex' && ext != '.bib') continue;
      try {
        final text = await File(_project.absolute(relative)).readAsString();
        if (ext == '.tex') {
          labels.addAll(scanLabels(text));
        } else {
          keys.addAll(scanCitationKeys(text));
        }
      } on FileSystemException {
        continue;
      }
    }
    if (!mounted) return;

    // Only the packages this document loads are read, so the list stays the
    // relevant one rather than everything TeX Live could offer.
    final packageCommands = await _cwl.forDocument(_editor.text);
    if (!mounted) return;

    setState(() {
      _autocomplete = LatexAutocomplete(
        labels: labels.toList()..sort(),
        citationKeys: keys.toList()..sort(),
        packageCommands: packageCommands,
      );
      _dangling = findDanglingReferences(_editor.text, labels);
    });
  }

  /// Opens the grid editor and writes the LaTeX at the caret.
  Future<void> _insertTable() async {
    final latex = await showTableEditor(context);
    if (latex == null || !mounted) return;
    final text = _editor.text;
    final at = _insertionPoint(text);
    _editor.value = TextEditingValue(
      text: text.replaceRange(at, at, '$latex\n'),
      selection: TextSelection.collapsed(offset: at + latex.length + 1),
    );
  }

  /// Where an inserted block should land.
  ///
  /// Anything after `\end{document}` is ignored by LaTeX, so inserting there
  /// produces a table that silently never appears. When the caret is outside
  /// the body — which it is whenever the editor has not been clicked into —
  /// the insertion moves to just before the end instead.
  int _insertionPoint(String text) {
    final selection = _editor.selection;
    final caret = selection.isValid ? selection.baseOffset : text.length;
    final end = text.lastIndexOf(r'\end{document}');
    if (end < 0 || caret <= end) return caret;
    return end;
  }

  Future<void> _openGit() async {
    await showGitPanel(context, directory: _project.directory, backend: _git);
  }

  Future<void> _save() async {
    final relative = _openFile;
    if (relative == null) return;
    await File(_project.absolute(relative)).writeAsString(_editor.text);
    if (mounted) setState(() => _dirty = false);
  }

  Future<void> _compile() async {
    if (_compiling) return;
    await _save();
    setState(() => _compiling = true);
    try {
      final result = await _engine.compile(
        projectDir: _project.directory,
        mainFile: _project.mainFile,
      );
      if (!mounted) return;
      setState(() => _result = result);
      // Reopening the PDF resets the view, so the page is restored.
      if (result.ok && _pdfPage > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (_pdf.isReady && _pdfPage <= _pdf.pages.length) {
          await _pdf.goToPage(pageNumber: _pdfPage);
        }
      }
    } finally {
      if (mounted) setState(() => _compiling = false);
    }
    await _rescanProject();
  }

  @override
  Widget build(BuildContext context) {
    final layout = LayoutSize.of(context);
    final scheme = Theme.of(context).colorScheme;
    final errors = _result?.errors ?? const <LatexMessage>[];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_project.name, style: Theme.of(context).textTheme.titleSmall),
            Text(
              '${_openFile ?? '—'}${_dirty ? ' •' : ''} · utama: ${_project.mainFile}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: <Widget>[
          if (_compiling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Simpan (Ctrl+S)',
              icon: const Icon(Icons.save_outlined),
              onPressed: _dirty ? _save : null,
            ),
          IconButton(
            tooltip: 'Sisipkan tabel',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: _insertTable,
          ),
          IconButton(tooltip: 'Git', icon: const Icon(Icons.commit_outlined), onPressed: _openGit),
          FilledButton.tonalIcon(
            onPressed: (_compiling || _engineReady == false) ? null : _compile,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Kompilasi'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: layout.treeInDrawer ? Drawer(child: SafeArea(child: _fileTree())) : null,
      body: Column(
        children: <Widget>[
          if (_engineReady == false) _noEngineBar(scheme),
          if (_dangling.isNotEmpty) _danglingBar(scheme),
          if (errors.isNotEmpty) _errorBar(errors, scheme),
          Expanded(
            child: Row(
              children: <Widget>[
                if (!layout.treeInDrawer) ...<Widget>[
                  SizedBox(width: 240, child: _fileTree()),
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  flex: 5,
                  child: LatexEditor(
                    controller: _editor,
                    autocomplete: _autocomplete,
                    showKeyRow: isTouchPlatform,
                    onSave: _save,
                  ),
                ),
                if (layout.showsSourceAndPdf) ...<Widget>[
                  const VerticalDivider(width: 1),
                  Expanded(flex: 4, child: _preview(scheme)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noEngineBar(ColorScheme scheme) => Material(
    color: scheme.tertiaryContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Platform.isAndroid
                  ? 'Belum bisa mengompilasi di Android: mesin Tectonic belum '
                        'dibundel. Menulis, menyimpan, dan membuka proyek tetap jalan.'
                  : _engine.unavailableReason,
              style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 12.5),
            ),
          ),
        ],
      ),
    ),
  );

  /// Warns about references that will come out as `??` in the PDF.
  ///
  /// LaTeX does not fail on these; it prints `??` and carries on, which is
  /// easy to miss until a reader finds it.
  Widget _danglingBar(ColorScheme scheme) => Material(
    color: scheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.link_off, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _dangling.length == 1
                  ? 'Rujukan ke label yang tidak ada: '
                        '${_dangling.single.key} (baris ${_dangling.single.line})'
                  : '${_dangling.length} rujukan ke label yang tidak ada: '
                        '${_dangling.take(3).map((d) => d.key).join(', ')}'
                        '${_dangling.length > 3 ? ', …' : ''}',
              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12.5),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorBar(List<LatexMessage> errors, ColorScheme scheme) => Material(
    color: scheme.errorContainer,
    child: SizedBox(
      height: 64,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: errors.length,
        itemBuilder: (context, i) {
          final e = errors[i];
          return Text(
            '${e.line == null ? '' : 'baris ${e.line}: '}${e.text}',
            style: TextStyle(color: scheme.onErrorContainer, fontSize: 12.5),
          );
        },
      ),
    ),
  );

  Widget _fileTree() => ListView(
    children: <Widget>[
      for (final relative in _project.files)
        SizedBox(
          height: treeRowHeight,
          child: ListTile(
            dense: true,
            selected: relative == _openFile,
            leading: Icon(
              p.extension(relative) == '.tex'
                  ? Icons.description_outlined
                  : p.extension(relative) == '.bib'
                  ? Icons.menu_book_outlined
                  : Icons.insert_drive_file_outlined,
              size: 18,
            ),
            title: Text(relative, style: const TextStyle(fontSize: 12.5)),
            onTap: () => _openRelative(relative),
          ),
        ),
    ],
  );

  Widget _preview(ColorScheme scheme) {
    final pdfPath = _result?.pdfPath;
    if (pdfPath == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _engineReady == false
                ? 'Pratinjau menunggu mesin kompilasi.'
                : _result == null
                ? 'Tekan Kompilasi untuk melihat hasilnya.'
                : 'Kompilasi gagal. Pesan errornya ada di atas.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return PdfViewer.file(
      pdfPath,
      controller: _pdf,
      // The file is rewritten in place on every compile, so the viewer has to
      // be told to reload rather than keep the pages it already has.
      key: ValueKey<String>('$pdfPath-${_result!.duration.inMicroseconds}'),
      params: PdfViewerParams(
        backgroundColor: scheme.surfaceContainerHighest,
        margin: 8,
        onPageChanged: (n) {
          if (n != null) _pdfPage = n;
        },
      ),
    );
  }
}
