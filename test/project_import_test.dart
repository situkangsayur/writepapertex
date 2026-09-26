import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/features/project/data/project_import.dart';

void main() {
  group('alamat arsip repositori', () {
    List<String> urls(String repo, {String? branch}) =>
        ProjectImport.archiveUrlsFor(repo, branch: branch);

    test('alamat HTTPS GitHub dikenali', () {
      final u = urls('https://github.com/situkangsayur/writepapertex');
      expect(u, contains('https://github.com/situkangsayur/writepapertex/archive/refs/heads/main.zip'));
    });

    test('akhiran .git dibuang', () {
      final u = urls('https://github.com/a/b.git');
      expect(u.every((x) => !x.contains('.git/')), isTrue);
      expect(u.first, contains('/a/b/archive/'));
    });

    test('alamat SSH diubah jadi HTTPS', () {
      final u = urls('git@github.com:situkangsayur/writepapertex.git');
      expect(u.first, startsWith('https://github.com/situkangsayur/writepapertex/'));
    });

    test('Gitea sendiri ikut jalan', () {
      final u = urls('https://gitea.kantor.id/tim/paper');
      expect(u.first, startsWith('https://gitea.kantor.id/tim/paper/archive/'));
    });

    test('bentuk GitLab ikut dicoba', () {
      final u = urls('https://gitlab.com/tim/paper');
      expect(u.any((x) => x.contains('/-/archive/')), isTrue);
    });

    test('tanpa cabang, main dan master dua-duanya dicoba', () {
      final u = urls('https://github.com/a/b');
      expect(u.any((x) => x.contains('/main.zip')), isTrue);
      expect(u.any((x) => x.contains('/master.zip')), isTrue);
    });

    test('dengan cabang, hanya cabang itu yang dicoba', () {
      final u = urls('https://github.com/a/b', branch: 'tulisan');
      expect(u.every((x) => x.contains('tulisan')), isTrue);
    });

    test('alamat yang tidak masuk akal menghasilkan daftar kosong', () {
      expect(urls(''), isEmpty);
      expect(urls('bukan-alamat'), isEmpty);
    });
  });

  group('membongkar ZIP', () {
    /// Membuat arsip yang isinya dibungkus satu folder, seperti arsip GitHub.
    List<int> wrappedZip() {
      final archive = Archive()
        ..add(ArchiveFile('paper-main/main.tex', 24, r'\documentclass{article}'.codeUnits))
        ..add(ArchiveFile('paper-main/bab/satu.tex', 5, 'satu'.codeUnits));
      return ZipEncoder().encode(archive);
    }

    test('arsip dari penyelenggara git membungkus isinya satu folder', () {
      final archive = ZipDecoder().decodeBytes(wrappedZip());
      // Ini yang dibuang saat membongkar: tanpa itu setiap proyek punya satu
      // lapis folder kosong yang tidak berarti apa-apa.
      expect(archive.every((e) => e.name.startsWith('paper-main/')), isTrue);
    });

    test('arsip tanpa pembungkus tidak ikut dipotong', () {
      final archive = Archive()
        ..add(ArchiveFile('main.tex', 3, 'abc'.codeUnits))
        ..add(ArchiveFile('ref.bib', 3, 'def'.codeUnits));
      final names = ZipDecoder().decodeBytes(ZipEncoder().encode(archive)).map((e) => e.name);
      expect(names.every((n) => !n.contains('/')), isTrue);
    });
  });
}
