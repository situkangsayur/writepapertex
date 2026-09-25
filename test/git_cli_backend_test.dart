import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:writepapertex/src/features/git/data/git_cli_backend.dart';

/// Runs against the real `git` on this machine, and against a real bare
/// repository standing in for a remote.
///
/// A bare repo on disk behaves exactly like GitHub, GitLab or a self-hosted
/// Gitea as far as `git` is concerned — which is the whole reason this
/// backend works with all of them.
void main() {
  const git = GitCliBackend();
  late Directory root;
  late String remote;
  late String work;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('wptex_git_');
    remote = p.join(root.path, 'remote.git');
    work = p.join(root.path, 'work');
    await Process.run('git', <String>['init', '--bare', '-b', 'main', remote]);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> seedRemote() async {
    final seed = p.join(root.path, 'seed');
    await Process.run('git', <String>['clone', remote, seed]);
    File(p.join(seed, 'main.tex')).writeAsStringSync(r'\documentclass{article}');
    await Process.run('git', <String>['-C', seed, 'add', '-A']);
    await Process.run('git', <String>[
      '-C',
      seed,
      '-c',
      'user.name=Uji',
      '-c',
      'user.email=uji@contoh.id',
      'commit',
      '-m',
      'awal',
    ]);
    await Process.run('git', <String>['-C', seed, 'push', 'origin', 'main']);
  }

  test('git is found', () async {
    expect(await git.isAvailable(), isTrue);
  });

  test('a folder that is not a repository is reported as such', () async {
    final plain = Directory(p.join(root.path, 'biasa'))..createSync();
    expect(await git.isRepository(plain.path), isFalse);
    expect(await git.status(plain.path), isNull);
  });

  test('a folder that does not exist does not throw', () async {
    expect(await git.isRepository(p.join(root.path, 'tidak-ada')), isFalse);
  });

  group('the full round trip', () {
    test(
      'clone, change, commit, push, and the remote has it',
      () async {
        await seedRemote();

        final cloned = await git.clone(remoteUrl: remote, directory: work);
        expect(cloned.ok, isTrue, reason: cloned.output);
        expect(File(p.join(work, 'main.tex')).existsSync(), isTrue);

        var status = await git.status(work);
        expect(status!.isClean, isTrue);
        expect(status.branch, 'main');
        expect(status.hasRemote, isTrue);

        File(p.join(work, 'bagian.tex')).writeAsStringSync(r'\section{Baru}');
        status = await git.status(work);
        expect(status!.isClean, isFalse);
        expect(status.changes.single.path, 'bagian.tex');
        expect(status.changes.single.isUntracked, isTrue);
        expect(status.changes.single.label, 'baru');

        final committed = await git.commitAll(
          work,
          message: 'tambah bagian',
          authorName: 'Uji',
          authorEmail: 'uji@contoh.id',
        );
        expect(committed.ok, isTrue, reason: committed.output);

        status = await git.status(work);
        expect(status!.isClean, isTrue);
        expect(status.ahead, 1, reason: 'satu commit belum dikirim');

        final pushed = await git.push(work);
        expect(pushed.ok, isTrue, reason: pushed.output);

        status = await git.status(work);
        expect(status!.ahead, 0);

        // The bare repo really received it.
        final log = await Process.run('git', <String>['-C', remote, 'log', '--oneline']);
        expect(log.stdout.toString(), contains('tambah bagian'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('pull brings down what someone else pushed', () async {
      await seedRemote();
      await git.clone(remoteUrl: remote, directory: work);

      // Somebody else commits and pushes.
      final other = p.join(root.path, 'orang-lain');
      await Process.run('git', <String>['clone', remote, other]);
      File(p.join(other, 'tabel.tex')).writeAsStringSync(r'\begin{tabular}{l}a\end{tabular}');
      await Process.run('git', <String>['-C', other, 'add', '-A']);
      await Process.run('git', <String>[
        '-C',
        other,
        '-c',
        'user.name=Lain',
        '-c',
        'user.email=lain@contoh.id',
        'commit',
        '-m',
        'tabel',
      ]);
      await Process.run('git', <String>['-C', other, 'push']);

      final pulled = await git.pull(work);
      expect(pulled.ok, isTrue, reason: pulled.output);
      expect(File(p.join(work, 'tabel.tex')).existsSync(), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('pulling does not throw away work in progress', () async {
      await seedRemote();
      await git.clone(remoteUrl: remote, directory: work);

      // Unsaved edits in the working tree while a pull happens.
      File(p.join(work, 'main.tex')).writeAsStringSync('% sedang ditulis\n');

      final other = p.join(root.path, 'orang-lain');
      await Process.run('git', <String>['clone', remote, other]);
      File(p.join(other, 'lain.tex')).writeAsStringSync('x');
      await Process.run('git', <String>['-C', other, 'add', '-A']);
      await Process.run('git', <String>[
        '-C',
        other,
        '-c',
        'user.name=L',
        '-c',
        'user.email=l@c.id',
        'commit',
        '-m',
        'lain',
      ]);
      await Process.run('git', <String>['-C', other, 'push']);

      final pulled = await git.pull(work);
      expect(pulled.ok, isTrue, reason: pulled.output);
      expect(File(p.join(work, 'lain.tex')).existsSync(), isTrue);
      // The half-written paragraph survived.
      expect(File(p.join(work, 'main.tex')).readAsStringSync(), contains('sedang ditulis'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('starting a repository from a folder', () {
    test('init then remote makes a template project pushable', () async {
      final fresh = Directory(p.join(root.path, 'baru'))..createSync();
      File(p.join(fresh.path, 'main.tex')).writeAsStringSync(r'\documentclass{article}');

      expect((await git.init(fresh.path)).ok, isTrue);
      expect(await git.isRepository(fresh.path), isTrue);
      expect((await git.setRemote(fresh.path, remote)).ok, isTrue);

      final status = await git.status(fresh.path);
      expect(status!.remoteUrl, remote);
    });

    test('setting the remote twice replaces it rather than failing', () async {
      final fresh = Directory(p.join(root.path, 'baru2'))..createSync();
      await git.init(fresh.path);
      await git.setRemote(fresh.path, remote);
      final again = await git.setRemote(fresh.path, '${remote}x');
      expect(again.ok, isTrue);
      expect((await git.status(fresh.path))!.remoteUrl, '${remote}x');
    });
  });

  test(
    'committing with nothing changed says so instead of failing',
    () async {
      await seedRemote();
      await git.clone(remoteUrl: remote, directory: work);
      final result = await git.commitAll(
        work,
        message: 'kosong',
        authorName: 'U',
        authorEmail: 'u@c',
      );
      expect(result.ok, isTrue);
      expect(result.message, contains('Tidak ada perubahan'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a missing git binary is reported, not thrown', () async {
    const missing = GitCliBackend(executable: 'git-yang-tidak-ada');
    expect(await missing.isAvailable(), isFalse);
    final result = await missing.pull(root.path);
    expect(result.ok, isFalse);
    expect(result.output, contains('tidak bisa dijalankan'));
  });
}
