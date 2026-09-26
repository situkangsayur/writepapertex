import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/git_backend.dart';

typedef _Clone7 =
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Size,
    );
typedef _Clone7Dart =
    int Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
    );
typedef _Init5 = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Size);
typedef _Init5Dart = int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);
typedef _Buf3 = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Size);
typedef _Buf3Dart = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _Tok5 = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Size);
typedef _Tok5Dart = int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);
typedef _Commit6 =
    Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Size);
typedef _Commit6Dart =
    int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);

/// Satu pekerjaan git, dijalankan di isolate.
class _Call {
  const _Call(this.op, this.args, {this.caFile = ''});
  final String op;
  final List<String> args;

  /// Berkas sertifikat akar untuk HTTPS; kosong untuk pekerjaan lokal.
  final String caFile;
}

/// Git untuk Android, lewat libgit2 di dalam pustaka mesin.
///
/// Android tidak punya biner `git`. Protokolnya tidak ditulis ulang di sini —
/// libgit2 yang sudah ada dan teruji dipakai, ikut dibundel ke dalam APK.
///
/// Hanya HTTPS dengan token. SSH sengaja tidak didukung: menyimpan kunci
/// privat di tablet menimbulkan persoalan yang lebih besar daripada
/// manfaatnya, sedangkan token bisa dicabut satu per satu.
class GitFfiBackend implements GitBackend {
  const GitFfiBackend({
    this.token,
    this.username = '',
    this.authorName = '',
    this.authorEmail = '',
  });

  /// Token akses; tanpa ini hanya repositori publik yang bisa dibaca.
  final String? token;

  /// Nama pengguna HTTPS. Kosong berarti `x-access-token`.
  final String username;
  final String authorName;
  final String authorEmail;

  static const String _library = 'libwptex_engine.so';

  @override
  String get name => 'libgit2';

  /// Kenapa git tidak bisa dipakai, kalau memang tidak bisa.
  String get unavailableReason =>
      'Pustaka mesin tidak ikut pada build ini, jadi git tidak tersedia.';

  @override
  Future<bool> isAvailable() async {
    try {
      DynamicLibrary.open(_library).lookup<NativeFunction<_Buf3>>('wptex_git_status');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isRepository(String directory) async => Directory('$directory/.git').existsSync();

  @override
  Future<GitStatus?> status(String directory) async {
    if (!await isRepository(directory)) return null;
    final result = await _run(_Call('status', <String>[directory]));
    if (!result.ok) return null;
    try {
      final json = jsonDecode(result.output) as Map<String, dynamic>;
      return GitStatus(
        branch: json['branch'] as String? ?? '',
        remoteUrl: json['remote'] as String? ?? '',
        lastCommit: json['last'] as String? ?? '',
        ahead: (json['ahead'] as num?)?.toInt() ?? 0,
        behind: (json['behind'] as num?)?.toInt() ?? 0,
        changes: <GitChange>[
          for (final c in (json['changes'] as List?) ?? const <dynamic>[])
            if (c is Map)
              GitChange(
                path: c['path'] as String? ?? '',
                status: _codeFor(c['label'] as String? ?? ''),
              ),
        ],
      );
    } catch (_) {
      // JSON yang rusak lebih baik dianggap "tidak tahu" daripada membuat
      // panel git gagal terbuka sama sekali.
      return null;
    }
  }

  /// Label dari Rust dikembalikan ke kode dua huruf yang dipakai GitChange.
  static String _codeFor(String label) => switch (label) {
    'baru' => '??',
    'dihapus' => ' D',
    'dipindah' => 'R ',
    _ => ' M',
  };

  @override
  Future<GitResult> clone({
    required String remoteUrl,
    required String directory,
    String? branch,
    void Function(String line)? onOutput,
  }) async {
    onOutput?.call('Menyalin $remoteUrl…\n');
    final r = await _run(
      _Call('clone', <String>[remoteUrl, directory, token ?? '', username, branch ?? '']),
    );
    return GitResult(ok: r.ok, output: r.output, message: r.ok ? 'Repositori tersalin' : '');
  }

  @override
  Future<GitResult> pull(String directory, {void Function(String line)? onOutput}) async {
    final r = await _run(_Call('pull', <String>[directory, token ?? '', username]));
    return GitResult(ok: r.ok, output: r.output, message: r.ok ? r.output : '');
  }

  @override
  Future<GitResult> commitAll(
    String directory, {
    required String message,
    String? authorName,
    String? authorEmail,
  }) async {
    final r = await _run(
      _Call('commit', <String>[
        directory,
        message,
        authorName ?? this.authorName,
        authorEmail ?? this.authorEmail,
      ]),
    );
    if (r.code == 3) {
      return const GitResult(ok: true, output: '', message: 'Tidak ada perubahan untuk disimpan');
    }
    return GitResult(ok: r.ok, output: r.output, message: r.ok ? 'Tersimpan' : '');
  }

  @override
  Future<GitResult> push(String directory, {void Function(String line)? onOutput}) async {
    onOutput?.call('Mengirim…\n');
    final r = await _run(_Call('push', <String>[directory, token ?? '', username]));
    return GitResult(ok: r.ok, output: r.output, message: r.ok ? 'Terkirim' : '');
  }

  @override
  Future<GitResult> init(String directory, {String branch = 'main'}) async {
    final r = await _run(_Call('init', <String>[directory, '', branch]));
    return GitResult(ok: r.ok, output: r.output, message: r.ok ? 'Repositori dibuat' : '');
  }

  @override
  Future<GitResult> setRemote(String directory, String remoteUrl, {String name = 'origin'}) async {
    // `init` di sisi Rust memasang remote pada repositori yang sudah ada tanpa
    // mengubah apa pun yang lain, jadi memanggilnya lagi sudah cukup.
    final r = await _run(_Call('init', <String>[directory, remoteUrl, '']));
    return GitResult(ok: r.ok, output: r.output, message: r.ok ? 'Remote disetel' : '');
  }

  /// Menjalankan pekerjaan di isolate: jaringan dan pack bisa makan waktu, dan
  /// di thread utama itu berarti antarmuka membeku.
  Future<({bool ok, int code, String output})> _run(_Call call) async {
    // Pekerjaan yang menyentuh jaringan perlu tahu di mana sertifikat akarnya,
    // dan folder aplikasi hanya bisa ditanyakan dari isolate utama.
    final needsNetwork = const <String>{'clone', 'pull', 'push'}.contains(call.op);
    final withCa = needsNetwork
        ? _Call(
            call.op,
            call.args,
            caFile: p.join((await getApplicationSupportDirectory()).path, 'cacert.pem'),
          )
        : call;
    return Isolate.run(() => _blocking(withCa));
  }

  static ({bool ok, int code, String output}) _blocking(_Call call) {
    final lib = DynamicLibrary.open(_library);
    const len = 8192;
    final buf = calloc<Uint8>(len).cast<Utf8>();
    final args = call.args.map((a) => a.toNativeUtf8()).toList();

    try {
      if (call.caFile.isNotEmpty) {
        // Pengaturan sertifikat itu global di libgit2 dan isolate ini baru,
        // jadi dipasang lagi tiap kali — biayanya sekali baca berkas.
        final path = call.caFile.toNativeUtf8();
        try {
          final code = lib.lookupFunction<_Buf3, _Buf3Dart>('wptex_git_set_ca_bundle')(
            path,
            buf,
            len,
          );
          if (code != 0) {
            return (ok: false, code: code, output: buf.toDartString());
          }
        } finally {
          calloc.free(path);
        }
      }

      final code = switch (call.op) {
        'clone' => lib.lookupFunction<_Clone7, _Clone7Dart>('wptex_git_clone')(
          args[0],
          args[1],
          args[2],
          args[3],
          args[4],
          buf,
          len,
        ),
        'status' => lib.lookupFunction<_Buf3, _Buf3Dart>('wptex_git_status')(args[0], buf, len),
        'commit' => lib.lookupFunction<_Commit6, _Commit6Dart>('wptex_git_commit')(
          args[0],
          args[1],
          args[2],
          args[3],
          buf,
          len,
        ),
        'pull' => lib.lookupFunction<_Tok5, _Tok5Dart>('wptex_git_pull')(
          args[0],
          args[1],
          args[2],
          buf,
          len,
        ),
        'push' => lib.lookupFunction<_Tok5, _Tok5Dart>('wptex_git_push')(
          args[0],
          args[1],
          args[2],
          buf,
          len,
        ),
        _ => lib.lookupFunction<_Init5, _Init5Dart>('wptex_git_init')(
          args[0],
          args[1],
          args[2],
          buf,
          len,
        ),
      };
      return (ok: code == 0, code: code, output: buf.toDartString());
    } finally {
      for (final a in args) {
        calloc.free(a);
      }
      calloc.free(buf);
    }
  }
}
