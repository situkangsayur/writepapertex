import 'package:flutter/material.dart';

import '../domain/project_files.dart';

/// Apa yang diminta pengguna di lembar "tambah berkas".
sealed class AddFileRequest {
  const AddFileRequest();
}

/// Buat berkas baru di dalam proyek.
class CreateFile extends AddFileRequest {
  const CreateFile({required this.kind, required this.name});

  final NewFileKind kind;

  /// Sudah dirapikan, relatif terhadap folder proyek.
  final String name;
}

/// Ambil berkas yang sudah ada di perangkat dan salin ke dalam proyek.
class ImportFiles extends AddFileRequest {
  const ImportFiles({required this.graphicsOnly});

  /// True membatasi pemilihnya ke gambar, supaya galeri yang terbuka bukan
  /// daftar berisi ribuan berkas.
  final bool graphicsOnly;
}

/// Bertanya berkas apa yang mau ditambahkan.
Future<AddFileRequest?> showAddFileSheet(BuildContext context) =>
    showModalBottomSheet<AddFileRequest>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _AddFileSheet(),
    );

class _AddFileSheet extends StatelessWidget {
  const _AddFileSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          shrinkWrap: true,
          children: <Widget>[
            Text('Tambah berkas', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Berkas baru dibuatkan isi awalnya dan langsung dipanggil dari '
              'berkas utama. Berkas dari perangkat disalin ke dalam folder '
              'proyek, supaya ikut terbawa saat diarsipkan atau dikirim ke git.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),

            Text('Buat baru', style: text.labelLarge),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (final kind in NewFileKind.values) ...<Widget>[
                    if (kind != NewFileKind.values.first) const Divider(height: 1),
                    ListTile(
                      leading: Icon(_iconFor(kind)),
                      title: Text(
                        kind.extension.isEmpty ? kind.label : '${kind.label} (.${kind.extension})',
                      ),
                      subtitle: Text(kind.hint),
                      onTap: () async {
                        final name = await _askName(context, kind);
                        if (name == null || !context.mounted) return;
                        Navigator.of(context).pop(CreateFile(kind: kind, name: name));
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text('Ambil dari perangkat', style: text.labelLarge),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: const Text('Gambar'),
                    subtitle: const Text('disisipkan sebagai figure lengkap dengan caption'),
                    onTap: () => Navigator.of(context).pop(const ImportFiles(graphicsOnly: true)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.attach_file),
                    title: const Text('Berkas lain'),
                    subtitle: const Text('.bib, .sty, .cls, .csv, PDF — apa pun'),
                    onTap: () => Navigator.of(context).pop(const ImportFiles(graphicsOnly: false)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(NewFileKind kind) => switch (kind) {
    NewFileKind.chapter => Icons.article_outlined,
    NewFileKind.bibliography => Icons.menu_book_outlined,
    NewFileKind.style => Icons.style_outlined,
    NewFileKind.documentClass => Icons.school_outlined,
    NewFileKind.plain => Icons.insert_drive_file_outlined,
  };

  /// Menanyakan nama berkasnya, memperlihatkan hasil rapiannya sambil diketik.
  static Future<String?> _askName(BuildContext context, NewFileKind kind) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final tidy = sanitiseFileName(controller.text, extension: kind.extension);
          final valid = controller.text.trim().isNotEmpty;
          return AlertDialog(
            scrollable: true,
            title: Text(kind.label),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Nama berkas',
                      hintText: switch (kind) {
                        NewFileKind.chapter => 'bab/pendahuluan',
                        NewFileKind.bibliography => 'pustaka',
                        NewFileKind.style => 'gaya-saya',
                        NewFileKind.documentClass => 'tazkia',
                        NewFileKind.plain => 'catatan.txt',
                      },
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (valid) Navigator.of(context).pop(tidy);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    valid ? 'Akan dibuat: $tidy' : 'Boleh pakai garis miring untuk subfolder.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              Row(
                children: <Widget>[
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: valid ? () => Navigator.of(context).pop(tidy) : null,
                    child: const Text('Buat'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
