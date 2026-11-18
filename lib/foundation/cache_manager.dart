import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:sqlite3/sqlite3.dart';

typedef CacheHit = ({String path, Uint8List bytes, String? type});

class CacheManager {
  static String get cachePath => '${App.cachePath}/cache';
  static CacheManager? _instance;

  factory CacheManager() =>
      _instance ??= CacheManager._(cachePath, '${App.dataPath}/cache.db');

  @visibleForTesting
  CacheManager.forTesting(String directory, String databasePath,
      {Future<void> Function(File)? deleteFile})
      : this._(directory, databasePath, deleteFile: deleteFile);

  CacheManager._(this._directory, String databasePath,
      {Future<void> Function(File)? deleteFile})
      : _db = sqlite3.open(databasePath),
        _deleteFile = deleteFile ?? _deleteFromDisk {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS cache (
        key TEXT PRIMARY KEY NOT NULL,
        dir TEXT NOT NULL,
        name TEXT NOT NULL,
        expires INTEGER NOT NULL,
        type TEXT
      )
    ''');
    final columns = _db.select('PRAGMA table_info(cache)');
    if (!columns.any((row) => row['name'] == 'type')) {
      _db.execute('ALTER TABLE cache ADD COLUMN type TEXT');
    }
    _db.execute('CREATE INDEX IF NOT EXISTS cache_expires ON cache(expires)');
    _ready = _scanExistingFiles();
  }

  final String _directory;
  final Database _db;
  final Future<void> Function(File) _deleteFile;
  final _sizes = <String, int>{};
  final _unindexed = <String>{};
  late final Future<void> _ready;
  Future<void> _pending = Future.value();
  int _currentSize = 0;
  int _dir = 0;
  int _limitSize = 500 * 1024 * 1024;
  DateTime? _nextExpiryCheck;
  static const _batchSize = 32;
  static const _defaultDuration = 7 * 24 * 60 * 60 * 1000;

  int get currentSize => _currentSize;
  int get limitSize => _limitSize;

  Future<void> setLimitSize(int size) {
    _limitSize = size.clamp(0, 0x7fffffff) * 1024 * 1024;
    return checkCache();
  }

  static String _pathKey(String path) => path.replaceAll('\\', '/');
  File _file(Row row) => File('$_directory/${row['dir']}/${row['name']}');

  Future<void> _scanExistingFiles() async {
    final root = Directory(_directory);
    await root.create(recursive: true);
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      final path = _pathKey(entity.path);
      _setSize(path, stat.size);
      _unindexed.add(path);
    }
    for (final row in _db.select('SELECT dir, name FROM cache')) {
      _unindexed.remove(_pathKey(_file(row).path));
    }
  }

  void _setSize(String path, int bytes) {
    _currentSize += bytes - (_sizes[path] ?? 0);
    if (bytes == 0) {
      _sizes.remove(path);
    } else {
      _sizes[path] = bytes;
    }
  }

  /// Serialize index changes and evictions. A failed operation leaves the queue usable.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) async {
      await _ready;
      return operation();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Row? _find(String key) => _db.select(
      'SELECT key, dir, name, type FROM cache WHERE key = ?',
      [key]).firstOrNull;

  Future<String?> findCache(String key) async {
    await _ready;
    final row = _find(key);
    if (row == null) return null;
    final file = _file(row);
    return await file.exists() ? file.path : null;
  }

  /// A cache entry evicted between lookup and read is a cache miss.
  Future<CacheHit?> readCache(String key) async {
    await _ready;
    final row = _find(key);
    if (row == null) return null;
    final file = _file(row);
    try {
      return (
        path: file.path,
        bytes: await file.readAsBytes(),
        type: row['type'] as String?
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<void> writeCache(String key, Uint8List data,
      [int duration = _defaultDuration]) async {
    if (data.length > _limitSize) return;
    final writer = await openWrite(key);
    try {
      await writer.file.writeAsBytes(data);
      await writer.close(duration: duration);
    } catch (_) {
      await writer.cancel();
      rethrow;
    }
  }

  Future<CachingFile> openWrite(String key) => _enqueue(() async {
        _dir = (_dir + 1) % 100;
        final dir = '$_dir';
        var name = md5.convert(utf8.encode(key)).toString();
        var file = File('$_directory/$dir/$name');
        while (await file.exists()) {
          name = md5.convert(utf8.encode(name)).toString();
          file = File('$_directory/$dir/$name');
        }
        await file.create(recursive: true);
        return CachingFile._(this, key, dir, name, file);
      });

  Future<void> _publish(CachingFile writer, int duration, String? type) =>
      _enqueue(() async {
        final path = _pathKey(writer.file.path);
        final bytes = await writer.file.length();
        _setSize(path, bytes);
        _unindexed.add(path);
        if (bytes > _limitSize) {
          await _removeFile(path);
          return;
        }
        final previous = _find(writer.key);
        _db.execute('''
          INSERT OR REPLACE INTO cache (key, dir, name, expires, type)
          VALUES (?, ?, ?, ?, ?)
        ''', [
          writer.key,
          writer.dir,
          writer.name,
          DateTime.now().millisecondsSinceEpoch + duration,
          type
        ]);
        _unindexed.remove(path);
        if (previous != null) {
          final oldPath = _pathKey(_file(previous).path);
          if (path != oldPath) {
            _unindexed.add(oldPath);
            await _removeFile(oldPath);
          }
        }
        writer._published = true;
        await _tryMaintain();
      });

  Future<void> checkCache() => _enqueue(() => _tryMaintain(forceExpiry: true));

  Future<void> _tryMaintain({bool forceExpiry = false}) async {
    try {
      await _maintain(forceExpiry: forceExpiry);
    } catch (error) {
      _nextExpiryCheck = null;
      Log.warning('Disk cache', 'Maintenance failed (${error.runtimeType})');
    }
  }

  Future<void> _maintain({bool forceExpiry = false}) async {
    final now = DateTime.now();
    if (forceExpiry ||
        _nextExpiryCheck == null ||
        !now.isBefore(_nextExpiryCheck!)) {
      _nextExpiryCheck = now.add(const Duration(minutes: 1));
      await _evictBatches(expiresBefore: now.millisecondsSinceEpoch);
    }
    if (_currentSize <= _limitSize) return;

    // Files left behind by interrupted writes or older versions have no readers.
    for (final path in _unindexed.toList()) {
      if (_currentSize <= _limitSize) return;
      await _removeFile(path);
    }
    await _evictBatches();
  }

  Future<void> _evictBatches({int? expiresBefore, bool clear = false}) async {
    final expiryOnly = expiresBefore != null;
    while (clear || expiryOnly || _currentSize > _limitSize) {
      final entries = _db.select('''
        SELECT key, dir, name FROM cache
        ${expiryOnly ? 'WHERE expires < ?' : ''}
        ORDER BY expires, rowid LIMIT $_batchSize
      ''', [if (expiryOnly) expiresBefore]);
      if (entries.isEmpty) return;

      final removed = <Row>[];
      for (final row in entries) {
        if (!clear && !expiryOnly && _currentSize <= _limitSize) break;
        if (await _removeFile(_pathKey(_file(row).path))) removed.add(row);
      }
      if (removed.isEmpty) return;
      _deleteRows(removed);
    }
  }

  void _deleteRows(List<Row> rows) {
    final statement = _db.prepare('DELETE FROM cache WHERE key = ?');
    _db.execute('BEGIN');
    try {
      for (final row in rows) {
        statement.execute([row['key']]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      statement.dispose();
    }
  }

  static Future<void> _deleteFromDisk(File file) async {
    await file.delete();
  }

  /// Returns false when the file still exists and cannot be removed.
  Future<bool> _removeFile(String path) async {
    final file = File(path);
    try {
      await _deleteFile(file);
    } on FileSystemException {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        Log.warning('Disk cache', 'Could not remove a cache file');
        return false;
      }
    }
    _setSize(path, 0);
    _unindexed.remove(path);
    return true;
  }

  Future<void> delete(String key) => _enqueue(() async {
        final row = _find(key);
        if (row != null && await _removeFile(_pathKey(_file(row).path))) {
          _db.execute('DELETE FROM cache WHERE key = ?', [key]);
        }
      });

  Future<void> clear() => _enqueue(() async {
        // Unpublished files may belong to downloads still in progress.
        for (final path in _unindexed.toList()) {
          await _removeFile(path);
        }
        await _evictBatches(clear: true);
      });

  Future<void> deleteKeyword(String keyword) => _enqueue(() async {
        final rows = _db.select(
            'SELECT key, dir, name FROM cache WHERE key LIKE ?',
            ['%$keyword%']);
        final removed = <Row>[];
        for (final row in rows) {
          if (await _removeFile(_pathKey(_file(row).path))) removed.add(row);
        }
        if (removed.isNotEmpty) _deleteRows(removed);
      });

  @visibleForTesting
  Future<void> closeForTesting() => _enqueue(() async => _db.dispose());
}

class CachingFile {
  CachingFile._(this._manager, this.key, this.dir, this.name, this.file);

  final CacheManager _manager;
  final String key;
  final String dir;
  final String name;
  final File file;
  final List<int> _buffer = [];
  bool _closed = false;
  bool _published = false;

  Future<void> writeBytes(List<int> data) async {
    _buffer.addAll(data);
    if (_buffer.length > 1024 * 1024) await _flush();
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty) return;
    await file.writeAsBytes(_buffer, mode: FileMode.append);
    _buffer.clear();
  }

  Future<void> close(
      {String? type, int duration = CacheManager._defaultDuration}) async {
    if (_closed) return;
    await _flush();
    await _manager._publish(this, duration, type);
    _closed = true;
  }

  Future<void> cancel() async {
    if (_closed || _published) return;
    _buffer.clear();
    final path = CacheManager._pathKey(file.path);
    await _manager._enqueue(() async {
      if (await _manager._removeFile(path)) return;
      _manager._unindexed.add(path);
      final stat = await file.stat();
      _manager._setSize(path, stat.size);
    });
  }

  void reset() {
    _buffer.clear();
    if (file.existsSync()) file.deleteSync();
  }
}
