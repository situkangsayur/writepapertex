import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:writepapertex/src/features/project/data/workspace_store.dart';
import 'package:writepapertex/src/features/project/domain/project_profile.dart';

void main() {
  late Directory base;
  late Directory projects;
  late WorkspaceStore store;

  /// Folder proyek sungguhan: store menyaring yang sudah tidak ada di disk.
  String makeProject(String name) {
    final dir = Directory(p.join(projects.path, name))..createSync(recursive: true);
    File(p.join(dir.path, 'main.tex')).writeAsStringSync('% $name\n');
    return dir.path;
  }

  setUp(() {
    base = Directory.systemTemp.createTempSync('wptex-store-');
    projects = Directory(p.join(base.path, 'proyek'))..createSync();
    store = WorkspaceStore(baseDir: base);
  });

  tearDown(() => base.deleteSync(recursive: true));

  test('proyek yang baru diingat ada di puncak daftar', () async {
    final satu = makeProject('satu');
    final dua = makeProject('dua');

    await store.remember(satu);
    await store.remember(dua);

    final loaded = await store.load();
    expect(loaded.map((profile) => profile.name), <String>['dua', 'satu']);
  });

  test('membuka folder yang sama dua kali tidak menduakan entrinya', () async {
    final dir = makeProject('satu');
    await store.remember(dir);
    // Path dengan `./` di tengahnya adalah folder yang sama, dan orang sampai
    // ke sana lewat pemilih folder maupun hasil clone.
    await store.remember(p.join(projects.path, '.', 'satu'));

    expect((await store.load()).length, 1);
  });

  test('alamat remote yang sudah tercatat tidak terhapus saat dibuka lagi', () async {
    final dir = makeProject('satu');
    await store.remember(dir, remoteUrl: 'https://github.com/a/b.git', branch: 'main');
    await store.remember(dir);

    final profile = (await store.load()).single;
    expect(profile.remoteUrl, 'https://github.com/a/b.git');
    expect(profile.branch, 'main');
  });

  test('folder yang sudah dihapus tidak ditawarkan lagi', () async {
    final dir = makeProject('hilang');
    await store.remember(dir);
    Directory(dir).deleteSync(recursive: true);

    expect(await store.load(), isEmpty);
  });

  test('token tidak pernah masuk ke daftar proyek', () async {
    final dir = makeProject('satu');
    final profile = await store.remember(dir);
    await store.saveToken(profile.id, 'rahasia-sekali');

    final listing = File(p.join(base.path, 'projects.json')).readAsStringSync();
    expect(listing, isNot(contains('rahasia-sekali')));
    expect(await store.tokenFor(profile.id), 'rahasia-sekali');
  });

  test('berkas kredensial hanya bisa dibaca pemiliknya', () async {
    final profile = await store.remember(makeProject('satu'));
    await store.saveToken(profile.id, 'rahasia');

    final mode = File(p.join(base.path, 'credentials.json')).statSync().mode;
    // Enam bit terakhir adalah izin golongan dan yang lain; keduanya harus nol.
    expect(mode & 0x3F, 0);
  }, skip: Platform.isWindows ? 'izin POSIX' : false);

  test('melupakan proyek juga melupakan tokennya', () async {
    final profile = await store.remember(makeProject('satu'));
    await store.saveToken(profile.id, 'rahasia');
    await store.forget(profile.id);

    expect(await store.load(), isEmpty);
    expect(await store.tokenFor(profile.id), isNull);
  });

  test('menyunting remote satu proyek tidak menyentuh yang lain', () async {
    final satu = await store.remember(makeProject('satu'));
    await store.remember(makeProject('dua'));

    await store.update(satu.copyWith(remoteUrl: 'https://gitea.kantor/tim/paper.git'));

    final loaded = await store.load();
    expect(loaded.firstWhere((profile) => profile.name == 'satu').remoteUrl, contains('gitea'));
    expect(loaded.firstWhere((profile) => profile.name == 'dua').remoteUrl, isEmpty);
  });

  test('daftar "terakhir dibuka" versi lama ikut terbawa', () async {
    final dir = makeProject('lama');
    File(p.join(base.path, 'recent-projects.json')).writeAsStringSync(
      jsonEncode(<Map<String, String>>[
        <String, String>{'directory': dir, 'openedAt': '2026-01-01T00:00:00.000'},
        <String, String>{
          'directory': p.join(projects.path, 'sudah-hilang'),
          'openedAt': '2026-01-02T00:00:00.000',
        },
      ]),
    );

    final loaded = await store.load();
    expect(loaded.map((profile) => profile.name), <String>['lama']);
    // Berkas lamanya dihapus supaya migrasinya tidak berulang tiap kali dibuka.
    expect(File(p.join(base.path, 'recent-projects.json')).existsSync(), isFalse);
  });

  test('berkas daftar yang rusak tidak membuat aplikasi gagal dibuka', () async {
    File(p.join(base.path, 'projects.json')).writeAsStringSync('{bukan json');
    expect(await store.load(), isEmpty);
  });

  test('daftarnya dibatasi, yang terlama jatuh', () async {
    for (var n = 0; n < WorkspaceStore.max + 3; n++) {
      await store.remember(makeProject('proyek-$n'));
    }
    final loaded = await store.load();
    expect(loaded.length, WorkspaceStore.max);
    expect(loaded.first.name, 'proyek-${WorkspaceStore.max + 2}');
    expect(loaded.map((profile) => profile.name), isNot(contains('proyek-0')));
  });

  test('id sebuah folder tidak bergantung pada bentuk penulisannya', () {
    expect(
      ProjectProfile.idForDirectory('/data/proyek/satu'),
      ProjectProfile.idForDirectory('/data/proyek/./satu/'),
    );
  });

  test('alamat remote dibaca jadi label yang pendek', () {
    ProjectProfile withUrl(String url) => ProjectProfile.forDirectory('/x/satu', remoteUrl: url);

    expect(
      withUrl('https://github.com/situkangsayur/proposal-phd.git').remoteLabel,
      'github.com/situkangsayur/proposal-phd',
    );
    expect(
      withUrl('git@github.com:situkangsayur/proposal-phd.git').remoteLabel,
      'github.com/situkangsayur/proposal-phd',
    );
  });
}
