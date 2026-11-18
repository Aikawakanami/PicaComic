import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/favorite_query.dart';
import 'package:pica_comic/foundation/reading_stats.dart';
import 'package:sqlite3/sqlite3.dart';
import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureTestSqlite();
  test('legacy chapter counts and new totals share numeric sorting and display',
      () {
    final directory = Directory.systemTemp.createTempSync('pica-image-count-');
    final historyPath = '${directory.path}/history.db';
    final history = sqlite3.open(historyPath);
    history.execute(
        'CREATE TABLE history(target TEXT PRIMARY KEY,type INT,max_page TEXT)');
    history.execute(
        "INSERT INTO history VALUES ('large',2,'233'),('small',2,'500'),('nh',5,'201'),('42',3,'200'),('shared',2,'800')");
    final stats = ReadingStatistics.open('${directory.path}/stats.db',
        historyPath: historyPath);
    final favorites = sqlite3.open('${directory.path}/favorites.db');
    favorites.execute(
        'CREATE TABLE folder(target TEXT,type INT,time TEXT,display_order INT,PRIMARY KEY(target,type))');
    for (final key in [
      (2, 'large'),
      (2, 'small'),
      (6, 'nh'),
      (3, 'https://neutral/42.html'),
      (6, 'shared'),
      (2, 'unknown')
    ]) {
      favorites
          .execute('INSERT INTO folder VALUES (?,?,NULL,0)', [key.$2, key.$1]);
    }
    stats.recordTotal(('jm', 'small'), 28);
    stats.recordChapter(('jm', 'large'), 'a', 30, catalog: ['a', 'b']);
    final query = FavoriteQuery(favorites, stats, historyPath: historyPath);
    try {
      final desc = query.snapshot('folder', FavoriteSort.imageCount, true);
      expect(desc.keys.take(4), [
        (2, 'large'),
        (6, 'nh'),
        (3, 'https://neutral/42.html'),
        (2, 'small')
      ]);
      expect(
          query.snapshot('folder', FavoriteSort.imageCount, false).keys.first,
          (2, 'small'));
      expect(stats.metrics(('jm', 'large')).imageLabel, '233+');
      expect(stats.metrics(('jm', 'small')).imageLabel, '28');
      expect(stats.metrics(('nhentai', 'nh')).imageLabel, '201');
      expect(stats.metrics(('hitomi', 'https://neutral/42.html')).imageLabel,
          '200');
      expect(stats.metrics(('nhentai', 'shared')).images, isNull);
      final rows = query.read(desc);
      expect(rows.first['image_count'], 233);
      expect(rows.first['images_complete'], 0);
      expect(rows[1]['images_complete'], 1);
      expect(rows[3]['image_count'],
          28); // Complete new value wins over old chapter count.
      expect(rows[4]['image_count'],
          isNull); // Equal ID from a different source is ignored.
      stats.recordTotal(('jm', 'large'), 240);
      expect(stats.metrics(('jm', 'large')).imageLabel, '240');
      expect(query.read(desc).first['image_count'], 240);
    } finally {
      favorites.dispose();
      stats.close();
      history.dispose();
      directory.deleteSync(recursive: true);
    }
  });
}
