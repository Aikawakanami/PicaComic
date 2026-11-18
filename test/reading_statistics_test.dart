import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/reading_stats.dart';
import 'package:sqlite3/sqlite3.dart';
import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureTestSqlite();
  late Directory directory;
  late ReadingStatistics store;
  const key = ('jm', '42');
  setUp(() {
    directory = Directory.systemTemp.createTempSync('pica-stats-test-');
    store = ReadingStatistics.open('${directory.path}/stats.db');
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  test('one effective session across chapters, excludes loading and background',
      () {
    var now = 0;
    final tracker = ReadingSessionTracker(
        store: store,
        identity: key,
        sessionId: 'one',
        monotonicMs: () => now,
        wallMs: () => 100000 + now);
    now += 50000;
    tracker.checkpoint();
    expect(store.metrics(key).elapsedMs, 0);
    tracker.setActive(true);
    now += 6000;
    tracker.setActive(false);
    expect(store.metrics(key).count, 0);
    now += 100000;
    tracker.setActive(true);
    now += 5000;
    tracker.checkpoint();
    expect(store.metrics(key).count, 1);
    tracker.checkpoint();
    now += 3000;
    tracker.setActive(false);
    final end = tracker.lastReadAt;
    now += 500000;
    tracker.close();
    tracker.close();
    expect(store.metrics(key).count, 1);
    expect(store.metrics(key).elapsedMs, 14000);
    expect(tracker.lastReadAt, end);
    final second = ReadingSessionTracker(
        store: store,
        identity: key,
        sessionId: 'two',
        monotonicMs: () => now,
        wallMs: () => 100000 + now);
    second.setActive(true);
    now += 10000;
    second.close();
    expect(store.metrics(key).count, 2);
    expect(store.metrics(key).elapsedMs, 24000);
  });

  test(
      'source identities remain separate, including native NH type distinction',
      () {
    store.checkpoint('jm', key, 10000, counted: true, updatedAt: 1);
    store.checkpoint('nh', ('nhentai', '42'), 20000,
        counted: true, updatedAt: 2);
    expect(store.metrics(key).elapsedMs, 10000);
    expect(store.metrics(('nhentai', '42')).elapsedMs, 20000);
    expect(store.metrics(('ehentai', '42')).count, 0);
  });

  test(
      'partial lower bounds, repeat chapter, refreshed counts and full coverage',
      () {
    expect(store.metrics(key).imageLabel, '未获取');
    store.recordChapter(key, 'a', 30, catalog: ['a', 'b'], updatedAt: 1);
    expect(store.metrics(key).imageLabel, '30+');
    store.recordChapter(key, 'a', 30, catalog: ['a', 'b'], updatedAt: 2);
    expect(store.metrics(key).images, 30);
    store.recordChapter(key, 'b', 40, catalog: ['a', 'b'], updatedAt: 3);
    expect(store.metrics(key).imageLabel, '70');
    store.recordChapter(key, 'a', 25, catalog: ['a', 'b'], updatedAt: 4);
    expect(store.metrics(key).images, 65);
    store.recordCatalog(key, ['a', 'b', 'c'], updatedAt: 5);
    expect(store.metrics(key).imageLabel, '65+');
    store.recordCatalog(key, ['a', 'c'], updatedAt: 6);
    expect(store.metrics(key).imageLabel, '25+');
  });

  test(
      'trusted whole count survives first catalog discovery, invalidates on change',
      () {
    store.recordTotal(key, 90, updatedAt: 1);
    store.recordChapter(key, 'a', 30, catalog: ['a', 'b'], updatedAt: 2);
    expect(store.metrics(key).imageLabel, '90');
    store.recordCatalog(key, ['a', 'b', 'c'], updatedAt: 3);
    expect(store.metrics(key).imageLabel, '30+');
    store.recordTotal(key, 100, updatedAt: 4);
    expect(store.metrics(key).imageLabel, '100');
  });

  test(
      'older checkpoints cannot shrink a session; repeated import is idempotent',
      () {
    store.checkpoint('s', key, 18000, counted: true, updatedAt: 5);
    store.recordChapter(key, 'a', 30, catalog: ['a', 'b'], updatedAt: 5);
    final payload =
        jsonDecode(jsonEncode(store.exportData())) as Map<String, dynamic>;
    store.checkpoint('s', key, 25000, counted: true, updatedAt: 7);
    store.mergeData(payload);
    store.mergeData(payload);
    expect(store.metrics(key).elapsedMs, 25000);
    expect(store.metrics(key).count, 1);
    expect(store.metrics(key).imageLabel, '30+');
    store.checkpoint('other', key, 12000, counted: true, updatedAt: 8);
    store.mergeData(payload);
    expect(store.metrics(key).elapsedMs, 37000);
    expect(store.metrics(key).count, 2);
    expect(store.exportData({('ehentai', 'unrelated')})['sessions'], isEmpty);
  });

  test(
      'bad payload rolls back every preceding session and preserves original data',
      () {
    store.checkpoint('old', key, 15000, counted: true, updatedAt: 1);
    final data = store.exportData();
    final sessions = data['sessions'] as List;
    sessions.add(<String, dynamic>{
      ...Map<String, dynamic>.from(sessions.first),
      'session_id': 'new'
    });
    sessions.add(<String, dynamic>{
      ...Map<String, dynamic>.from(sessions.first),
      'session_id': 'old',
      'comic_id': 'conflict'
    });
    expect(() => store.mergeData(data), throwsFormatException);
    expect(store.metrics(key).elapsedMs, 15000);
    expect(store.db.select('SELECT * FROM reading_sessions'), hasLength(1));
  });

  test('consistent database snapshot restores and can merge twice', () {
    store.checkpoint('a', key, 15000, counted: true, updatedAt: 1);
    store.recordChapter(key, '@single', 35, catalog: ['@single'], updatedAt: 1);
    final snapshot = '${directory.path}/snapshot.db';
    store.snapshotTo(snapshot);
    validateReadingStatistics(snapshot);
    final restoredPath = '${directory.path}/restored.db';
    mergeReadingStatisticsFiles(restoredPath, snapshot);
    mergeReadingStatisticsFiles(restoredPath, snapshot);
    final restored = ReadingStatistics.open(restoredPath);
    try {
      expect(restored.metrics(key).count, 1);
      expect(restored.metrics(key).elapsedMs, 15000);
      expect(restored.metrics(key).imageLabel, '35');
    } finally {
      restored.close();
    }
  });

  test('rejects future schema and malformed optional database before import',
      () {
    final path = '${directory.path}/invalid.db';
    final invalid = sqlite3.open(path);
    invalid.execute('PRAGMA user_version=9');
    invalid.dispose();
    expect(() => ReadingStatistics.open(path), throwsFormatException);
    expect(() => validateReadingStatistics(path), throwsA(anything));
  });

  test('clearing application statistics leaves a usable empty schema', () {
    store.checkpoint('s', key, 12000, counted: true, updatedAt: 1);
    store.recordTotal(key, 30);
    store.clear();
    expect(store.metrics(key).count, 0);
    expect(store.metrics(key).images, isNull);
    store.checkpoint('again', key, 10000, counted: true, updatedAt: 2);
    expect(store.metrics(key).count, 1);
  });
}
