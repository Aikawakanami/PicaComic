import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:sqlite3/sqlite3.dart';

import 'sqlite_test_support.dart';

const mib = 1024 * 1024;

void main() {
  configureTestSqlite();
  late Directory fixture;
  late Directory cacheDirectory;
  late String dbPath;
  CacheManager? manager;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('pica-disk-cache-test-');
    cacheDirectory = Directory('${fixture.path}/cache');
    dbPath = '${fixture.path}/cache.db';
  });

  tearDown(() async {
    await manager?.closeForTesting();
    manager = null;
    fixture.deleteSync(recursive: true);
  });

  CacheManager open({Future<void> Function(File)? deleteFile}) =>
      manager = CacheManager.forTesting(cacheDirectory.path, dbPath,
          deleteFile: deleteFile);

  int fileCount() =>
      cacheDirectory.listSync(recursive: true).whereType<File>().length;

  test(
      'legacy cache retains 2101 files under 16 MiB and trims on lowering limit',
      () async {
    const count = 2101;
    const bytesPerFile = 4096;
    final covers = Directory('${cacheDirectory.path}/0')
      ..createSync(recursive: true);
    final db = sqlite3.open(dbPath);
    // Exercise upgrade from an existing cache schema without a type column.
    db.execute(
        'CREATE TABLE cache (key TEXT PRIMARY KEY NOT NULL, dir TEXT NOT NULL, name TEXT NOT NULL, expires INTEGER NOT NULL)');
    db.execute('BEGIN');
    final insert = db.prepare("INSERT INTO cache VALUES (?, '0', ?, ?)");
    final expiry = DateTime.now().millisecondsSinceEpoch + 60000;
    for (var i = 0; i < count; i++) {
      File('${covers.path}/$i').writeAsBytesSync(Uint8List(bytesPerFile));
      insert.execute(['cover-$i', '$i', expiry + i]);
    }
    insert.dispose();
    db.execute('COMMIT');
    db.dispose();

    final cache = open();
    await cache.setLimitSize(16);
    expect(cache.currentSize, count * bytesPerFile);
    expect(fileCount(), count);
    expect(await cache.readCache('cover-0'), isNotNull);

    await cache.setLimitSize(1);
    expect(cache.currentSize, mib);
    expect(fileCount(), mib ~/ bytesPerFile);
    expect(await cache.readCache('cover-0'), isNull);
    expect((await cache.readCache('cover-${count - 1}'))?.bytes.length,
        bytesPerFile);
  });

  test('streaming writes evict by bytes and keep newly returned data and type',
      () async {
    final cache = open();
    await cache.setLimitSize(1);
    final contents = Uint8List(mib * 3 ~/ 4);
    await cache.writeCache('old', contents);
    final cover = await cache.openWrite('new');
    await cover.writeBytes(contents);
    await cover.close(type: 'png');
    expect(await cache.readCache('old'), isNull);
    expect((await cache.readCache('new'))?.type, 'png');
    expect(cache.currentSize, contents.length);

    final oversized = await cache.openWrite('oversized');
    await oversized.writeBytes(Uint8List(2 * mib));
    await oversized.close();
    expect(await cache.readCache('oversized'), isNull);
    expect(await oversized.file.exists(), isFalse);
    expect(await cache.readCache('new'), isNotNull);
    expect(cache.currentSize, contents.length);
  });

  test(
      'replacement, missing files, orphan files and in-flight writes stay consistent',
      () async {
    cacheDirectory.createSync();
    File('${cacheDirectory.path}/abandoned').writeAsBytesSync(Uint8List(mib));
    final cache = open();
    await cache.setLimitSize(1);
    await cache.writeCache('replace', Uint8List(700 * 1024));
    expect(await File('${cacheDirectory.path}/abandoned').exists(), isFalse);
    final oldPath = (await cache.readCache('replace'))!.path;
    final other = await cache.openWrite('in-flight');
    await cache.writeCache('replace', Uint8List(100 * 1024));
    expect(await File(oldPath).exists(), isFalse);
    expect(cache.currentSize, 100 * 1024);
    await File((await cache.readCache('replace'))!.path).delete();
    expect(await cache.readCache('replace'), isNull);
    await cache.delete('replace');
    expect(cache.currentSize, 0);
    await cache.clear();
    expect(await other.file.exists(), isTrue);
    await other.writeBytes(Uint8List(10));
    await other.close();
    expect(cache.currentSize, 10);
  });

  test('a failed deletion stops without spinning and can retry', () async {
    bool fail = true;
    int attempts = 0;
    final cache = open(deleteFile: (file) async {
      attempts++;
      if (fail) throw FileSystemException('Injected failure');
      await file.delete();
    });
    await cache.setLimitSize(2);
    await cache.writeCache('old', Uint8List(mib));
    await cache.writeCache('new', Uint8List(mib ~/ 2));
    await cache.setLimitSize(1).timeout(const Duration(seconds: 5));
    expect(attempts, 2);
    expect(cache.currentSize, mib + mib ~/ 2);
    fail = false;
    await cache.checkCache();
    expect(cache.currentSize, mib ~/ 2);
    expect(await cache.readCache('new'), isNotNull);
  });

  test('60 pages of simultaneous cover writes stay responsive at 1 MiB',
      () async {
    final cache = open();
    await cache.setLimitSize(1);
    final watch = Stopwatch()..start();
    var lastTick = 0;
    var ticks = 0;
    var longestGap = 0;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 25), (_) {
      final elapsed = watch.elapsedMilliseconds;
      final gap = elapsed - lastTick;
      if (gap > longestGap) longestGap = gap;
      lastTick = elapsed;
      ticks++;
    });
    final data = Uint8List(8192);
    try {
      for (var page = 0; page < 60; page++) {
        await Future.wait(List.generate(36, (index) async {
          final cover = await cache.openWrite('page-$page-$index');
          await cover.writeBytes(data);
          await cover.close(type: 'png');
        }));
        expect(cache.currentSize, lessThanOrEqualTo(mib));
      }
      expect(await cache.readCache('page-0-0'), isNull);
      expect(await cache.readCache('page-59-35'), isNotNull);
      expect(cache.currentSize, mib);
      expect(fileCount(), 128);
      expect(ticks, greaterThan(0));
      expect(longestGap, lessThan(5000));
      print('2160 covers, ${watch.elapsedMilliseconds} ms, '
          '$ticks heartbeat ticks, max gap ${longestGap} ms, ${fileCount()} files');
    } finally {
      heartbeat.cancel();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
