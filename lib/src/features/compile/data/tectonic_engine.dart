import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  /// Berapa lama satu kompilasi boleh berjalan sebelum dihentikan.
  ///
  /// Tanpa batas ini, jaringan yang mati di tengah unduhan bundel membuat
  /// kompilasi menggantung selamanya dengan spinner yang tidak pernah
  /// berhenti, dan tidak ada cara membatalkannya.
  static const Duration timeout = Duration(minutes: 5);

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

    // Paket TeX dibongkar dari dalam APK, bukan diunduh. Mengunduhnya satu
    // per satu membuat kompilasi pertama makan menit dan bergantung jaringan
    // — dan satu unduhan yang gagal berakhir sebagai "failed to open input
    // file hyph-en-us.tex", yang tidak menyebut jaringan sama sekali.
    if (await _needsUnpacking(cache)) {
      onOutput?.call('Menyiapkan paket TeX (sekali saja)…\n');
      await _unpackBundle(cache);
    }

    onOutput?.call('Menjalankan Tectonic…\n');

    final (:code, :message) = await _runWithLimit(
      _Job(p.join(projectDir, mainFile), outPath, cache),
      timeout,
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

  /// Nama berkas penanda bahwa bundel sudah dibongkar seluruhnya.
  ///
  /// Ditulis paling akhir, jadi pembongkaran yang terputus di tengah tidak
  /// akan dikira selesai.
  static const String _stampFile = '.bundle-siap';

  static Future<bool> _needsUnpacking(String cache) async =>
      !File(p.join(cache, _stampFile)).existsSync();

  /// Membongkar cache Tectonic dari aset ke [cache].
  static Future<void> _unpackBundle(String cache) async {
    final data = await rootBundle.load('assets/bundle/tectonic-cache.zip');
    final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List());

    for (final entry in archive) {
      if (!entry.isFile) continue;
      final resolved = p.normalize(p.join(cache, entry.name));
      // Nama di dalam arsip tidak tepercaya walaupun arsipnya milik sendiri.
      if (!p.isWithin(cache, resolved)) continue;
      final file = File(resolved);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.readBytes() ?? const <int>[]);
    }

    await File(
      p.join(cache, _stampFile),
    ).writeAsString('Dibongkar dari aset pada ${DateTime.now().toIso8601String()}\n');
  }

  /// Menjalankan kompilasi di isolate, dan menghentikannya kalau kelewat lama.
  ///
  /// Isolate-nya dimatikan sungguhan, bukan hanya future-nya yang diabaikan:
  /// pekerjaan yang ditinggalkan terus berjalan, memegang berkas dan memakan
  /// baterai tanpa ada yang menunggunya.
  static Future<({int code, String message})> _runWithLimit(_Job job, Duration limit) async {
    final port = ReceivePort();
    final errors = ReceivePort();
    final completer = Completer<({int code, String message})>();

    final isolate = await Isolate.spawn<(SendPort, _Job)>(
      _isolateEntry,
      (port.sendPort, job),
      onError: errors.sendPort,
      errorsAreFatal: true,
    );

    port.listen((dynamic value) {
      if (!completer.isCompleted && value is List && value.length == 2) {
        completer.complete((code: value[0] as int, message: value[1] as String));
      }
    });
    errors.listen((dynamic value) {
      if (!completer.isCompleted) {
        completer.complete((code: 6, message: 'Mesin berhenti: $value'));
      }
    });

    try {
      return await completer.future.timeout(limit);
    } on TimeoutException {
      return (
        code: 7,
        message:
            'Kompilasi dihentikan setelah ${limit.inMinutes} menit. Kalau ini '
            'kompilasi pertama, paket TeX sedang diunduh dan jaringannya '
            'mungkin terlalu lambat — coba lagi dengan sambungan yang lebih baik.',
      );
    } finally {
      isolate.kill(priority: Isolate.immediate);
      port.close();
      errors.close();
    }
  }

  static void _isolateEntry((SendPort, _Job) args) {
    final (send, job) = args;
    final result = _compileBlocking(job);
    send.send(<dynamic>[result.code, result.message]);
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
