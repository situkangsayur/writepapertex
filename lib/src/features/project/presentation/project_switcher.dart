import 'package:flutter/material.dart';

import '../data/workspace_store.dart';
import '../domain/project_profile.dart';

/// Hasil dari lembar pindah proyek.
sealed class SwitcherResult {
  const SwitcherResult();
}

/// Pindah ke proyek ini.
class SwitchTo extends SwitcherResult {
  const SwitchTo(this.profile);

  final ProjectProfile profile;
}

/// Kembali ke layar pembuka untuk membuka atau membuat yang lain.
class OpenSomethingElse extends SwitcherResult {
  const OpenSomethingElse();
}

/// Daftar proyek yang dikenal, untuk berpindah tanpa menutup ruang kerja.
///
/// Sebuah paper jarang berdiri sendiri: proposal, artikel jurnal, dan slide
/// seminar hidup di tiga repositori berbeda dan disunting berganti-ganti dalam
/// satu duduk. Menutup aplikasi untuk berpindah di antaranya adalah
/// kejengkelan yang tidak perlu ada.
Future<SwitcherResult?> showProjectSwitcher(
  BuildContext context, {
  required WorkspaceStore store,
  required String currentId,
}) => showModalBottomSheet<SwitcherResult>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _Switcher(store: store, currentId: currentId),
);

class _Switcher extends StatefulWidget {
  const _Switcher({required this.store, required this.currentId});

  final WorkspaceStore store;
  final String currentId;

  @override
  State<_Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<_Switcher> {
  List<ProjectProfile>? _profiles;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await widget.store.load();
    if (mounted) setState(() => _profiles = profiles);
  }

  Future<void> _editRemote(ProjectProfile profile) async {
    final token = await widget.store.tokenFor(profile.id);
    if (!mounted) return;
    final result = await showRemoteEditor(context, profile: profile, token: token);
    if (result == null) return;
    await widget.store.update(result.profile);
    await widget.store.saveToken(profile.id, result.token);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final profiles = _profiles;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          shrinkWrap: true,
          children: <Widget>[
            Text('Proyek', style: text.titleMedium),
            const SizedBox(height: 10),

            if (profiles == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    for (final profile in profiles) ...<Widget>[
                      if (profile != profiles.first) const Divider(height: 1),
                      ListTile(
                        selected: profile.id == widget.currentId,
                        leading: Icon(
                          profile.id == widget.currentId
                              ? Icons.radio_button_checked
                              : Icons.folder_outlined,
                        ),
                        title: Text(profile.name),
                        subtitle: Text(
                          profile.hasRemote ? profile.remoteLabel : profile.directory,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              tooltip: 'Alamat git dan token',
                              icon: Icon(
                                profile.hasRemote ? Icons.cloud_done_outlined : Icons.cloud_off,
                                size: 18,
                              ),
                              onPressed: () => _editRemote(profile),
                            ),
                            IconButton(
                              tooltip: 'Hapus dari daftar',
                              icon: const Icon(Icons.close, size: 18),
                              // Proyek yang sedang dibuka tidak bisa dilupakan:
                              // daftarnya akan menunjuk ke yang tidak ada.
                              onPressed: profile.id == widget.currentId
                                  ? null
                                  : () async {
                                      await widget.store.forget(profile.id);
                                      await _load();
                                    },
                            ),
                          ],
                        ),
                        onTap: profile.id == widget.currentId
                            ? null
                            : () => Navigator.of(context).pop(SwitchTo(profile)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text('Menghapus dari daftar tidak menghapus berkasnya.', style: text.bodySmall),
            ],

            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(const OpenSomethingElse()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Buka atau buat yang lain…'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alamat git dan token sebuah proyek.
class RemoteSettings {
  const RemoteSettings({required this.profile, required this.token});

  final ProjectProfile profile;
  final String? token;
}

/// Menyunting alamat remote, cabang, dan token satu proyek.
Future<RemoteSettings?> showRemoteEditor(
  BuildContext context, {
  required ProjectProfile profile,
  String? token,
}) {
  final url = TextEditingController(text: profile.remoteUrl);
  final branch = TextEditingController(text: profile.branch);
  final secret = TextEditingController(text: token ?? '');
  final user = TextEditingController(text: profile.httpsUsername);
  final authorName = TextEditingController(text: profile.authorName);
  final authorEmail = TextEditingController(text: profile.authorEmail);

  return showDialog<RemoteSettings>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(profile.name),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: url,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Alamat remote',
                hintText: 'https://github.com/pemilik/nama.git',
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
            TextField(
              controller: user,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Nama pengguna git (boleh dikosongkan)',
                hintText: 'situkangsayur',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: secret,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Token akses',
                hintText: 'github_pat_… — perlu untuk repositori tertutup',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'GitHub menerima nama pengguna apa pun asal tokennya benar; '
              'Gitea dan GitLab memeriksanya, jadi isilah kalau memakai salah '
              'satu dari keduanya. Tokennya disimpan terpisah dari daftar '
              'proyek, di berkas yang hanya bisa dibaca pemiliknya. Pakai '
              'HTTPS, bukan SSH: token bisa dicabut satu per satu, kunci '
              'privat yang tertinggal di tablet tidak.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Padding(padding: EdgeInsets.only(top: 14, bottom: 10), child: Divider(height: 1)),
            Text('Identitas pada commit', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: authorName,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Nama penulis',
                hintText: 'Hendri Karisma',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: authorEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Surel penulis',
                hintText: 'nama@contoh.ac.id',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Inilah yang tercantum pada setiap commit. Dibiarkan kosong, '
              'commit-nya atas nama aplikasi — dan riwayat sebuah paper '
              'kehilangan keterangan siapa menulis apa.',
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
              onPressed: () => Navigator.of(context).pop(
                RemoteSettings(
                  profile: profile.copyWith(
                    remoteUrl: url.text.trim(),
                    branch: branch.text.trim(),
                    httpsUsername: user.text.trim(),
                    authorName: authorName.text.trim(),
                    authorEmail: authorEmail.text.trim(),
                  ),
                  token: secret.text.trim().isEmpty ? null : secret.text.trim(),
                ),
              ),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ],
    ),
  );
}
