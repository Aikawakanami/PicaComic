import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/import_database.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/reading_stats.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zip_flutter/zip_flutter.dart';

// Run ONLY in the independent .devtest.importcheck package. All data is neutral
// and generated here; this target never imports a user's backup or account.
void createFixtures(String root) {
  final db = sqlite3.open('$root/favorites.db');
  db.execute(
      'CREATE TABLE folder_order(folder_name TEXT PRIMARY KEY, order_value INT)');
  db.execute('BEGIN');
  for (var folder = 0; folder < 10; folder++) {
    db.execute(
        '''CREATE TABLE fixture$folder(target TEXT, name TEXT, author TEXT,
      type INT, tags TEXT, cover_path TEXT, time TEXT, display_order INT,
      PRIMARY KEY(target, type))''');
    db.execute(
        'INSERT INTO folder_order VALUES (?, ?)', ['fixture$folder', folder]);
    final insert = db
        .prepare('INSERT INTO fixture$folder VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    for (var row = 0; row < 2523; row++) {
      insert.execute(
          ['id$row', 'Fixture $row', '', row % 2, '', '', '2026-01-01', row]);
    }
    insert.dispose();
  }
  // Same target, different source type must survive the merge.
  db.execute(
      "INSERT INTO fixture0 VALUES ('id0', 'Other type', '', 2, '', '', '2026-01-01', 2523)");
  db.execute('COMMIT');
  db.dispose();
  final history = sqlite3.open('$root/history.db');
  // Covers compatibility with exports predating max_page.
  history.execute('''CREATE TABLE history(target TEXT PRIMARY KEY, title TEXT,
    subtitle TEXT, cover TEXT, time INT, type INT, ep INT, page INT, readEpisode TEXT)''');
  history.execute('''CREATE TABLE image_favorites(id TEXT, title TEXT NOT NULL,
    cover TEXT NOT NULL, ep INT NOT NULL, page INT NOT NULL, other TEXT NOT NULL,
    PRIMARY KEY(id, ep, page))''');
  history.execute('BEGIN');
  final insert =
      history.prepare('INSERT INTO history VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)');
  for (var i = 0; i < 7028; i++) {
    insert.execute(['h$i', 'History $i', '', '', i, 2, 1, 3, '1']);
  }
  insert.dispose();
  for (var i = 0; i < 6; i++) {
    history.execute('INSERT INTO image_favorites VALUES (?, ?, ?, ?, ?, ?)',
        ['h$i', 'Image $i', '', 1, i, '{}']);
  }
  history.execute('COMMIT');
  history.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixtures;
  late String archive;

  setUpAll(() async {
    await App.init();
    // No personal settings or network synchronization in this package.
    appdata.settings[45] = '';
    appdata.settings[53] = '0';
    await LocalFavoritesManager().init();
    fixtures = await Directory(App.cachePath).createTemp('import-fixture-');
    final root = fixtures.path;
    await Isolate.run(() => createFixtures(root));
    await File('$root/history.db').copy('${App.dataPath}/history_temp.db');
    await HistoryManager().init(); // Recovers the pending import on startup.
    SingleInstanceCookieJar('${App.dataPath}/cookies.db');
    final data = appdata.toJson();
    data['settings'] = List<String>.of(appdata.settings)
      ..[0] = 'fixture-setting';
    data['favoriteTags'] = ['fixture-tag'];
    data['blockingKeywords'] = ['fixture-block'];
    await File('$root/appdata').writeAsString(jsonEncode(data));
    archive = '$root/valid.picadata';
    final zip = ZipFile.open(archive);
    zip.addFile('appdata', '$root/appdata');
    zip.addFile('local_favorite.db', '$root/favorites.db');
    zip.addFile('history.db', '$root/history.db');
    zip.close();
  });

  testWidgets('startup resumes 7028 histories and 6 image favorites',
      (tester) async {
    expect(HistoryManager().length, 7028);
    expect(ImageFavoriteManager.length, 6);
    expect(HistoryManager().findSync('h0')!.page, 3);
    expect(File('${App.dataPath}/history_temp.db').existsSync(), isFalse);
  });

  testWidgets(
      'large archive, responsive event loop, duplicate import, persisted settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('Import fixture')));
    var beats = 0;
    final timer =
        Timer.periodic(const Duration(milliseconds: 10), (_) => beats++);
    final watch = Stopwatch()..start();
    expect(await importDataFromFile(archive, checkVersion: false), isTrue);
    timer.cancel();
    watch.stop();
    final manager = LocalFavoritesManager();
    expect(manager.folderNames.length, 10);
    expect(
        manager.folderNames
            .fold<int>(0, (sum, folder) => sum + manager.count(folder)),
        25231);
    expect(manager.comicExists('fixture0', 'id0', 0), isTrue);
    expect(manager.comicExists('fixture0', 'id0', 2), isTrue);
    expect(beats, greaterThan(0));
    debugPrint(
        'IMPORT_FIXTURE elapsed_ms=${watch.elapsedMilliseconds} heartbeat=$beats');
    expect(await importDataFromFile(archive, checkVersion: false), isTrue);
    expect(manager.count('fixture0'), 2524);
    expect(HistoryManager().length, 7028);
    expect(ImageFavoriteManager.length, 6);
    expect(appdata.settings[0], 'fixture-setting');
    final settings =
        jsonDecode(await File('${App.dataPath}/settings').readAsString());
    expect(settings[0], 'fixture-setting');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('favoriteTags'), ['fixture-tag']);
    appdata.settings[0] = 'newer-local-setting';
    appdata.settings[46] = '9999999999';
    expect(await importDataFromFile(archive), isTrue);
    expect(appdata.settings[0], 'newer-local-setting');
  });

  testWidgets('database transaction rolls back and pending file is retained',
      (tester) async {
    final root = fixtures.path;
    final target = '$root/rollback.db';
    final db = sqlite3.open(target);
    db.execute(
        'CREATE TABLE folder_order(folder_name TEXT PRIMARY KEY, order_value INT)');
    db.execute('''CREATE TABLE fixture0(target TEXT, name TEXT, author TEXT,
      type INT, tags TEXT, cover_path TEXT, time TEXT, display_order INT,
      PRIMARY KEY(target, type))''');
    db.execute('''CREATE TRIGGER reject_fixture BEFORE INSERT ON fixture0
      WHEN NEW.target = 'id100' BEGIN SELECT RAISE(ABORT, 'fixture rejection'); END''');
    db.dispose();
    await expectLater(
        mergeFavoriteDatabases(target, '$root/favorites.db', true),
        throwsA(anything));
    final check = sqlite3.open(target);
    expect(check.select('SELECT COUNT(*) FROM fixture0').first[0], 0);
    check.dispose();
    expect(File('$root/favorites.db').existsSync(), isTrue);
  });

  testWidgets(
      'invalid archive leaves services usable and a later retry succeeds',
      (tester) async {
    final root = fixtures.path;
    final broken = '$root/broken.picadata';
    final zip = ZipFile.open(broken);
    zip.addFile('appdata', '$root/appdata'); // Missing favorites database.
    zip.close();
    expect(await importDataFromFile(broken, checkVersion: false), isFalse);
    expect(
        SingleInstanceCookieJar.instance!
            .loadForRequest(Uri.parse('https://example.invalid')),
        isEmpty);
    expect(HistoryManager().length, 7028);
    expect(await importDataFromFile(archive, checkVersion: false), isTrue);
    expect(
        Directory(App.dataPath).listSync().where(
            (item) => item.path.split('/').last.startsWith('data-import-')),
        isEmpty);
  });

  testWidgets('user archive round trip restores and merges chapter progress',
      (tester) async {
    const key = ('jm', 'progress-fixture');
    final stats = ReadingStatistics.instance;
    stats.recordChapter(key, 'a', 30, catalog: ['a', 'b', 'c']);
    stats.recordChapter(key, 'b', 15);
    stats.recordProgress(key, {'a': 20, 'b': 7});
    final progressArchive = '${fixtures.path}/progress.picadata';
    await Directory('${App.dataPath}/comic_source').create(recursive: true);
    expect(await exportDataToFile(false, progressArchive), progressArchive);

    stats.clear();
    stats.recordProgress(key, {'a': 25});
    for (var i = 0; i < 2; i++) {
      expect(await importDataFromFile(progressArchive, checkVersion: false),
          isTrue);
      expect(stats.progress(key), (pages: 32, complete: false));
      expect(stats.metrics(key).imageLabel, '45+');
      expect(HistoryManager().findSync('h0')!.page, 3);
    }
    expect(
        (stats.exportData({key})['progress'] as List).map(
            (row) => (row['chapter_id'], row['furthest_page'])),
        unorderedEquals([('a', 25), ('b', 7)]));
  });
}
