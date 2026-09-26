import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/project_import.dart';
import '../data/recent_projects.dart';
import '../domain/latex_project.dart';
import 'workspace_screen.dart';

/// Layar pembuka: lanjutkan yang terakhir, buka dari mana pun, atau mulai baru.
class StartScreen extends StatefulWidget {
  const StartScreen({this.initialFolder, super.key});

  /// Dibuka langsung, melewati layar ini.
  final String? initialFolder;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final RecentProjects _recents = const RecentProjects();
  final ProjectImport _import = const ProjectImport();

  List<RecentProject> _recent = const <RecentProject>[];
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _loadRecents();
    final folder = widget.initialFolder;
    if (folder == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!Directory(folder).existsSync()) {
        if (mounted) setState(() => _error = 'Folder tidak ada: $folder');
        return;
      }
      await _open(await LatexProject.open(folder));
    });
  }

  Future<void> _loadRecents() async {
    final list = await _recents.load();
    if (mounted) setState(() => _recent = list);
  }

  Future<void> _open(LatexProject project) async {
    await _recents.remember(project.directory);
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => WorkspaceScreen(project: project)));
    await _loadRecents();
  }

  /// Folder tempat proyek hasil impor dan templat disimpan.
  ///
  /// Di Android tidak ada folder lain yang boleh ditulisi aplikasi, dan di
  /// desktop pun menyatukannya membuat daftar "terakhir dibuka" berarti.
  Future<String> _projectsRoot() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'writepapertex'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _guard(String label, Future<void> Function() action) async {
    setState(() {
      _busy = label;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ------------------------------------------------------------- membuka

  Future<void> _openFolder() => _guard('Membuka folder…', () async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Pilih folder proyek LaTeX');
    if (path == null) return;
    await _open(await LatexProject.open(path));
  });

  /// Membuka satu berkas `.tex`.
  ///
  /// Di Android pemilih berkas menyerahkan salinan di cache, bukan berkas
  /// aslinya, jadi berkas itu disalin ke folder proyek milik aplikasi supaya
  /// suntingannya benar-benar tersimpan di tempat yang bisa ditemukan lagi.
  Future<void> _openFile() => _guard('Membuka berkas…', () async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['tex'],
      dialogTitle: 'Pilih berkas .tex',
    );
    final path = picked.singleOrNull?.path;
    if (path == null) return;

    if (!Platform.isAndroid && !Platform.isIOS) {
      await _open(await LatexProject.open(p.dirname(path)));
      return;
    }

    final root = await _projectsRoot();
    final name = p.basenameWithoutExtension(path);
    final target = Directory(p.join(root, name));
    if (!target.existsSync()) await target.create(recursive: true);
    await File(path).copy(p.join(target.path, p.basename(path)));
    await _open(await LatexProject.open(target.path));
  });

  Future<void> _openZip() => _guard('Membongkar ZIP…', () async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
      dialogTitle: 'Pilih arsip ZIP',
    );
    final path = picked.singleOrNull?.path;
    if (path == null) return;
    final project = await _import.fromZip(
      zipBytes: await File(path).readAsBytes(),
      baseDir: await _projectsRoot(),
      name: p.basenameWithoutExtension(path),
    );
    await _open(project);
  });

  Future<void> _openRepository() async {
    final input = await _askRepository();
    if (input == null) return;
    await _guard('Mengunduh repositori…', () async {
      final project = await _import.fromRepository(
        repoUrl: input.url,
        branch: input.branch,
        baseDir: await _projectsRoot(),
        onProgress: (m) {
          if (mounted) setState(() => _busy = m);
        },
      );
      await _open(project);
    });
  }

  Future<({String url, String branch})?> _askRepository() {
    final url = TextEditingController();
    final branch = TextEditingController();
    return showDialog<({String url, String branch})>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Buka dari repositori'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'GitHub, GitLab, atau Gitea sendiri. Isinya diunduh sebagai '
                'arsip, jadi tidak perlu git terpasang.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Alamat repositori',
                  hintText: 'https://github.com/pemilik/nama',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: branch,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Cabang (boleh dikosongkan)',
                  hintText: 'main',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Catatan: yang diunduh adalah salinan. Mengirim balik '
                'perubahan lewat git baru tersedia di desktop.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          Row(
            children: <Widget>[
              const Spacer(),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop((url: url.text.trim(), branch: branch.text.trim())),
                child: const Text('Unduh'),
              ),
            ],
          ),
        ],
      ),
    ).then((value) => (value == null || value.url.isEmpty) ? null : value);
  }

  Future<void> _createFrom(ProjectTemplate template) async {
    final name = await _askName(template.name);
    if (name == null || name.trim().isEmpty) return;
    await _guard('Membuat proyek…', () async {
      final dir = p.join(await _projectsRoot(), name.trim());
      await _open(await template.create(dir));
    });
  }

  Future<String?> _askName(String suggestion) {
    final controller = TextEditingController(text: suggestion.toLowerCase().replaceAll(' ', '-'));
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nama proyek'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Nama folder'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- tampilan

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('WritePaperTeX')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              if (_busy != null) ...<Widget>[
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_busy!, style: text.bodyMedium)),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              if (_recent.isNotEmpty) ...<Widget>[
                Text('Lanjutkan', style: text.titleMedium),
                const SizedBox(height: 8),
                for (final r in _recent.take(5))
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(r.name),
                      subtitle: Text(r.directory, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        tooltip: 'Hapus dari daftar',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () async {
                          final list = await _recents.forget(r.directory);
                          if (mounted) setState(() => _recent = list);
                        },
                      ),
                      onTap: () => _guard('Membuka…', () async {
                        await _open(await LatexProject.open(r.directory));
                      }),
                    ),
                  ),
                const SizedBox(height: 20),
              ],

              Text('Buka', style: text.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: const Text('Folder proyek'),
                      subtitle: const Text('berkas utamanya dicari dari \\documentclass'),
                      onTap: _openFolder,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Berkas .tex'),
                      subtitle: const Text('satu berkas, tanpa folder proyek'),
                      onTap: _openFile,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.folder_zip_outlined),
                      title: const Text('Arsip ZIP'),
                      subtitle: const Text('dibongkar jadi proyek baru'),
                      onTap: _openZip,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.cloud_download_outlined),
                      title: const Text('Repositori git'),
                      subtitle: const Text('GitHub, GitLab, atau Gitea sendiri'),
                      onTap: _openRepository,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text('Mulai baru', style: text.titleMedium),
              const SizedBox(height: 8),
              for (final template in ProjectTemplate.all)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.note_add_outlined),
                    title: Text(template.name),
                    subtitle: Text(template.description),
                    onTap: () => _createFrom(template),
                  ),
                ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
