import 'package:flutter/material.dart';

import '../domain/git_backend.dart';

/// Clone, commit, pull and push, for whatever git server the project uses.
Future<void> showGitPanel(
  BuildContext context, {
  required String directory,
  required GitBackend backend,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _GitPanel(directory: directory, backend: backend),
);

class _GitPanel extends StatefulWidget {
  const _GitPanel({required this.directory, required this.backend});

  final String directory;
  final GitBackend backend;

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

  @override
  void initState() {
    super.initState();
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
                  IconButton(
                    tooltip: 'Muat ulang',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _busy ? null : _refresh,
                  ),
                ],
              ),

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
                final init = await widget.backend.init(widget.directory);
                if (!init.ok) return init;
                final remote = _remote.text.trim();
                if (remote.isEmpty) {
                  return const GitResult(ok: true, output: '', message: 'Repositori dibuat');
                }
                return widget.backend.setRemote(widget.directory, remote);
              }),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Jadikan repositori'),
      ),
    ],
  );
}
