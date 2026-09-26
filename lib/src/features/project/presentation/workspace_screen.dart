import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../core/utils/layout_size.dart';
import '../../compile/data/latexmk_engine.dart';
import '../../compile/data/tectonic_engine.dart';
import '../../compile/domain/latex_engine.dart';
import '../../editor/data/cwl_repository.dart';
import '../../editor/domain/autocomplete.dart';
import '../../editor/presentation/latex_editor.dart';
import '../../git/data/git_cli_backend.dart';
import '../../git/data/git_ffi_backend.dart';
import '../../git/domain/git_backend.dart';
import '../../git/presentation/git_panel.dart';
import '../../table/presentation/table_editor_sheet.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import '../data/workspace_store.dart';
import '../domain/latex_project.dart';
import '../domain/project_files.dart';
import '../domain/project_profile.dart';
import 'add_file_sheet.dart';
import 'project_switcher.dart';

/// Everything at once: files on the left, source in the middle, PDF on the
/// right — as much of it as the window can hold.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    required this.project,
    required this.profile,
    required this.store,
    super.key,
  });

  final LatexProject project;

  /// Proyek mana ini, dan ke repositori mana isinya dikirim.
  final ProjectProfile profile;
  final WorkspaceStore store;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final TextEditingController _editor = TextEditingController();
  final PdfViewerController _pdf = PdfViewerController();

  /// Tectonic di Android karena tidak ada TeX Live di sana; latexmk di
  /// desktop karena membundel salinan kedua TeX Live akan sia-sia.
  final LatexEngine _engine = Platform.isAndroid || Platform.isIOS
      ? const TectonicEngine()
      : const LatexmkEngine();

  /// libgit2 di Android karena tidak ada biner git di sana; biner git di
  /// desktop karena sudah terpasang dan sudah tahu kredensial penggunanya.
  ///
  /// Dibuat setiap kali dipakai, bukan sekali di awal: tokennya bisa berubah
  /// saat pengguna menyuntingnya, dan backend yang masih memegang token lama
  /// akan gagal tanpa alasan yang kelihatan.
  GitBackend get _git => Platform.isAndroid || Platform.isIOS
      ? GitFfiBackend(
          token: _token,
          username: _profile.httpsUsername,
          authorName: _profile.authorName,
          authorEmail: _profile.authorEmail,
        )
      : GitCliBackend(token: _token, username: _profile.httpsUsername);

  LatexProject _project = const LatexProject(directory: '', mainFile: '', files: <String>[]);
  late ProjectProfile _profile = widget.profile;

  /// Token repositori proyek ini, kalau ada.
  String? _token;

  /// True while a file is being put into the editor, so filling it does not
  /// count as the user typing.
  bool _loadingFile = false;

  /// Recompile by itself once typing pauses.
  bool _autoCompile = false;
  Timer? _autoTimer;

  /// Null until checked; false means there is no engine on this platform.
  bool? _engineReady;
  String? _openFile;
  bool _dirty = false;
  bool _compiling = false;
  CompileResult? _result;

  /// Apa yang sedang dikerjakan mesin, ditampilkan selama kompilasi.
  String _progress = '';
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
    _project = _withChosenMain(widget.project, widget.profile);
    _editor.addListener(_onEdited);
    _openRelative(_project.mainFile);
    _checkEngine();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await widget.store.tokenFor(_profile.id);
    if (mounted) setState(() => _token = token);
  }

  /// Berpindah proyek tanpa meninggalkan ruang kerja.
  Future<void> _switchProject() async {
    final result = await showProjectSwitcher(context, store: widget.store, currentId: _profile.id);
    if (result == null || !mounted) return;

    switch (result) {
      case OpenSomethingElse():
        Navigator.of(context).pop();
      case SwitchTo(:final profile):
        if (_dirty) await _save();
        final project = _withChosenMain(await LatexProject.open(profile.directory), profile);
        await widget.store.remember(profile.directory);
        if (!mounted) return;
        setState(() {
          _profile = profile;
          _project = project;
          // Hasil kompilasi proyek sebelumnya tidak berlaku di sini, dan
          // memperlihatkannya sebagai pratinjau proyek baru akan menyesatkan.
          _result = null;
          _dangling = const <DanglingReference>[];
          _pdfPage = 1;
          _token = null;
        });
        await _openRelative(project.mainFile);
        await _loadToken();
    }
  }

  // ------------------------------------------------------- menambah berkas

  /// Menambahkan berkas ke proyek: buat baru, atau ambil dari perangkat.
  Future<void> _addFile() async {
    final request = await showAddFileSheet(context);
    if (request == null || !mounted) return;
    switch (request) {
      case CreateFile(:final kind, :final name):
        await _createFile(kind, name);
      case ImportFiles(:final graphicsOnly):
        await _importFiles(graphicsOnly: graphicsOnly);
    }
  }

  Future<void> _createFile(NewFileKind kind, String name) async {
    final file = File(_project.absolute(name));
    if (file.existsSync()) {
      _say('$name sudah ada');
      // Berkas yang sudah ada tetap dibuka: itu yang dimaui orang yang
      // mengetikkan namanya lagi.
      await _reloadProject();
      await _openRelative(name);
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(starterContent(kind, name));
    await _wireUp(kind, name);
    await _reloadProject();
    await _openRelative(name);
    _say('$name dibuat');
  }

  /// Menyalin berkas dari perangkat ke dalam folder proyek.
  ///
  /// Disalin, bukan dirujuk: di Android pemilih berkas menyerahkan salinan di
  /// cache yang bisa hilang kapan saja, dan berkas di luar folder proyek tidak
  /// akan ikut saat proyeknya diarsipkan atau dikirim ke git.
  Future<void> _importFiles({required bool graphicsOnly}) async {
    final picked = await FilePicker.pickFiles(
      type: graphicsOnly ? FileType.image : FileType.any,
      dialogTitle: graphicsOnly ? 'Pilih gambar' : 'Pilih berkas',
    );
    if (picked.isEmpty || !mounted) return;

    final added = <String>[];
    final failed = <String>[];
    for (final file in picked) {
      final source = file.path;
      if (source == null) {
        failed.add(file.name);
        continue;
      }
      final graphic = isGraphic(file.name);
      final dir = preferredAssetDir(_project.files, graphic: graphic);
      final relative = _freeName(p.join(dir, sanitiseFileName(file.name)));
      final target = File(_project.absolute(relative));
      await target.parent.create(recursive: true);
      try {
        await File(source).copy(target.path);
        added.add(relative);
      } on FileSystemException {
        failed.add(file.name);
      }
    }

    for (final relative in added) {
      if (isGraphic(relative)) {
        await _insertFigure(relative);
      } else if (kindForExtension(relative) case final kind?) {
        await _wireUp(kind, relative);
      }
    }
    await _reloadProject();

    _say(
      <String>[
        if (added.isNotEmpty) '${added.length} berkas ditambahkan',
        if (failed.isNotEmpty) '${failed.length} gagal disalin',
      ].join(' · '),
    );
  }

  /// Nama yang belum terpakai, dengan angka di belakang kalau perlu.
  String _freeName(String relative) {
    if (!File(_project.absolute(relative)).existsSync()) return relative;
    final dir = p.dirname(relative);
    final stem = p.basenameWithoutExtension(relative);
    final ext = p.extension(relative);
    for (var n = 2; n < 500; n++) {
      final candidate = p.join(dir, '$stem-$n$ext');
      if (!File(_project.absolute(candidate)).existsSync()) return candidate;
    }
    return relative;
  }

  /// Menyambungkan berkas baru ke berkas utama, supaya benar-benar terpakai.
  ///
  /// Berkas `.tex` yang tidak pernah di-`\input` dan `.bib` yang tidak pernah
  /// disebut adalah keluhan yang paling sering muncul dari editor LaTeX mana
  /// pun: berkasnya terlihat di daftar, tetapi tidak muncul di PDF.
  Future<void> _wireUp(NewFileKind kind, String relative) async {
    // Berkas pertama di proyek kosong menjadi berkas utamanya sendiri, dan
    // sebuah dokumen yang meng-`\input` dirinya sendiri adalah rekursi yang
    // membuat LaTeX berputar sampai kehabisan memori.
    if (relative == _project.mainFile) return;

    final mainPath = _project.absolute(_project.mainFile);
    final mainOpen = _openFile == _project.mainFile;
    if (mainOpen && _dirty) await _save();

    final file = File(mainPath);
    if (!file.existsSync()) return;
    final before = await file.readAsString();
    final biblatex = usesBiblatex(before);

    var after = before;
    if (preambleLineFor(kind, relative, usesBiblatex: biblatex) case final line?) {
      after = insertOnce(after, line, preamble: true);
    }
    if (bodyLineFor(kind, relative, usesBiblatex: biblatex) case final line?) {
      after = insertOnce(after, line, preamble: false);
    }
    if (after == before) return;

    await file.writeAsString(after);
    if (mainOpen) await _openRelative(_project.mainFile);
  }

  /// Menyisipkan `figure` di tempat kursor, atau di berkas utama.
  Future<void> _insertFigure(String relative) async {
    final mainPath = _project.absolute(_project.mainFile);
    final source = File(mainPath).existsSync() ? await File(mainPath).readAsString() : '';
    // graphicx harus ada di preamble, atau `\includegraphics` tidak dikenal.
    if (source.isNotEmpty && !source.contains('{graphicx}')) {
      await File(
        mainPath,
      ).writeAsString(insertOnce(source, '\\usepackage{graphicx}', preamble: true));
      if (_openFile == _project.mainFile) await _openRelative(_project.mainFile);
    }

    final snippet = figureSnippet(relative);
    if (_openFile != null && p.extension(_openFile!) == '.tex') {
      final text = _editor.text;
      final at = _insertionPoint(text);
      _editor.value = TextEditingValue(
        text: text.replaceRange(at, at, '$snippet\n'),
        selection: TextSelection.collapsed(offset: at + snippet.length),
      );
      return;
    }
    // Tidak ada berkas .tex yang terbuka: gambarnya tetap harus muncul di
    // suatu tempat, dan berkas utama adalah satu-satunya taruhan yang masuk
    // akal.
    final main = File(mainPath);
    if (!main.existsSync()) return;
    final text = await main.readAsString();
    final at = bodyInsertionPoint(text);
    await main.writeAsString(text.replaceRange(at, at, '$snippet\n'));
  }

  /// Memuat ulang daftar berkas proyek dari disk.
  Future<void> _reloadProject() async {
    final project = _withChosenMain(await LatexProject.open(_project.directory), _profile);
    if (mounted) setState(() => _project = project);
  }

  /// Menghormati berkas utama yang dipilih sendiri oleh pengguna.
  static LatexProject _withChosenMain(LatexProject project, ProjectProfile profile) {
    final chosen = profile.mainFile;
    if (chosen.isEmpty || !project.files.contains(chosen)) return project;
    return project.copyWith(mainFile: chosen);
  }

  /// Menjadikan sebuah berkas sebagai yang dikompilasi.
  Future<void> _setMainFile(String relative) async {
    final saved = await widget.store.update(_profile.copyWith(mainFile: relative));
    if (!mounted) return;
    setState(() {
      _profile = saved;
      _project = _project.copyWith(mainFile: relative);
      // Hasil lama milik berkas utama sebelumnya, jadi tidak lagi berlaku.
      _result = null;
    });
    _say('$relative jadi berkas utama');
  }

  /// Marks the file as changed.
  ///
  /// Without this the save button stayed disabled forever and the modified
  /// dot never appeared, so the only way to save was to compile.
  void _onEdited() {
    if (_loadingFile) return;
    if (!_dirty) setState(() => _dirty = true);
    if (_autoCompile) _scheduleAutoCompile();
  }

  /// Mengompilasi ulang setelah mengetik berhenti sejenak.
  ///
  /// Bukan pada setiap ketikan: satu kompilasi makan beberapa detik, dan
  /// menjalankannya per huruf berarti antrean yang tidak pernah habis. Dua
  /// detik cukup untuk menandai "sudah selesai mengetik" tanpa terasa lambat.
  void _scheduleAutoCompile() {
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_compiling) _compile();
    });
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
    _autoTimer?.cancel();
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

  /// Menyimpan PDF hasil kompilasi ke tempat yang dipilih pengguna.
  Future<void> _savePdf() async {
    final pdf = _result?.pdfPath;
    if (pdf == null) {
      _say('Belum ada PDF. Tekan Kompilasi dulu.');
      return;
    }
    final uri = await FilePicker.saveFile(
      fileName: '${_project.name}.pdf',
      bytes: await File(pdf).readAsBytes(),
      mimeType: 'application/pdf',
      dialogTitle: 'Simpan PDF',
    );
    _say(uri == null ? 'Tidak jadi disimpan' : 'PDF disimpan');
  }

  /// Membungkus seluruh proyek jadi satu ZIP.
  ///
  /// Keluaran build sengaja tidak ikut: penerima arsip ini menginginkan
  /// sumbernya, bukan PDF hasil kompilasi mesin orang lain.
  Future<void> _exportZip() async {
    await _save();
    final archive = Archive();
    final root = Directory(_project.directory);
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: root.path);
      if (p.split(relative).any((s) => s.startsWith('.'))) continue;
      if (isGeneratedFile(relative)) continue;
      final bytes = entity.readAsBytesSync();
      archive.add(ArchiveFile(relative, bytes.length, bytes));
    }

    final bytes = ZipEncoder().encode(archive);
    if (bytes.isEmpty) {
      _say('Tidak ada berkas untuk diarsipkan');
      return;
    }
    final uri = await FilePicker.saveFile(
      fileName: '${_project.name}.zip',
      bytes: Uint8List.fromList(bytes),
      mimeType: 'application/zip',
      dialogTitle: 'Ekspor proyek',
    );
    _say(uri == null ? 'Tidak jadi diekspor' : 'Proyek diekspor (${archive.length} berkas)');
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(duration: const Duration(seconds: 3), content: Text(message)));
  }

  Future<void> _openGit() async {
    await _save();

    // Folder yang belum jadi repositori sebentar lagi akan di-`init` dari
    // panel ini, dan commit pertamanya jangan sampai membawa berkas keluaran.
    // Repositori yang sudah ada tidak disentuh: aturan abaikannya milik
    // pemiliknya, bukan milik aplikasi ini.
    final ignore = File(_project.absolute('.gitignore'));
    if (!ignore.existsSync() && !await _git.isRepository(_project.directory)) {
      await ignore.writeAsString(latexGitignore);
      await _reloadProject();
    }

    if (!mounted) return;
    await showGitPanel(
      context,
      directory: _project.directory,
      backend: _git,
      // Alamat yang tercatat di profil ditawarkan lebih dulu, supaya folder
      // yang belum jadi repositori tidak perlu mengetiknya ulang.
      suggestedRemote: _profile.remoteUrl,
      branch: _profile.branch,
      authorName: _profile.authorName,
      authorEmail: _profile.authorEmail,
      // Identitas kosong berarti commit-nya atas nama aplikasi; panelnya
      // menawarkan jalan ke tempat mengisinya, bukan sekadar mengeluh.
      onEditIdentity: _editIdentity,
      onRemoteSet: (url) async {
        final updated = await widget.store.update(_profile.copyWith(remoteUrl: url));
        if (mounted) setState(() => _profile = updated);
      },
    );

    // Menarik perubahan bisa membawa berkas baru dan mengubah yang terbuka.
    // Tanpa muat ulang, daftar berkasnya masih memperlihatkan keadaan sebelum
    // ditarik, dan orang menyangka tarikannya tidak berhasil.
    if (!mounted) return;
    await _reloadProject();
    final open = _openFile;
    if (open != null && !_dirty) {
      final file = File(_project.absolute(open));
      // Berkas yang sedang dibuka bisa saja terhapus oleh tarikan itu.
      if (!file.existsSync()) {
        await _openRelative(_project.mainFile);
      } else {
        final text = await file.readAsString();
        if (mounted && text != _editor.text) {
          _loadingFile = true;
          setState(() => _editor.text = text);
          _loadingFile = false;
        }
      }
    }
  }

  /// Membuka penyunting alamat, token, dan identitas proyek ini.
  Future<({String name, String email})?> _editIdentity() async {
    final token = await widget.store.tokenFor(_profile.id);
    if (!mounted) return null;
    final result = await showRemoteEditor(context, profile: _profile, token: token);
    if (result == null) return null;
    final saved = await widget.store.update(result.profile);
    await widget.store.saveToken(_profile.id, result.token);
    if (mounted) {
      setState(() {
        _profile = saved;
        _token = result.token;
      });
    }
    return (name: saved.authorName, email: saved.authorEmail);
  }

  Future<void> _save() async {
    final relative = _openFile;
    if (relative == null) return;
    // Tanpa jaga-jaga ini, membuka panel git pada proyek yang masih kosong
    // menuliskan berkas utama yang kosong ke disk — lalu git melaporkannya
    // sebagai berkas baru yang tidak pernah dibuat siapa pun.
    if (!_dirty) return;
    await File(_project.absolute(relative)).writeAsString(_editor.text);
    if (mounted) setState(() => _dirty = false);
  }

  Future<void> _compile() async {
    if (_compiling) return;
    await _save();
    setState(() {
      _compiling = true;
      _progress = 'Menyiapkan…';
    });
    try {
      final result = await _engine.compile(
        projectDir: _project.directory,
        mainFile: _project.mainFile,
        onOutput: (line) {
          final text = line.trim();
          if (text.isNotEmpty && mounted) setState(() => _progress = text);
        },
      );
      if (!mounted) return;
      setState(() => _result = result);
      if (result.ok) await _publishPdf(result);
      // Reopening the PDF resets the view, so the page is restored.
      if (result.ok && _pdfPage > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (_pdf.isReady && _pdfPage <= _pdf.pages.length) {
          await _pdf.goToPage(pageNumber: _pdfPage);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _compiling = false;
          _progress = '';
        });
      }
    }
    await _rescanProject();
  }

  /// Menyalin PDF hasil kompilasi ke folder proyek.
  ///
  /// Kompilasinya menulis ke `.writepapertex/`, yang mengabaikan dirinya
  /// sendiri di git — jadi tanpa salinan ini PDF-nya tidak pernah ikut
  /// ter-push, dan yang membuka repositori tanpa TeX tidak menemukan apa pun
  /// yang bisa dibaca.
  Future<void> _publishPdf(CompileResult result) async {
    final source = result.pdfPath;
    if (source == null || !File(source).existsSync()) return;
    final target = _project.absolute('${p.basenameWithoutExtension(_project.mainFile)}.pdf');
    if (p.equals(source, target)) return;
    try {
      await File(source).copy(target);
    } on FileSystemException {
      // Gagal menyalin bukan alasan untuk membatalkan kompilasi yang berhasil.
      return;
    }
    await _reloadProject();
  }

  @override
  Widget build(BuildContext context) {
    final layout = LayoutSize.of(context);
    final scheme = Theme.of(context).colorScheme;
    final errors = _result?.errors ?? const <LatexMessage>[];

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _switchProject,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(_project.name, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more, size: 16),
                  ],
                ),
                Text(
                  <String>[
                    '${_openFile ?? '—'}${_dirty ? ' •' : ''}',
                    'utama: ${_project.mainFile}',
                    // Waktu kompilasi ditampilkan supaya "lama" bisa diukur, bukan
                    // hanya dirasakan: kompilasi pertama mengunduh paket TeX dan
                    // memang lama, sesudahnya seharusnya beberapa detik saja.
                    if (_result != null) 'kompilasi ${_formatDuration(_result!.duration)}',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
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
          IconButton(
            tooltip: _autoCompile
                ? 'Kompilasi otomatis: hidup'
                : 'Kompilasi otomatis saat mengetik berhenti',
            isSelected: _autoCompile,
            selectedIcon: const Icon(Icons.autorenew),
            icon: const Icon(Icons.autorenew_outlined),
            onPressed: () {
              setState(() => _autoCompile = !_autoCompile);
              if (_autoCompile) _scheduleAutoCompile();
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Simpan dan bagikan',
            icon: const Icon(Icons.ios_share),
            onSelected: (choice) => switch (choice) {
              'simpan' => _save(),
              'pdf' => _savePdf(),
              _ => _exportZip(),
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'simpan',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.save_outlined),
                  title: Text('Simpan berkas'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'pdf',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Simpan PDF…'),
                  subtitle: Text('hasil kompilasi terakhir'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'zip',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.folder_zip_outlined),
                  title: Text('Ekspor proyek sebagai ZIP'),
                  subtitle: Text('tanpa berkas hasil build'),
                ),
              ),
            ],
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
          if (_compiling && _progress.isNotEmpty) _progressBar(scheme),
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

  /// Mengatakan apa yang sedang dikerjakan selama kompilasi.
  ///
  /// Spinner yang diam selama dua menit tidak bisa dibedakan dari aplikasi
  /// yang menggantung — dan itulah yang dilaporkan terjadi pada versi
  /// sebelumnya.
  Widget _progressBar(ColorScheme scheme) => Material(
    color: scheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _progress,
              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12.5),
            ),
          ),
        ],
      ),
    ),
  );

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
              _engine.unavailableReason,
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

  static String _formatDuration(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds} md';
    if (d.inSeconds < 60) return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} dtk';
    return '${d.inMinutes} mnt ${d.inSeconds % 60} dtk';
  }

  Widget _errorBar(List<LatexMessage> errors, ColorScheme scheme) => Material(
    color: scheme.errorContainer,
    child: SizedBox(
      // Pesan Tectonic bisa beberapa baris; 64 piksel hanya memperlihatkan
      // barisnya yang pertama dan menyembunyikan sebabnya.
      height: 110,
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

  Widget _fileTree() => Column(
    children: <Widget>[
      // Menambah berkas duduk di kepala daftar berkas, tempat orang mencarinya.
      ListTile(
        dense: true,
        leading: const Icon(Icons.add, size: 18),
        title: const Text('Tambah berkas', style: TextStyle(fontSize: 12.5)),
        onTap: _addFile,
      ),
      const Divider(height: 1),
      Expanded(child: _fileList()),
    ],
  );

  Widget _fileList() => ListView(
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
            title: Text(
              relative,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: relative == _project.mainFile ? FontWeight.w700 : null,
              ),
            ),
            // Tekan lama untuk memilih berkas utama: tebakannya benar hampir
            // selalu, dan saat salah orang butuh jalan yang tidak berbelit.
            onLongPress: p.extension(relative) == '.tex' && relative != _project.mainFile
                ? () => _setMainFile(relative)
                : null,
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
