import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/git_backend.dart';

/// Runs the `git` already installed on the machine.
///
/// This is the desktop backend, and it is the reason WritePaperTeX works with
/// GitHub, GitLab, a self-hosted Gitea and a bare repository on a disk without
/// knowing the difference: `git` itself does not care which it is talking to.
///
/// Android has no `git` binary; that is a separate backend (see KT-6).
class GitCliBackend implements GitBackend {
  const GitCliBackend({this.executable = 'git', this.token, this.username = ''});

  final String executable;

  /// Nama pengguna HTTPS. Kosong berarti `x-access-token`.
  final String username;

  /// Token akses untuk remote HTTPS tertutup.
  ///
  /// Tidak pernah masuk ke baris perintah dan tidak pernah ditulis ke
  /// `.git/config`: keduanya berarti token itu terbaca oleh proses lain atau
  /// ikut tersalin bersama repositorinya. Yang dipakai adalah `GIT_ASKPASS` —
  /// jalan yang sama dengan yang dipakai git sendiri untuk bertanya.
  final String? token;

  @override
  String get name => executable;

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await Process.run(executable, <String>['--version']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<bool> isRepository(String directory) async {
    if (!Directory(directory).existsSync()) return false;
    final result = await _run(directory, <String>['rev-parse', '--is-inside-work-tree']);
    return result.ok && result.output.trim() == 'true';
  }

  @override
  Future<GitStatus?> status(String directory) async {
    if (!await isRepository(directory)) return null;

    // -b puts a header line first that carries branch and ahead/behind, so
    // one call answers everything the panel shows.
    final porcelain = await _run(directory, <String>['status', '--porcelain=v1', '-b']);
    if (!porcelain.ok) return null;

    var branch = '';
    var ahead = 0;
    var behind = 0;
    final changes = <GitChange>[];

    for (final line in const LineSplitter().convert(porcelain.output)) {
      if (line.isEmpty) continue;
      if (line.startsWith('## ')) {
        final header = line.substring(3);
        branch = header.split(RegExp(r'\.\.\.|\s')).first;
        ahead = _count(header, 'ahead');
        behind = _count(header, 'behind');
        continue;
      }
      if (line.length < 4) continue;
      changes.add(GitChange(status: line.substring(0, 2), path: line.substring(3).trim()));
    }

    final remote = await _run(directory, <String>['remote', 'get-url', 'origin']);
    final last = await _run(directory, <String>['log', '-1', '--pretty=%h %s']);

    return GitStatus(
      branch: branch.isEmpty ? '(tanpa commit)' : branch,
      changes: changes,
      ahead: ahead,
      behind: behind,
      remoteUrl: remote.ok ? remote.output.trim() : '',
      lastCommit: last.ok ? last.output.trim() : '',
    );
  }

  static int _count(String header, String word) {
    final match = RegExp('$word (\\d+)').firstMatch(header);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  @override
  Future<GitResult> clone({
    required String remoteUrl,
    required String directory,
    String? branch,
    void Function(String line)? onOutput,
  }) => _stream(
    Directory(directory).parent.path,
    <String>[
      'clone',
      '--progress',
      if (branch != null) ...<String>['--branch', branch],
      remoteUrl,
      directory,
    ],
    onOutput: onOutput,
    okMessage: 'Repositori tersalin',
  );

  @override
  Future<GitResult> pull(String directory, {void Function(String line)? onOutput}) => _stream(
    directory,
    // --autostash keeps unsaved work: pulling should never be the reason
    // someone loses a paragraph they were in the middle of.
    <String>['pull', '--rebase', '--autostash', '--progress'],
    onOutput: onOutput,
    okMessage: 'Perubahan ditarik',
  );

  @override
  Future<GitResult> commitAll(
    String directory, {
    required String message,
    String? authorName,
    String? authorEmail,
  }) async {
    final added = await _run(directory, <String>['add', '-A']);
    if (!added.ok) return added;

    final args = <String>[
      if (authorName != null && authorName.isNotEmpty) ...<String>['-c', 'user.name=$authorName'],
      if (authorEmail != null && authorEmail.isNotEmpty) ...<String>[
        '-c',
        'user.email=$authorEmail',
      ],
      'commit',
      '-m',
      message,
    ];
    final result = await _run(directory, args);
    if (!result.ok && result.output.contains('nothing to commit')) {
      return const GitResult(ok: true, output: '', message: 'Tidak ada perubahan untuk disimpan');
    }
    return GitResult(ok: result.ok, output: result.output, message: result.ok ? 'Tersimpan' : '');
  }

  @override
  Future<GitResult> push(String directory, {void Function(String line)? onOutput}) =>
      _stream(directory, <String>['push', '--progress'], onOutput: onOutput, okMessage: 'Terkirim');

  @override
  Future<GitResult> init(String directory, {String branch = 'main'}) =>
      _run(directory, <String>['init', '-b', branch]);

  @override
  Future<GitResult> setRemote(String directory, String remoteUrl, {String name = 'origin'}) async {
    final existing = await _run(directory, <String>['remote', 'get-url', name]);
    return existing.ok
        ? _run(directory, <String>['remote', 'set-url', name, remoteUrl])
        : _run(directory, <String>['remote', 'add', name, remoteUrl]);
  }

  Future<GitResult> _run(String directory, List<String> args) => _withAuth((environment) async {
    try {
      final result = await Process.run(
        executable,
        args,
        workingDirectory: directory,
        environment: environment,
      );
      final output = '${result.stdout}${result.stderr}';
      return GitResult(ok: result.exitCode == 0, output: output);
    } on ProcessException catch (e) {
      return GitResult(ok: false, output: '$executable tidak bisa dijalankan: ${e.message}');
    }
  });

  /// Menjalankan [body] dengan lingkungan yang sudah tahu tokennya.
  ///
  /// Skrip askpass-nya tinggal di folder sementara berizin `0700` dan dihapus
  /// begitu perintahnya selesai, jadi tokennya tidak tertinggal di disk lebih
  /// lama dari yang diperlukan.
  Future<GitResult> _withAuth(Future<GitResult> Function(Map<String, String>) body) async {
    final secret = token;
    if (secret == null || secret.isEmpty) return body(_nonInteractive);

    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('wptex-git-');
      if (!Platform.isWindows) {
        await Process.run('chmod', <String>['700', temp.path]);
      }
      final tokenFile = File(p.join(temp.path, 'token'));
      await tokenFile.writeAsString(secret, flush: true);
      // Tanpa baris baru di belakangnya: git memakai isi berkas ini apa adanya
      // sebagai nama pengguna, dan `\n` yang ikut terbawa membuat server
      // menolaknya.
      await File(
        p.join(temp.path, 'user'),
      ).writeAsString(username.isEmpty ? 'x-access-token' : username, flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', <String>['600', tokenFile.path]);
      }

      final script = File(p.join(temp.path, Platform.isWindows ? 'askpass.bat' : 'askpass.sh'));
      // Git bertanya dua kali: nama pengguna lalu sandi. GitHub, GitLab, dan
      // Gitea semuanya menerima token sebagai sandi dengan nama pengguna apa
      // pun, dan `x-access-token` adalah nama yang dipakai GitHub sendiri.
      await script.writeAsString(
        Platform.isWindows
            ? '@echo off\r\n'
                  'echo %* | findstr /I "username" >nul\r\n'
                  'if %errorlevel%==0 (type "%~dp0user") else (type "%~dp0token")\r\n'
            : '#!/bin/sh\n'
                  'case "\$1" in\n'
                  '  *[Uu]sername*) cat "\$(dirname "\$0")/user" ;;\n'
                  '  *) cat "\$(dirname "\$0")/token" ;;\n'
                  'esac\n',
        flush: true,
      );
      if (!Platform.isWindows) {
        await Process.run('chmod', <String>['700', script.path]);
      }

      return await body(<String, String>{
        ..._nonInteractive,
        'GIT_ASKPASS': script.path,
        // Tanpa ini git di beberapa sistem lebih memilih helper yang sudah
        // terpasang dan mengabaikan askpass, lalu gagal tanpa alasan jelas.
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'credential.helper',
        'GIT_CONFIG_VALUE_0': '',
      });
    } finally {
      if (temp != null && temp.existsSync()) {
        await temp.delete(recursive: true);
      }
    }
  }

  Future<GitResult> _stream(
    String directory,
    List<String> args, {
    void Function(String line)? onOutput,
    required String okMessage,
  }) async {
    return _withAuth((environment) async {
      final buffer = StringBuffer();
      final Process process;
      try {
        process = await Process.start(
          executable,
          args,
          workingDirectory: directory,
          environment: environment,
        );
      } on ProcessException catch (e) {
        return GitResult(ok: false, output: '$executable tidak bisa dijalankan: ${e.message}');
      }

      final done = <Future<void>>[];
      void collect(Stream<List<int>> stream) {
        done.add(
          stream.transform(const SystemEncoding().decoder).forEach((chunk) {
            buffer.write(chunk);
            onOutput?.call(chunk);
          }),
        );
      }

      collect(process.stdout);
      collect(process.stderr);
      final exitCode = await process.exitCode;
      // Keluarannya ditunggu sampai habis: tanpa ini baris terakhir — yang
      // justru memuat sebab kegagalannya — kadang belum sampai ke buffer.
      await Future.wait(done);
      final output = buffer.toString();
      return GitResult(ok: exitCode == 0, output: output, message: exitCode == 0 ? okMessage : '');
    });
  }

  static const Map<String, String> _nonInteractive = <String, String>{
    'GIT_TERMINAL_PROMPT': '0',
    'GIT_ASKPASS': 'echo',
    'SSH_ASKPASS': 'echo',
  };
}
