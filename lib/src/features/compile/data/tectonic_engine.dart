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
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
      Pointer<Utf8>,
      Size,
    );
typedef _CompileDart =
    int Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
      int,
    );

/// Argumen untuk isolate, karena kompilasi memblokir dan bisa berjalan lama.
class _Job {
  const _Job(this.tex, this.out, this.cache, this.progress, this.fullPass);
  final String tex;
  final String out;
  final String cache;

  /// Berkas tempat mesinnya menuliskan langkah demi langkah.
  final String progress;

  /// True menjalankan BibTeX dan mengulang TeX sampai rujukannya mantap.
  final bool fullPass;
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
    CompilePass pass = CompilePass.full,
    void Function(String line)? onOutput,
  }) async {
    final started = DateTime.now();

    // Tiap langkah dicap waktunya. Pertanyaan "kenapa satu setengah menit?"
    // tidak bisa dijawab oleh bilah kemajuan yang hanya berkata "Menjalankan
    // Tectonic"; yang menjawabnya adalah melihat langkah mana yang memakan
    // menitnya — menyiapkan bundel, atau LaTeX-nya sendiri.
    final timeline = <String>[];
    void say(String text) {
      final line = '[${_elapsed(DateTime.now().difference(started))}] $text';
      timeline.add(line);
      onOutput?.call(line);
    }

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
    // Penanda bundelnya: ukuran asetnya. Cukup untuk membedakan bundel yang
    // berganti isi, dan tidak menuntut membaca 15 MB hanya untuk memutuskan.
    final marker = '${(await rootBundle.load(_bundleAsset)).lengthInBytes}';
    if (await _needsUnpacking(cache, marker)) {
      say('Menyiapkan paket TeX (sekali saja)…');
      final added = await _unpackBundle(cache, marker);
      say('$added paket disiapkan.');
    }

    say('Menjalankan Tectonic…');

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
          if (lines[i].trim().isNotEmpty) say(lines[i].trim());
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
        _Job(p.join(projectDir, mainFile), outPath, cache, progressPath, pass == CompilePass.full),
        idleTimeout,
        () => lastActivity,
      );
    } finally {
      watcher.cancel();
    }
    final (:code, :message) = outcome;

    final ok = code == 0 && File(outPath).existsSync();
    say(ok ? 'Selesai.' : 'Berhenti dengan galat.');

    // Log LaTeX yang sebenarnya — dengan nomor baris dan nama berkasnya —
    // hanya ada kalau mesinnya sempat menulisnya. Itu yang paling berguna
    // saat gagal; pesan Tectonic sendiri sering hanya "the LaTeX engine
    // failed".
    final texLog = File(p.join(buildDir, '${p.basenameWithoutExtension(mainFile)}.log'));
    final logText = texLog.existsSync() ? await texLog.readAsString() : '';
    // Saat berhasil, log-nya adalah catatan waktunya: itu yang berguna
    // dilihat berikutnya. Saat gagal, yang berguna adalah pesan galatnya.
    final log = ok
        ? timeline.join('\n')
        : <String>[...timeline, message, logText].where((t) => t.isNotEmpty).join('\n');
    if (!ok) onOutput?.call('$message\n');

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
      // Hanya lintasan cepat yang bisa "kurang": lintasan penuh sudah
      // mengulang sampai TeX berhenti meminta.
      needsFullPass: ok && pass == CompilePass.quick && logAsksForRerun(logText),
    );
  }

  /// Detik dengan satu angka di belakang koma, untuk cap waktu langkah.
  static String _elapsed(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';

  /// Nama berkas penanda bahwa bundel sudah dibongkar seluruhnya.
  ///
  /// Ditulis paling akhir, jadi pembongkaran yang terputus di tengah tidak
  /// akan dikira selesai. Isinya menyebut bundel yang mana — ukuran asetnya —
  /// karena pembaruan aplikasi bisa membawa bundel yang lebih lengkap, dan
  /// penanda yang hanya berarti "pernah dibongkar" akan membuat bundel baru
  /// itu tidak pernah dipakai pada perangkat yang sudah memasang versi lama.
  static const String _stampFile = '.bundle-siap';

  static const String _bundleAsset = 'assets/bundle/tectonic-cache.zip';

  static Future<bool> _needsUnpacking(String cache, String marker) async {
    final stamp = File(p.join(cache, _stampFile));
    if (!stamp.existsSync()) return true;
    try {
      return !(await stamp.readAsString()).contains(marker);
    } on FileSystemException {
      return true;
    }
  }

  /// Membongkar cache Tectonic dari aset ke [cache].
  ///
  /// Berkas yang sudah ada **tidak** ditimpa. Cache Tectonic beralamat isi —
  /// nama berkasnya adalah sidik jarinya — jadi yang sudah ada pasti sama,
  /// dan yang pernah diunduh sendiri oleh pengguna tetap utuh. Bundelnya
  /// menambah, tidak pernah mengurangi.
  static Future<int> _unpackBundle(String cache, String marker) async {
    final data = await rootBundle.load(_bundleAsset);
    final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List());

    var added = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final resolved = p.normalize(p.join(cache, entry.name));
      // Nama di dalam arsip tidak tepercaya walaupun arsipnya milik sendiri.
      if (!p.isWithin(cache, resolved)) continue;
      final file = File(resolved);
      if (file.existsSync()) continue;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.readBytes() ?? const <int>[]);
      added++;
    }

    await File(p.join(cache, _stampFile)).writeAsString(
      'bundel: $marker\n'
      'dibongkar: ${DateTime.now().toIso8601String()}\n'
      'berkas baru: $added\n',
    );
    return added;
  }

  /// Berapa banyak paket yang sudah tersimpan, dan sebesar apa.
  ///
  /// Dipakai layar untuk menjawab pertanyaan yang wajar: apakah yang sudah
  /// diunduh benar-benar tersimpan dan dipakai lagi oleh proyek berikutnya?
  static Future<({int files, int bytes, String path})> cacheInfo() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'tectonic-cache'));
    if (!dir.existsSync()) return (files: 0, bytes: 0, path: dir.path);

    var files = 0;
    var bytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      files++;
      bytes += await entity.length();
    }
    return (files: files, bytes: bytes, path: dir.path);
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
      final code = compile(tex, out, cache, progress, job.fullPass ? 1 : 0, err, errLen);
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
