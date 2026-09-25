import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/latex_project.dart';
import 'workspace_screen.dart';

/// Open a folder, or start one from a template.
class StartScreen extends StatefulWidget {
  const StartScreen({this.initialFolder, super.key});

  /// Opened immediately, skipping this screen.
  final String? initialFolder;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
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

  Future<void> _open(LatexProject project) async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => WorkspaceScreen(project: project)));
  }

  Future<void> _openFolder() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Pilih folder proyek LaTeX');
    if (path == null) return;
    await _open(await LatexProject.open(path));
  }

  Future<void> _createFrom(ProjectTemplate template) async {
    final name = await _askName(template.name);
    if (name == null || name.trim().isEmpty) return;

    // On Android there is no folder to pick that the app may write to, so
    // new projects live in its own documents directory.
    final base = await getApplicationDocumentsDirectory();
    final dir = p.join(base.path, 'writepapertex', name.trim());
    try {
      await _open(await template.create(dir));
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('WritePaperTeX')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              Text('Mulai', style: text.titleLarge),
              const SizedBox(height: 4),
              Text('Buka folder yang sudah ada, atau mulai dari templat.', style: text.bodySmall),
              const SizedBox(height: 20),

              if (!Platform.isAndroid)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Buka folder'),
                    subtitle: const Text('Berkas utamanya dicari sendiri dari \\documentclass'),
                    onTap: _openFolder,
                  ),
                ),
              const SizedBox(height: 16),

              Text('Templat', style: text.titleMedium),
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
