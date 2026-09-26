import 'package:flutter/material.dart';

import '../domain/git_backend.dart';

/// Clone, commit, pull and push, for whatever git server the project uses.
Future<void> showGitPanel(
  BuildContext context, {
  required String directory,
  required GitBackend backend,
  String suggestedRemote = '',
  String branch = '',
  String authorName = '',
  String authorEmail = '',
  Future<void> Function(String remoteUrl)? onRemoteSet,
  Future<({String name, String email})?> Function()? onEditIdentity,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _GitPanel(
    directory: directory,
    backend: backend,
    suggestedRemote: suggestedRemote,
    branch: branch,
    authorName: authorName,
    authorEmail: authorEmail,
    onRemoteSet: onRemoteSet,
    onEditIdentity: onEditIdentity,
  ),
);

class _GitPanel extends StatefulWidget {
  const _GitPanel({
    required this.directory,
    required this.backend,
    this.suggestedRemote = '',
    this.branch = '',
    this.authorName = '',
    this.authorEmail = '',
    this.onRemoteSet,
    this.onEditIdentity,
  });

  final String directory;
  final GitBackend backend;

  /// Alamat yang sudah tercatat untuk proyek ini, ditawarkan sebagai isi awal.
  final String suggestedRemote;
  final String branch;

  /// Nama dan surel yang dicantumkan pada commit.
  final String authorName;
  final String authorEmail;

  /// Dipanggil setelah remote berhasil dipasang, supaya profil proyeknya ikut
  /// mengingatnya.
  final Future<void> Function(String remoteUrl)? onRemoteSet;

  /// Membuka tempat mengisi nama pengguna, token, dan identitas penulis.
  ///
  /// Mengembalikan identitas yang baru, karena panel ini sudah terbuka saat
  /// suntingannya terjadi dan tidak akan melihat perubahannya sendiri.
  final Future<({String name, String email})?> Function()? onEditIdentity;

  @override
  State<_GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<_GitPanel> {
  final TextEditingController _message = TextEditingController();
  final TextEditingController _remote = TextEditingController();

  GitStatus? _status;
  bool _busy = false;
  bool _available = true;
  String _log = '';

  /// Identitas yang dipakai commit berikutnya.
  late String _authorName = widget.authorName;
  late String _authorEmail = widget.authorEmail;

  @override
  void initState() {
    super.initState();
    _remote.text = widget.suggestedRemote;
    _refresh();
  }

  @override
  void dispose() {
    _message.dispose();
    _remote.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final available = await widget.backend.isAvailable();
    final status = available ? await widget.backend.status(widget.directory) : null;
    if (!mounted) return;
    setState(() {
      _available = available;
      _status = status;
    });
  }

  Future<void> _do(Future<GitResult> Function() action) async {
    setState(() {
      _busy = true;
      _log = '';
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      // git's own words are kept: its errors are usually the clearest
      // explanation available, and paraphrasing loses the useful part.
      _log = result.message.isNotEmpty ? result.message : result.output.trim();
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = _status;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          // Naik setinggi papan ketik. Tanpa ini panelnya tertutup rapat oleh
          // papan ketik begitu kolom pesan commit disentuh: yang mengetik
          // tidak bisa melihat tulisannya sendiri, apalagi menekan Simpan.
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('Git', style: text.titleMedium),
                  const SizedBox(width: 10),
                  if (_busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const Spacer(),
                  if (widget.onEditIdentity != null)
                    IconButton(
                      tooltip: 'Akun dan identitas',
                      icon: const Icon(Icons.manage_accounts_outlined, size: 20),
                      onPressed: _busy
                          ? null
                          : () async {
                              final identity = await widget.onEditIdentity!.call();
                              if (identity != null && mounted) {
                                setState(() {
                                  _authorName = identity.name;
                                  _authorEmail = identity.email;
                                });
                              }
                              await _refresh();
                            },
                    ),
                  IconButton(
                    tooltip: 'Muat ulang',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _busy ? null : _refresh,
                  ),
                ],
              ),

              // Identitas yang belum diisi baru terasa akibatnya jauh di
              // kemudian hari, saat riwayatnya dibaca orang lain — jadi
              // dikatakan sekarang, di tempat commit dibuat.
              Text(
                _authorName.isEmpty
                    ? 'Commit atas nama aplikasi — isi nama dan surel lewat ikon akun.'
                    : 'Commit sebagai $_authorName'
                          '${_authorEmail.isEmpty ? '' : ' <$_authorEmail>'}',
                style: text.bodySmall?.copyWith(color: _authorName.isEmpty ? scheme.error : null),
              ),
              const SizedBox(height: 8),

              if (!_available)
                Text(
                  'git tidak ditemukan di mesin ini. Pasang dengan: sudo apt install git',
                  style: TextStyle(color: scheme.error),
                )
              else if (status == null)
                _notARepository(text)
              else ...<Widget>[
                Text(
                  '${status.branch}'
                  '${status.hasRemote ? ' → ${status.remoteUrl}' : ' · belum ada remote'}',
                  style: text.bodySmall,
                ),
                if (status.lastCommit.isNotEmpty) Text(status.lastCommit, style: text.labelSmall),
                const SizedBox(height: 4),
                Text(
                  status.isClean
                      ? 'Tidak ada perubahan'
                      : '${status.changes.length} berkas berubah',
                  style: text.bodyMedium,
                ),
                if (status.ahead > 0 || status.behind > 0)
                  Text(
                    <String>[
                      if (status.ahead > 0) '${status.ahead} commit belum dikirim',
                      if (status.behind > 0) '${status.behind} commit menunggu ditarik',
                    ].join(' · '),
                    style: TextStyle(color: scheme.primary, fontSize: 12.5),
                  ),

                if (!status.isClean) ...<Widget>[
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final change in status.changes)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 84,
                                  child: Text(change.label, style: text.labelSmall),
                                ),
                                Expanded(
                                  child: Text(
                                    change.path,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _message,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Pesan commit',
                    ),
                    // Tanpa ini tombol Simpan tidak pernah menyala: keadaannya
                    // bergantung pada isi kolom ini, dan tidak ada yang
                    // membangun ulang saat orang mengetik.
                    onChanged: (_) => setState(() {}),
                  ),
                ],

                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: _busy || status.isClean || _message.text.trim().isEmpty
                          ? null
                          : () => _do(
                              () => widget.backend.commitAll(
                                widget.directory,
                                message: _message.text.trim(),
                                authorName: _authorName,
                                authorEmail: _authorEmail,
                              ),
                            ),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Simpan (commit)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || !status.hasRemote
                          ? null
                          : () => _do(() => widget.backend.pull(widget.directory)),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Tarik'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || !status.hasRemote
                          ? null
                          : () => _do(() => widget.backend.push(widget.directory)),
                      icon: const Icon(Icons.upload, size: 18),
                      label: const Text('Kirim'),
                    ),
                  ],
                ),
              ],

              if (_log.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _log,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _notARepository(TextTheme text) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('Folder ini belum berupa repositori git.', style: text.bodyMedium),
      const SizedBox(height: 4),
      Text(
        'Alamat remote boleh GitHub, GitLab, Gitea sendiri, atau folder lain '
        'di komputer ini — semuanya git yang sama.',
        style: text.bodySmall,
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _remote,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          labelText: 'Alamat remote (boleh dikosongkan)',
          hintText: 'git@gitea.kantor:tim/paper.git',
        ),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _busy
            ? null
            : () => _do(() async {
                final init = await widget.backend.init(
                  widget.directory,
                  branch: widget.branch.isEmpty ? 'main' : widget.branch,
                );
                if (!init.ok) return init;
                final remote = _remote.text.trim();
                if (remote.isEmpty) {
                  return const GitResult(ok: true, output: '', message: 'Repositori dibuat');
                }
                final set = await widget.backend.setRemote(widget.directory, remote);
                if (set.ok) await widget.onRemoteSet?.call(remote);
                return set;
              }),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Jadikan repositori'),
      ),
    ],
  );
}
