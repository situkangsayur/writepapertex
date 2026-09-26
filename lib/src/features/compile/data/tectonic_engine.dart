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
    Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Size);
typedef _CompileDart =
    int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);

/// Argumen untuk isolate, karena kompilasi memblokir dan bisa berjalan lama.
class _Job {
  const _Job(this.tex, this.out, this.cache, this.progress);
  final String tex;
  final String out;
  final String cache;

  /// Berkas tempat mesinnya menuliskan langkah demi langkah.
  final String progress;
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

  /// Berapa lama boleh **tidak ada kemajuan** sebelum kompilasi dihentikan.
  ///
  /// Bukan batas waktu total. Kompilasi pertama sebuah disertasi memang bisa
  /// makan sepuluh menit — mengunduh berpuluh paket dan font, menjalankan
  /// bibtex, lalu mengulang TeX sampai rujukannya mantap — dan memotongnya di
  /// menit kelima berarti pekerjaan yang benar dibunuh tepat sebelum selesai.
  /// Yang pantas dicurigai adalah diamnya: mesin yang tidak melaporkan apa
  /// pun selama tiga menit memang sedang tersangkut.
  static const Duration idleTimeout = Duration(minutes: 3);

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

    // Mesinnya menulis kemajuannya ke berkas ini; dibaca sambil menunggu.
    // Tanpa itu satu-satunya yang terlihat selama beberapa menit adalah
    // kalimat "Menjalankan Tectonic", yang tidak bisa dibedakan dari
    // aplikasi yang menggantung.
    final progressPath = p.join(buildDir, 'kemajuan.log');
    final progressFile = File(progressPath);
    if (progressFile.existsSync()) await progressFile.delete();

    var shown = 0;
    var lastActivity = DateTime.now();
    final watcher = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (onOutput == null || !progressFile.existsSync()) return;
      try {
        final lines = progressFile.readAsLinesSync();
        for (var i = shown; i < lines.length; i++) {
          if (lines[i].trim().isNotEmpty) onOutput(lines[i]);
        }
        if (lines.length != shown) lastActivity = DateTime.now();
        shown = lines.length;
      } on FileSystemException {
        // Berkasnya sedang ditulis mesin; percobaan berikutnya 400 md lagi.
      }
    });

    final ({int code, String message}) outcome;
    try {
      outcome = await _runWithLimit(
        _Job(p.join(projectDir, mainFile), outPath, cache, progressPath),
        idleTimeout,
        () => lastActivity,
      );
    } finally {
      watcher.cancel();
    }
    final (:code, :message) = outcome;

    final ok = code == 0 && File(outPath).existsSync();

    // Log LaTeX yang sebenarnya — dengan nomor baris dan nama berkasnya —
    // hanya ada kalau mesinnya sempat menulisnya. Itu yang paling berguna
    // saat gagal; pesan Tectonic sendiri sering hanya "the LaTeX engine
    // failed".
    final texLog = File(p.join(buildDir, '${p.basenameWithoutExtension(mainFile)}.log'));
    final logText = texLog.existsSync() ? await texLog.readAsString() : '';
    final log = ok ? 'Selesai.' : <String>[message, logText].where((t) => t.isNotEmpty).join('\n');
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
  static Future<({int code, String message})> _runWithLimit(
    _Job job,
    Duration idleLimit,
    DateTime Function() lastActivity,
  ) async {
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

    // Pengawas yang menghitung diam, bukan lamanya. Selama mesinnya masih
    // melaporkan sesuatu, ia dibiarkan bekerja.
    final watchdog = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (completer.isCompleted) {
        timer.cancel();
        return;
      }
      if (DateTime.now().difference(lastActivity()) < idleLimit) return;
      timer.cancel();
      completer.complete((
        code: 7,
        message:
            'Mesin berhenti melapor selama ${idleLimit.inMinutes} menit, jadi '
            'kompilasinya dihentikan. Kalau ini kompilasi pertama, paket TeX '
            'sedang diunduh dan jaringannya mungkin putus.',
      ));
    });

    try {
      return await completer.future;
    } finally {
      watchdog.cancel();
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
    final progress = job.progress.toNativeUtf8();
    final err = calloc<Uint8>(errLen).cast<Utf8>();
    try {
      final code = compile(tex, out, cache, progress, err, errLen);
      final message = code == 0 ? '' : err.toDartString();
      return (code: code, message: message.isEmpty ? 'Kompilasi gagal (kode $code)' : message);
    } finally {
      calloc
        ..free(tex)
        ..free(out)
        ..free(cache)
        ..free(progress)
        ..free(err);
    }
  }
}
