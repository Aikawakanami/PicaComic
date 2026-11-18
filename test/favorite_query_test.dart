import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/favorite_query.dart';
import 'package:pica_comic/foundation/reading_stats.dart';
import 'package:sqlite3/sqlite3.dart';
import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureTestSqlite();
  late Directory directory;
  late ReadingStatistics stats;
  late Database db;
  late FavoriteQuery query;
  const folder = 'mixed " folder';
  setUp(() {
    directory = Directory.systemTemp.createTempSync('pica-favorite-query-');
    stats = ReadingStatistics.open('${directory.path}/statistics.db');
    db = sqlite3.open('${directory.path}/favorites.db');
    db.execute(
        'CREATE TABLE ${sqlIdentifier(folder)} (target TEXT,type INT,time TEXT,display_order INT,PRIMARY KEY(target,type))');
    void row(String id, int type, String? time, int order) => db.execute(
        'INSERT INTO ${sqlIdentifier(folder)} VALUES (?,?,?,?)',
        [id, type, time, order]);
    row('a', 2, '2020-01-01 00:00:00', 3);
    row('b', 2, '2022-01-01 00:00:00', 2);
    row('c', 2, '2021-01-01 00:00:00', 1);
    row('a', 6, null, 0);
    stats.checkpoint('jm-a', ('jm', 'a'), 12000, counted: true, updatedAt: 1);
    stats.checkpoint('jm-b', ('jm', 'b'), 25000, counted: true, updatedAt: 1);
    stats.checkpoint('jm-b2', ('jm', 'b'), 10000, counted: true, updatedAt: 1);
    stats.checkpoint('nh-a', ('nhentai', 'a'), 5000,
        counted: false, updatedAt: 1);
    stats.recordChapter(('jm', 'a'), 'one', 30, catalog: ['one', 'two']);
    stats.recordTotal(('jm', 'b'), 25);
    query = FavoriteQuery(db, stats);
  });
  tearDown(() {
    db.dispose();
    stats.close();
    directory.deleteSync(recursive: true);
  });

  test(
      'manual order preserved; last read, session count, duration sort across folder',
      () {
    expect(query.snapshot(folder, FavoriteSort.manual, false).keys,
        [(6, 'a'), (2, 'c'), (2, 'b'), (2, 'a')]);
    expect(query.snapshot(folder, FavoriteSort.lastRead, true).keys,
        [(2, 'b'), (2, 'c'), (2, 'a'), (6, 'a')]);
    expect(query.snapshot(folder, FavoriteSort.readCount, true).keys,
        [(2, 'b'), (2, 'a'), (2, 'c'), (6, 'a')]);
    expect(query.snapshot(folder, FavoriteSort.readTime, true).keys,
        [(2, 'b'), (2, 'a'), (6, 'a'), (2, 'c')]);
    // Sorting never rewrites the user's persisted manual order.
    expect(query.snapshot(folder, FavoriteSort.manual, false).keys.first,
        (6, 'a'));
  });

  test(
      'partial image count participates numerically; unknown always last in both directions',
      () {
    expect(query.snapshot(folder, FavoriteSort.imageCount, true).keys,
        [(2, 'a'), (2, 'b'), (2, 'c'), (6, 'a')]);
    expect(query.snapshot(folder, FavoriteSort.imageCount, false).keys,
        [(2, 'b'), (2, 'a'), (2, 'c'), (6, 'a')]);
    final rows =
        query.read(query.snapshot(folder, FavoriteSort.imageCount, true));
    expect(rows.first['image_count'], 30);
    expect(rows.first['images_complete'], 0);
    expect(
        rows.last['reading_ms'], 5000); // NH type 6 maps to native source key.
  });

  test('snapshot page boundaries do not move as reading metrics update', () {
    final snapshot = query.snapshot(folder, FavoriteSort.readTime, true);
    final first = query.read(snapshot, page: 1, pageSize: 2);
    stats.checkpoint('later', ('jm', 'c'), 100000, counted: true, updatedAt: 2);
    final second = query.read(snapshot, page: 2, pageSize: 2);
    expect(
        [...first, ...second]
            .map((row) => (row['type'], row['target']))
            .toSet(),
        hasLength(4));
    expect(second.last['target'], 'c');
    expect(second.last['reading_ms'], 100000); // Values fresh, order fixed.
    expect(query.snapshot(folder, FavoriteSort.readTime, true).keys.first,
        (2, 'c'));
    expect(query.read(snapshot, page: 99, pageSize: 2), hasLength(2));
    db.execute('DELETE FROM ${sqlIdentifier(folder)} WHERE target=? AND type=?',
        ['c', 2]);
    final updated = query.snapshot(folder, FavoriteSort.manual, false);
    expect(updated.pageCount(2), 2);
    expect(query.read(updated, page: 2, pageSize: 2), hasLength(1));
  });

  test('empty and large old folders page without full metadata materialization',
      () {
    db.execute('DELETE FROM ${sqlIdentifier(folder)}');
    final empty = query.snapshot(folder, FavoriteSort.manual, false);
    expect(empty.pageCount(50), 1);
    expect(query.read(empty, page: 1), isEmpty);
    db.execute('BEGIN');
    final insert =
        db.prepare('INSERT INTO ${sqlIdentifier(folder)} VALUES (?,2,?,?)');
    for (var i = 0; i < 10000; i++) {
      insert.execute(['old-$i', '2020-01-01 00:00:00', i]);
    }
    insert.dispose();
    db.execute('COMMIT');
    final watch = Stopwatch()..start();
    final snapshot = query.snapshot(folder, FavoriteSort.readCount, true);
    final page = query.read(snapshot, page: 200, pageSize: 50);
    watch.stop();
    expect(snapshot.keys, hasLength(10000));
    expect(page, hasLength(50));
    expect(snapshot.pageCount(50), 200);
    expect(
        page.every(
            (row) => row['reading_count'] == 0 && row['image_count'] == null),
        isTrue);
    // Log a measured result, not a brittle machine-dependent time assertion.
    // ignore: avoid_print
    print(
        '10,000 identities + 50 metadata rows: ${watch.elapsedMilliseconds}ms');
  });

  test('view options tolerate old settings and persist choices independently',
      () {
    final defaults =
        FavoriteViewOptions.fromJson({}, paged: true, pageSize: 20);
    expect(defaults.paged, true);
    expect(defaults.pageSize, 20);
    expect(defaults.sort, FavoriteSort.manual);
    final changed = defaults.copyWith(
        sort: FavoriteSort.imageCount, descending: true, pageSize: 100);
    final restored = FavoriteViewOptions.fromJson(changed.toJson());
    expect(restored.sort, FavoriteSort.imageCount);
    expect(restored.descending, true);
    expect(restored.paged, true);
    expect(restored.pageSize, 100);
    expect(FavoriteViewOptions.fromJson({'sort': 999, 'size': -1}).sort,
        FavoriteSort.manual);
    expect(FavoriteViewOptions.fromJson({'sort':999,'descending':true}).descending,false);
    expect(FavoriteViewOptions.fromJson({'size': -1}).pageSize, 60);
    expect(FavoriteViewOptions.fromJson({'size': 50}).pageSize, 60);
    expect(FavoriteViewOptions.fromJson({}, pageSize: 50).pageSize, 60);
    for (final size in [20, 40, 60, 80, 100]) {
      expect(FavoriteViewOptions.fromJson({'size': size}).pageSize, size);
    }
  });
}
