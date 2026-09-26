import 'package:flutter_test/flutter_test.dart';
import 'package:writepapertex/src/features/git/domain/git_messages.dart';

void main() {
  group('normaliseRemoteUrl', () {
    test('alamat SSH jadi HTTPS', () {
      expect(
        normaliseRemoteUrl('git@github.com:situkangsayur/latex-doc-test.git'),
        'https://github.com/situkangsayur/latex-doc-test.git',
      );
    });

    test('alamat SSH lengkap dengan skema juga', () {
      expect(
        normaliseRemoteUrl('ssh://git@gitea.kantor:tim/paper.git'),
        'https://gitea.kantor/tim/paper.git',
      );
    });

    test('tanpa skema dianggap HTTPS', () {
      expect(
        normaliseRemoteUrl('github.com/pemilik/nama.git'),
        'https://github.com/pemilik/nama.git',
      );
    });

    test('spasi dan garis miring di ujung dibuang', () {
      expect(
        normaliseRemoteUrl('  https://github.com/pemilik/nama/  '),
        'https://github.com/pemilik/nama',
      );
    });

    test('alamat halaman web dipangkas jadi alamat repositori', () {
      // Yang tersalin dari bilah alamat peramban, bukan dari tombol Code.
      expect(
        normaliseRemoteUrl('https://github.com/pemilik/nama/tree/main'),
        'https://github.com/pemilik/nama',
      );
      expect(
        normaliseRemoteUrl('https://github.com/pemilik/nama/blob/main/main.tex'),
        'https://github.com/pemilik/nama',
      );
    });

    test('alamat yang sudah benar tidak disentuh', () {
      const url = 'https://github.com/pemilik/nama.git';
      expect(normaliseRemoteUrl(url), url);
    });

    test('http sendiri dibiarkan, bukan dipaksa https', () {
      // Gitea di jaringan kantor kadang memang hanya http.
      expect(normaliseRemoteUrl('http://gitea.kantor/tim/paper.git'),
          'http://gitea.kantor/tim/paper.git');
    });

    test('kosong tetap kosong', () {
      expect(normaliseRemoteUrl('   '), isEmpty);
    });
  });

  group('explainGitFailure', () {
    test('"too many redirects" dijelaskan sebagai kredensial ditolak', () {
      final text = explainGitFailure('too many redirects or authentication replays');
      expect(text, contains('token ditolak'));
      // Pesan aslinya tetap dibawa: kalau dugaannya meleset, itu yang berguna.
      expect(text, contains('too many redirects'));
    });

    test('401 diminta mengisi kredensial', () {
      expect(explainGitFailure('request failed with status code: 401'), contains('token akses'));
    });

    test('403 menyebut izin token', () {
      expect(explainGitFailure('status code: 403'), contains('izin'));
    });

    test('404 menyebut kemungkinan repositori tertutup', () {
      expect(explainGitFailure('remote: Repository not found'), contains('tertutup'));
    });

    test('gagal mencari alamat disebut sebagai persoalan jaringan', () {
      expect(
        explainGitFailure('failed to resolve address for github.com'),
        contains('jaringan'),
      );
    });

    test('keluhan yang tidak dikenali dibiarkan apa adanya', () {
      expect(explainGitFailure('sesuatu yang aneh'), 'sesuatu yang aneh');
    });
  });
}
