// Memeriksa clone, commit, dan push terhadap repositori sungguhan.
//
// Bukan uji satuan: perlu jaringan dan token, jadi tidak boleh ikut di
// `flutter test`. Dijalankan sendiri saat jalur kredensial disentuh:
//
//   WPTEX_REPO=https://github.com/pemilik/nama.git \
//   WPTEX_TOKEN=github_pat_… \
//   dart run tool/periksa-git.dart
//
// Tokennya hanya dibaca dari lingkungan — tidak pernah ditulis ke berkas mana
// pun di dalam repositori ini.
import 'dart:io';

import 'package:writepapertex/src/features/git/data/git_cli_backend.dart';

Future<void> main() async {
  final repo = Platform.environment['WPTEX_REPO'];
  final token = Platform.environment['WPTEX_TOKEN'];
  if (repo == null || repo.isEmpty) {
    stderr.writeln('WPTEX_REPO belum diisi');
    exit(2);
  }

  final backend = GitCliBackend(token: token);
  final work = Directory.systemTemp.createTempSync('wptex-periksa-');
  final target = '${work.path}/salinan';
  var gagal = 0;

  void periksa(String what, bool ok, [String detail = '']) {
    stdout.writeln('${ok ? '  ok  ' : 'GAGAL '} $what${detail.isEmpty ? '' : ' — $detail'}');
    if (!ok) gagal++;
  }

  try {
    stdout.writeln('clone $repo');
    final clone = await backend.clone(remoteUrl: repo, directory: target);
    periksa('clone', clone.ok, clone.ok ? '' : clone.output.trim());
    if (!clone.ok) exit(1);

    periksa('foldernya jadi repositori', await backend.isRepository(target));

    final status = await backend.status(target);
    periksa('status terbaca', status != null);
    periksa('bersih sesudah clone', status?.isClean ?? false);
    periksa('remote tercatat', status?.hasRemote ?? false, status?.remoteUrl ?? '');
    periksa('ada riwayatnya', (status?.lastCommit ?? '').isNotEmpty, status?.lastCommit ?? '');
    stdout.writeln('  cabang: ${status?.branch}');

    // Commit ke cabang terpisah, supaya pemeriksaan ini tidak pernah menyentuh
    // cabang tempat orang bekerja.
    final branch = 'uji-writepapertex-${DateTime.now().millisecondsSinceEpoch}';
    final dibuat = await Process.run('git', <String>[
      'checkout',
      '-b',
      branch,
    ], workingDirectory: target);
    periksa('cabang uji dibuat', dibuat.exitCode == 0);

    File('$target/writepapertex-periksa.txt').writeAsStringSync(
      'Ditulis oleh tool/periksa-git.dart pada ${DateTime.now()}\n',
    );

    final after = await backend.status(target);
    periksa('perubahan terlihat', !(after?.isClean ?? true), '${after?.changes.length} berkas');

    final commit = await backend.commitAll(target, message: 'Periksa jalur git WritePaperTeX');
    periksa('commit', commit.ok, commit.ok ? '' : commit.output.trim());

    final kedua = await backend.commitAll(target, message: 'tidak ada apa-apa');
    periksa('commit kedua mengaku tidak ada perubahan', kedua.ok && kedua.message.contains('Tidak'));

    // Cabang yang baru dibuat belum punya hulu, dan `git push` tanpa argumen
    // akan menolaknya. `push.default = current` membuat dorongan pertamanya
    // memakai nama cabang yang sedang dipakai — itulah yang dilakukan tombol
    // Kirim di aplikasi, jadi yang diuji di sini memang jalur yang sama.
    await Process.run('git', <String>[
      'config',
      'push.default',
      'current',
    ], workingDirectory: target);

    final push = await backend.push(target);
    periksa('push lewat backend', push.ok, push.ok ? '' : push.output.trim());
    if (push.ok) {
      // Menghapus cabang di sisi remote bukan pekerjaan aplikasi ini, jadi
      // namanya dicetak dan pembersihannya diserahkan ke yang menjalankan.
      stdout.writeln('\nHapus cabang ujinya dengan:\n'
          '  gh api -X DELETE repos/<pemilik>/<nama>/git/refs/heads/$branch');
    }
  } finally {
    work.deleteSync(recursive: true);
  }

  stdout.writeln(gagal == 0 ? '\nSemuanya lolos.' : '\n$gagal pemeriksaan gagal.');
  exit(gagal == 0 ? 0 : 1);
}
