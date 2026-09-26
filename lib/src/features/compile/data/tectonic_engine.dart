import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/latex_engine.dart';

/// Tanda tangan C dari `wptex_compile`.
typedef _CompileNative =
    Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Size);
typedef _CompileDart =
    int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);

/// Argumen untuk isolate, karena kompilasi memblokir dan bisa berjalan lama.
class _Job {
  const _Job(this.tex, this.out, this.cache);
  final String tex;
  final String out;
  final String cache;
}

/// Mesin TeX yang ikut di dalam aplikasi.
///
/// Android tidak punya TeX Live, jadi mesinnya dibawa sendiri: Tectonic,
/// XeTeX yang dibungkus Rust, dikompilasi untuk `aarch64-linux-android` dan
/// dipanggil lewat `dart:ffi`.
///
/// Dijalankan di isolate terpisah. Satu kompilasi bisa makan beberapa detik,
/// dan di thread utama itu berarti antarmuka membeku.
class TectonicEngine implements LatexEngine {
  const TectonicEngine();

  static const String _library = 'libwptex_engine.so';

  @override
  String get name => 'Tectonic (XeTeX)';

  @override
  String get unavailableReason =>
      'Mesin Tectonic tidak ikut pada build ini. Jalankan '
      'scripts/build-tectonic-android.sh lalu bangun ulang APK-nya.';

  @override
  Future<bool> isAvailable() async {
    try {
      DynamicLibrary.open(_library);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CompileResult> compile({
    required String projectDir,
    required String mainFile,
    void Function(String line)? onOutput,
  }) async {
    final started = DateTime.now();
    final buildDir = await ensureBuildDir(projectDir);
    final outPath = p.join(buildDir, '${p.basenameWithoutExtension(mainFile)}.pdf');

    // Paket TeX yang diunduh Tectonic disimpan di folder milik aplikasi:
    // di Android tidak ada HOME yang boleh ditulisi.
    final support = await getApplicationSupportDirectory();
    final cache = await ensureDir(p.join(support.path, 'tectonic-cache'));

    onOutput?.call('Menjalankan Tectonic…\n');

    final (:code, :message) = await Isolate.run(
      () => _compileBlocking(_Job(p.join(projectDir, mainFile), outPath, cache)),
    );

    final ok = code == 0 && File(outPath).existsSync();
    final log = ok ? 'Selesai.' : message;
    onOutput?.call('$log\n');

    // Pesan Tectonic tidak berbentuk log LaTeX, jadi pengurai biasa sering
    // tidak menemukan apa pun di dalamnya. Kalau itu terjadi sementara
    // kompilasinya gagal, pesannya dipakai apa adanya — kegagalan tanpa
    // alasan yang terlihat adalah hal terburuk yang bisa ditampilkan.
    var messages = const LatexLogParser().parse(log);
    if (!ok && messages.isEmpty) {
      messages = <LatexMessage>[
        for (final line in log.split('\n'))
          if (line.trim().isNotEmpty)
            LatexMessage(severity: LatexSeverity.error, text: line.trim()),
      ];
    }

    return CompileResult(
      ok: ok,
      log: log,
      messages: messages,
      pdfPath: ok ? outPath : null,
      duration: DateTime.now().difference(started),
    );
  }

  /// Memanggil pustaka C. Berjalan di isolate.
  static ({int code, String message}) _compileBlocking(_Job job) {
    final lib = DynamicLibrary.open(_library);
    final compile = lib.lookupFunction<_CompileNative, _CompileDart>('wptex_compile');

    const errLen = 8192;
    final tex = job.tex.toNativeUtf8();
    final out = job.out.toNativeUtf8();
    final cache = job.cache.toNativeUtf8();
    final err = calloc<Uint8>(errLen).cast<Utf8>();
    try {
      final code = compile(tex, out, cache, err, errLen);
      final message = code == 0 ? '' : err.toDartString();
      return (code: code, message: message.isEmpty ? 'Kompilasi gagal (kode $code)' : message);
    } finally {
      calloc
        ..free(tex)
        ..free(out)
        ..free(cache)
        ..free(err);
    }
  }
}
