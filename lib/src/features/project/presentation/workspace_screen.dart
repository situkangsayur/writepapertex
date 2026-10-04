import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../core/utils/layout_size.dart';
import '../../compile/data/latexmk_engine.dart';
import '../../compile/data/tectonic_engine.dart';
import '../../compile/domain/latex_engine.dart';
import '../../compile/domain/source_stamp.dart';
import '../../editor/data/cwl_repository.dart';
import '../../editor/domain/autocomplete.dart';
import '../../editor/domain/latex_syntax.dart';
import '../../editor/presentation/highlighting_controller.dart';
import '../../editor/presentation/latex_editor.dart';
import '../../editor/presentation/syntax_palette.dart';
import '../../git/data/git_cli_backend.dart';
import '../../git/data/git_ffi_backend.dart';
import '../../git/domain/git_backend.dart';
import '../../git/presentation/git_panel.dart';
import '../../table/presentation/table_editor_sheet.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import '../data/workspace_store.dart';
import '../domain/file_tree.dart';
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
  final LatexHighlightingController _editor = LatexHighlightingController();

  /// Fokus penyunting, supaya mengetuk pesan kompilasi bisa membawa kursor ke
  /// barisnya dan membuatnya terlihat.
  final FocusNode _editorFocus = FocusNode();

  /// Daftar peringatan dibuka. Bawaannya terlipat: peringatan penataan huruf
  /// tidak menggagalkan apa pun, dan sebuah disertasi bisa punya puluhan.
  bool _warningsOpen = false;
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

  /// Kapan kompilasi yang sedang berjalan dimulai, untuk menghitung waktunya.
  DateTime? _compileStarted;
  Timer? _ticker;

  /// Bertambah setiap kali kompilasi dibatalkan, supaya hasil dari kompilasi
  /// yang sudah ditinggalkan tidak mendarat di layar.
  int _compileRun = 0;
  LatexAutocomplete _autocomplete = const LatexAutocomplete();
  late final CwlRepository _cwl = CwlRepository(projectDir: _project.directory);

  /// `\ref` keys nothing in the project defines.
  List<DanglingReference> _dangling = const <DanglingReference>[];

  /// Folder yang sedang terbuka di pohon berkas.
  final Set<String> _expanded = <String>{};

  /// Berapa bagian lebar yang diberikan ke penyunting, sisanya ke pratinjau.
  ///
  /// Menulis tabel butuh kode yang lebar; memeriksa hasil butuh halaman yang
  /// lebar. Perbandingan tetap memaksa memilih salah satu untuk selamanya.
  double _split = 0.55;

  /// Kept across rebuilds so a recompile does not throw the writer back to
  /// page one — which is what makes an iterative document unbearable.
  int _pdfPage = 1;

  /// PDF yang sudah ada di proyek saat dibuka, sebelum kompilasi apa pun.
  ///
  /// Sebuah proyek yang baru di-clone membawa PDF-nya sendiri, dan yang ingin
  /// dilakukan orang pertama kali biasanya membacanya — bukan menunggu satu
  /// setengah menit untuk mendapatkan berkas yang sudah ada di folder.
  String? _openedPdf;

  @override
  void initState() {
    super.initState();
    _project = _withChosenMain(widget.project, widget.profile);
    _openedPdf = SourceStamp.existingPdf(
      projectDir: _project.directory,
      mainFile: _project.mainFile,
    );
    _editor.addListener(_onEdited);
    _openRelative(_project.mainFile);
    _checkEngine();
    _loadToken();
    _loadPalette();
    _loadSplit();
  }

  /// Memuat palet warna yang dipilih terakhir kali.
  Future<void> _loadPalette() async {
    final id = await widget.store.paletteId();
    if (id != null && mounted) setState(() => _editor.palette = SyntaxPalette.byId(id));
  }

  Future<void> _loadSplit() async {
    final saved = await widget.store.splitRatio();
    if (saved != null && mounted) setState(() => _split = saved);
  }

  /// Memperlihatkan cap waktu tiap langkah kompilasi terakhir.
  ///
  /// "Kompilasinya lama" adalah keluhan yang tidak bisa ditindaklanjuti sampai
  /// terlihat langkah mana yang lama — menyiapkan bundel, memuat format, atau
  /// LaTeX-nya sendiri. Ketiganya punya jalan keluar yang berbeda.
  Future<void> _showTimeline() async {
    final log = _result?.log ?? '';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Waktu kompilasi terakhir'),
        content: SizedBox(
          width: 520,
          child: log.trim().isEmpty
              ? const Text('Belum ada kompilasi di sesi ini.')
              : SingleChildScrollView(
                  child: SelectableText(
                    log,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup')),
        ],
      ),
    );
  }

  /// Memperlihatkan berapa paket yang sudah tersimpan.
  ///
  /// Pertanyaannya wajar — "yang sudah diunduh, apakah benar tidak diunduh
  /// lagi?" — dan jawabannya pantas berupa angka, bukan janji.
  Future<void> _showCacheInfo() async {
    final info = await TectonicEngine.cacheInfo();
    if (!mounted) return;
    final mb = (info.bytes / (1024 * 1024)).toStringAsFixed(1);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paket TeX tersimpan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${info.files} berkas · $mb MB'),
            const SizedBox(height: 10),
            const Text(
              'Dipakai bersama semua proyek di aplikasi ini. Paket yang sudah '
              'ada tidak pernah diunduh lagi, dan daftarnya bertambah sendiri '
              'setiap kali sebuah dokumen memerlukan yang belum ada.',
            ),
            const SizedBox(height: 10),
            Text(
              'Pembaruan aplikasi hanya menambahkan paket yang belum ada; '
              'yang sudah tersimpan tidak disentuh.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup')),
        ],
      ),
    );
  }

  /// Mengunduh paket dan font yang dibutuhkan dokumen ini, sekali saja.
  ///
  /// Paketnya dipakai bersama semua proyek — yang diunduh untuk proposal
  /// dipakai lagi oleh artikel berikutnya — jadi ini menyakitkan sekali lalu
  /// tidak pernah lagi.
  Future<void> _fetchDependencies() async {
    _say('Mengunduh paket yang dibutuhkan dokumen ini…');
    await _compile(pass: CompilePass.full);
    if (mounted && (_result?.ok ?? false)) {
      _say('Paketnya sudah tersimpan dan dipakai bersama proyek lain.');
    }
  }

  /// Memilih palet warna editor.
  Future<void> _pickPalette() async {
    final chosen = await showModalBottomSheet<SyntaxPalette>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: <Widget>[
            Text('Warna editor', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final palette in SyntaxPalette.all)
              ListTile(
                leading: Icon(
                  palette.id == _editor.palette.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(palette.name),
                subtitle: Text(palette.description),
                // Contoh kecil: lebih cepat dipahami daripada namanya.
                trailing: Text(
                  r'\section',
                  style: styleFor(
                    SyntaxKind.sectioning,
                    palette,
                    Theme.of(context).brightness,
                  ).copyWith(fontFamily: 'monospace', fontSize: 13),
                ),
                onTap: () => Navigator.of(context).pop(palette),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _editor.palette = chosen);
    await widget.store.savePaletteId(chosen.id);
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
          _openedPdf = SourceStamp.existingPdf(
            projectDir: project.directory,
            mainFile: project.mainFile,
          );
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
      _openedPdf = SourceStamp.existingPdf(projectDir: _project.directory, mainFile: relative);
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
      // Kompilasi otomatis selalu lintasan cepat: ia berjalan sambil orang
      // mengetik, dan lintasan penuh akan membuat setiap jeda mengetik
      // berbuntut satu menit kerja mesin.
      if (mounted && !_compiling) _compile(pass: CompilePass.quick);
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
    _ticker?.cancel();
    _autoTimer?.cancel();
    _editor.removeListener(_onEdited);
    _editor.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  Future<void> _openRelative(String relative) async {
    if (_dirty) await _save();
    // Berkas yang dibuka harus terlihat di pohonnya, walau folder induknya
    // sedang tertutup.
    _expanded.addAll(ancestorsOf(relative));
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

  /// Menawarkan lintasan penuh saat log-nya memintanya.
  ///
  /// Tidak dijalankan sendiri: lintasan penuh enam kali lebih lama — satu
  /// menit berbanding sepuluh detik pada dokumen sebesar disertasi — dan yang
  /// baru mengubah satu paragraf biasanya tidak sedang menunggu nomor
  /// rujukannya. Yang pantas adalah memberi tahu, lalu membiarkan memilih.
  void _offerFullPass() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: const Text('Rujukan atau daftar pustakanya belum mantap.'),
          action: SnackBarAction(
            label: 'Jalankan lengkap',
            onPressed: () => _compile(pass: CompilePass.full, force: true),
          ),
        ),
      );
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

  /// Melepaskan kompilasi yang sedang berjalan dari layar.
  ///
  /// Mesinnya sendiri tidak bisa dihentikan di tengah jalan — ia kode asli
  /// yang sedang berjalan di isolate-nya sendiri — tetapi menunggu tanpa
  /// batas juga bukan pilihan yang pantas ditawarkan. Jadi hasilnya
  /// diabaikan dan ruang kerjanya bisa dipakai lagi.
  void _abandonCompile() {
    _compileRun++;
    _ticker?.cancel();
    setState(() {
      _compiling = false;
      _progress = '';
      _compileStarted = null;
    });
    _say('Kompilasi ditinggalkan. Mesinnya masih menyelesaikan di latar.');
  }

  /// [force] melewati pemeriksaan sidik sumber dan benar-benar menjalankan
  /// mesinnya. Dipakai saat hasilnya dicurigai, bukan saat menulis.
  Future<void> _compile({CompilePass? pass, bool force = false}) async {
    if (_compiling) return;
    await _save();
    // Tanpa keterangan berarti melihat: lintasan cepat.
    final wanted = pass ?? CompilePass.quick;

    // Tidak ada yang berubah sejak kompilasi terakhir berarti PDF di folder
    // sudah jawaban yang benar. Menjalankan mesinnya lagi akan menghasilkan
    // berkas yang identik setelah satu setengah menit.
    if (!force) {
      final ready = SourceStamp.reusablePdf(
        projectDir: _project.directory,
        mainFile: _project.mainFile,
        pass: wanted,
      );
      if (ready != null) {
        if (_result?.pdfPath != ready) {
          setState(() {
            _openedPdf = ready;
            _result = CompileResult(
              ok: true,
              log: 'Tidak ada yang berubah sejak kompilasi terakhir.',
              messages: const <LatexMessage>[],
              pdfPath: ready,
            );
          });
        }
        _say('Tidak ada yang berubah — PDF terakhir dipakai lagi.');
        return;
      }
    }

    final run = ++_compileRun;
    setState(() {
      _compiling = true;
      _progress = 'Menyiapkan…';
      _compileStarted = DateTime.now();
    });
    _ticker?.cancel();
    // Angka detik yang bergerak adalah tanda paling sederhana bahwa sesuatu
    // masih berjalan; spinner yang diam tidak membedakan apa pun.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _compiling) setState(() {});
    });
    try {
      final result = await _engine.compile(
        projectDir: _project.directory,
        mainFile: _project.mainFile,
        pass: wanted,
        onOutput: (line) {
          final text = line.trim();
          if (text.isNotEmpty && mounted && run == _compileRun) {
            setState(() => _progress = text);
          }
        },
      );
      if (!mounted || run != _compileRun) return;
      setState(() {
        _result = result;
        if (result.ok) _openedPdf = result.pdfPath;
      });
      if (result.ok && result.needsFullPass) _offerFullPass();
      if (result.ok) {
        await _publishPdf(result);
        // Dicatat setelah PDF-nya terbit: yang dicatat adalah keadaan sumber
        // yang benar-benar menghasilkan berkas ini.
        SourceStamp.remember(
          projectDir: _project.directory,
          mainFile: _project.mainFile,
          pass: wanted,
        );
      }
      // Reopening the PDF resets the view, so the page is restored.
      if (result.ok && _pdfPage > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (_pdf.isReady && _pdfPage <= _pdf.pages.length) {
          await _pdf.goToPage(pageNumber: _pdfPage);
        }
      }
    } finally {
      _ticker?.cancel();
      if (mounted && run == _compileRun) {
        setState(() {
          _compiling = false;
          _progress = '';
          _compileStarted = null;
        });
      }
    }
    if (run != _compileRun) return;
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
    final messages = _result?.messages ?? const <LatexMessage>[];

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
            tooltip: 'Warna editor',
            icon: const Icon(Icons.palette_outlined),
            onPressed: _pickPalette,
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
          // Dua tombol, dua maksud. "Lihat" untuk melihat paragraf yang baru
          // diubah: satu lintasan, PDF tidak dimampatkan, sekitar lima detik
          // pada disertasi. "Lengkap" untuk hasil yang dibagikan: daftar
          // pustaka, rujukan yang mantap, PDF yang kecil. Dulu keduanya satu
          // tombol yang caranya dipilih di menu, dan yang sedang menulis tidak
          // pernah ingat sedang di mode mana.
          FilledButton.tonalIcon(
            onPressed: (_compiling || _engineReady == false)
                ? null
                : () => _compile(pass: CompilePass.quick),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Lihat'),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Kompilasi lengkap: daftar pustaka, rujukan, PDF siap dibagikan',
            child: OutlinedButton.icon(
              onPressed: (_compiling || _engineReady == false)
                  ? null
                  : () => _compile(pass: CompilePass.full),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('Lengkap'),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Cara kompilasi',
            icon: const Icon(Icons.arrow_drop_down),
            onSelected: (choice) => switch (choice) {
              'paket' => _showCacheInfo(),
              'paksa' => _compile(pass: CompilePass.full, force: true),
              'waktu' => _showTimeline(),
              _ => _fetchDependencies(),
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'waktu',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.timer_outlined),
                  title: Text('Rincian waktu kompilasi'),
                  subtitle: Text('langkah mana yang memakan waktu'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'paksa',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh),
                  title: Text('Paksa kompilasi lengkap'),
                  subtitle: Text('walau sumbernya tidak berubah'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'unduh',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cloud_download_outlined),
                  title: Text('Unduh paket yang dibutuhkan'),
                  subtitle: Text('sekali saja, lalu dipakai bersama proyek lain'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'paket',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Paket yang tersimpan'),
                  subtitle: Text('berapa banyak, dan berapa besar'),
                ),
              ),
            ],
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
          if (messages.isNotEmpty) _messageBar(messages, scheme),
          Expanded(
            child: Row(
              children: <Widget>[
                if (!layout.treeInDrawer) ...<Widget>[
                  SizedBox(width: 240, child: _fileTree()),
                  const VerticalDivider(width: 1),
                ],
                if (!layout.showsSourceAndPdf)
                  Expanded(
                    child: LatexEditor(
                      controller: _editor,
                      focusNode: _editorFocus,
                      autocomplete: _autocomplete,
                      showKeyRow: isTouchPlatform,
                      onSave: _save,
                    ),
                  )
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final editorWidth = constraints.maxWidth * _split;
                        return Row(
                          children: <Widget>[
                            SizedBox(
                              width: editorWidth,
                              child: LatexEditor(
                                controller: _editor,
                                focusNode: _editorFocus,
                                autocomplete: _autocomplete,
                                showKeyRow: isTouchPlatform,
                                onSave: _save,
                              ),
                            ),
                            _SplitHandle(
                              onDrag: (dx) {
                                final ratio = (editorWidth + dx) / constraints.maxWidth;
                                setState(() => _split = ratio.clamp(0.2, 0.85));
                              },
                              onDone: () => widget.store.saveSplitRatio(_split),
                            ),
                            Expanded(child: _preview(scheme)),
                          ],
                        );
                      },
                    ),
                  ),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12.5),
            ),
          ),
          if (_compileStarted != null) ...<Widget>[
            const SizedBox(width: 10),
            Text(
              _elapsed(_compileStarted!),
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 12.5,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(width: 8),
          TextButton(
            onPressed: _abandonCompile,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSecondaryContainer,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Batal'),
          ),
        ],
      ),
    ),
  );

  /// Sudah berapa lama, dalam bentuk m:dd.
  static String _elapsed(DateTime since) {
    final seconds = DateTime.now().difference(since).inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
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

  /// Berkas proyek yang dimaksud sebuah pesan.
  ///
  /// Tectonic menulis nama berkas tanpa `.tex` (`bab/02-tinjauan-pustaka`),
  /// latexmk dengan `./` di depannya; keduanya harus menunjuk ke berkas yang
  /// sama di pohon proyek.
  String? _messageFile(LatexMessage m) {
    final raw = m.file;
    if (raw == null) return null;
    final name = raw.startsWith('./') ? raw.substring(2) : raw;
    final files = _project.files;
    if (files.contains(name)) return name;
    if (files.contains('$name.tex')) return '$name.tex';
    return null;
  }

  String _messageLine(LatexMessage m) {
    final file = _messageFile(m) ?? m.file;
    final where = <String>[?file, if (m.line != null) '${m.line}'].join(':');
    return where.isEmpty ? m.text : '$where — ${m.text}';
  }

  /// Membuka berkas sebuah pesan dan menaruh kursor di barisnya.
  Future<void> _jumpToMessage(LatexMessage m) async {
    final line = m.line;
    if (line == null) return;
    final file = _messageFile(m) ?? (m.file == null ? _openFile : null);
    if (file == null) {
      _say('Berkas ${m.file} tidak ada di proyek ini.');
      return;
    }
    if (file != _openFile) await _openRelative(file);
    if (!mounted) return;
    final text = _editor.text;
    var offset = 0;
    for (var i = 1; i < line; i++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) break;
      offset = next + 1;
    }
    // Fokus dulu, baru kursornya: penyunting hanya menggulir ke kursor yang
    // berpindah selagi ia memegang fokus.
    _editorFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editor.selection = TextSelection.collapsed(offset: offset.clamp(0, _editor.text.length));
    });
  }

  /// Pesan dari kompilasi terakhir: galat kalau ada, kalau tidak peringatan.
  ///
  /// Merah hanya untuk yang benar-benar menggagalkan kompilasi. Peringatan —
  /// kebanyakan `Underfull \hbox`, baris yang terlalu longgar — dilipat jadi
  /// satu baris: PDF-nya tetap terbit, dan daftar puluhan baris yang selalu
  /// terbuka hanya mendesak penyunting. Setiap pesan menyebut berkas dan
  /// barisnya, dan bisa diketuk untuk langsung ke sana: "baris 40" saja tidak
  /// berarti apa-apa di proyek yang punya belasan berkas bab.
  Widget _messageBar(List<LatexMessage> all, ColorScheme scheme) {
    final errors = all.where((m) => m.severity == LatexSeverity.error).toList(growable: false);
    final shown = errors.isNotEmpty
        ? errors
        : all.where((m) => m.severity == LatexSeverity.warning).toList(growable: false);
    if (shown.isEmpty) return const SizedBox.shrink();
    final bad = errors.isNotEmpty;
    final open = bad || _warningsOpen;
    final background = bad ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final foreground = bad ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    final text = shown.map(_messageLine).join('\n');

    final header = Padding(
      padding: const EdgeInsets.only(left: 12, top: 2, right: 4),
      child: Row(
        children: <Widget>[
          Icon(bad ? Icons.error_outline : Icons.info_outline, size: 16, color: foreground),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              bad ? '${shown.length} galat' : '${shown.length} peringatan — PDF-nya tetap terbit',
              style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Salin semua pesan',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: foreground,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              _say('${shown.length} pesan disalin');
            },
          ),
          if (!bad)
            IconButton(
              tooltip: open ? 'Lipat peringatan' : 'Lihat peringatan',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              color: foreground,
              icon: Icon(open ? Icons.expand_more : Icons.expand_less),
              onPressed: () => setState(() => _warningsOpen = !_warningsOpen),
            ),
        ],
      ),
    );

    return Material(
      color: background,
      child: open
          ? SizedBox(
              // Pesan Tectonic bisa beberapa baris; 64 piksel hanya
              // memperlihatkan barisnya yang pertama dan menyembunyikan sebabnya.
              height: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  header,
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 6),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final m = shown[i];
                        return InkWell(
                          onTap: m.line == null ? null : () => _jumpToMessage(m),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                            child: Text(
                              _messageLine(m),
                              style: TextStyle(
                                color: foreground,
                                fontSize: 12.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          : header,
    );
  }

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

  Widget _fileList() {
    final rows = <Widget>[];
    void walk(List<FileNode> nodes, int depth) {
      for (final node in nodes) {
        if (node.isDirectory) {
          final open = _expanded.contains(node.path);
          rows.add(_treeRow(node, depth, open: open));
          if (open) walk(node.children, depth + 1);
        } else {
          rows.add(_treeRow(node, depth, open: false));
        }
      }
    }

    walk(buildFileTree(_project.files), 0);
    return ListView(children: rows);
  }

  Widget _treeRow(FileNode node, int depth, {required bool open}) {
    final selected = !node.isDirectory && node.path == _openFile;
    final isMain = !node.isDirectory && node.path == _project.mainFile;
    return SizedBox(
      height: treeRowHeight,
      child: ListTile(
        dense: true,
        selected: selected,
        contentPadding: EdgeInsets.only(left: 12 + depth * 14, right: 8),
        horizontalTitleGap: 6,
        leading: Icon(
          node.isDirectory
              ? (open ? Icons.folder_open : Icons.folder_outlined)
              : switch (p.extension(node.name)) {
                  '.tex' => Icons.description_outlined,
                  '.bib' => Icons.menu_book_outlined,
                  '.sty' || '.cls' => Icons.style_outlined,
                  '.pdf' => Icons.picture_as_pdf_outlined,
                  '.png' || '.jpg' || '.jpeg' || '.svg' => Icons.image_outlined,
                  _ => Icons.insert_drive_file_outlined,
                },
          size: 18,
        ),
        title: Text(
          node.name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, fontWeight: isMain ? FontWeight.w700 : null),
        ),
        // Berapa isinya, supaya folder yang tertutup tidak jadi teka-teki.
        trailing: node.isDirectory
            ? Text('${node.fileCount}', style: Theme.of(context).textTheme.labelSmall)
            : null,
        // Tekan lama untuk memilih berkas utama: tebakannya benar hampir
        // selalu, dan saat salah orang butuh jalan yang tidak berbelit.
        onLongPress: !node.isDirectory && p.extension(node.name) == '.tex' && !isMain
            ? () => _setMainFile(node.path)
            : null,
        onTap: node.isDirectory
            ? () => setState(() {
                if (!_expanded.remove(node.path)) _expanded.add(node.path);
              })
            : () => _openRelative(node.path),
      ),
    );
  }

  Widget _preview(ColorScheme scheme) {
    // Hasil kompilasi terakhir kalau ada; kalau belum ada, PDF yang sudah
    // berada di proyek sejak dibuka.
    final pdfPath = _result?.pdfPath ?? _openedPdf;
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
      key: ValueKey<String>('$pdfPath-${_result?.duration.inMicroseconds ?? 0}'),
      params: PdfViewerParams(
        backgroundColor: scheme.surfaceContainerHighest,
        margin: 8,
        // Bilah gulir yang bisa diseret: menggeser 40 halaman dengan
        // sapuan jari satu per satu bukan cara membaca hasil kompilasi.
        viewerOverlayBuilder: (context, size, handleLinkTap) => <Widget>[
          PdfViewerScrollThumb(
            controller: _pdf,
            thumbSize: const Size(44, 36),
            thumbBuilder: (context, thumbSize, pageNumber, controller) => Material(
              color: scheme.secondary,
              borderRadius: BorderRadius.circular(6),
              child: Center(
                child: Text(
                  '${pageNumber ?? 1}',
                  style: TextStyle(color: scheme.onSecondary, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
        onPageChanged: (n) {
          if (n != null) _pdfPage = n;
        },
      ),
    );
  }
}

/// Batang tipis di antara kode dan pratinjau, yang bisa diseret.
///
/// Dibuat selebar 10 piksel dengan kursor dan warna yang berubah saat
/// disentuh: pemisah setipis satu piksel benar dalam gambar rancangan dan
/// mustahil ditangkap dengan jari.
class _SplitHandle extends StatefulWidget {
  const _SplitHandle({required this.onDrag, required this.onDone});

  final void Function(double dx) onDrag;
  final VoidCallback onDone;

  @override
  State<_SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<_SplitHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => widget.onDone(),
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: _active ? 3 : 1,
              color: _active ? scheme.primary : Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}
