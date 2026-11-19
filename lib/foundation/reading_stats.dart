import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'app.dart';
import 'reading_image_count.dart';

typedef ReadingIdentity = (String, String);
typedef ReadingProgress = ({int pages, bool complete});

const _statisticsSchemaVersion = 2;

class ReadingMetrics {
  const ReadingMetrics(
      {this.count = 0,
      this.elapsedMs = 0,
      this.images,
      this.imagesComplete = false});
  final int count;
  final int elapsedMs;
  final int? images;
  final bool imagesComplete;
  String get imageLabel =>
      images == null ? '未获取' : '$images${imagesComplete ? '' : '+'}';
  String get durationLabel {
    final duration = Duration(milliseconds: elapsedMs);
    return '${duration.inHours}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}

/// Separate from favorite-folder tables and legacy target-only history keys.
class ReadingStatistics {
  static ReadingStatistics? _instance;
  static ReadingStatistics get instance =>
      _instance ??= ReadingStatistics.open('${App.dataPath}/reading_stats.db',
          historyPath: '${App.dataPath}/history.db');

  ReadingStatistics.open(this.path, {this.historyPath})
      : db = sqlite3.open(path) {
    if (db.select('PRAGMA user_version').first[0] > _statisticsSchemaVersion) {
      db.dispose();
      throw const FormatException('Unsupported statistics database');
    }
    db.execute('PRAGMA busy_timeout = 5000');
    db.execute('''CREATE TABLE IF NOT EXISTS reading_sessions (
      session_id TEXT PRIMARY KEY, source_key TEXT NOT NULL, comic_id TEXT NOT NULL,
      elapsed_ms INTEGER NOT NULL CHECK(elapsed_ms >= 0),
      counted INTEGER NOT NULL CHECK(counted IN (0,1)), updated_at INTEGER NOT NULL)''');
    db.execute(
        'CREATE INDEX IF NOT EXISTS reading_session_comic ON reading_sessions(source_key,comic_id)');
    db.execute('''CREATE TABLE IF NOT EXISTS comic_totals (
      source_key TEXT, comic_id TEXT, read_count INTEGER, elapsed_ms INTEGER,
      PRIMARY KEY(source_key,comic_id))''');
    db.execute('''CREATE TABLE IF NOT EXISTS image_books (
      source_key TEXT, comic_id TEXT, total_hint INTEGER, chapter_ids TEXT,
      known_count INTEGER, complete INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL, PRIMARY KEY(source_key,comic_id))''');
    db.execute('''CREATE TABLE IF NOT EXISTS image_chapters (
      source_key TEXT, comic_id TEXT, chapter_id TEXT, pages INTEGER NOT NULL CHECK(pages >= 0),
      updated_at INTEGER NOT NULL, PRIMARY KEY(source_key,comic_id,chapter_id))''');
    db.execute('''CREATE TABLE IF NOT EXISTS chapter_progress (
      source_key TEXT NOT NULL, comic_id TEXT NOT NULL, chapter_id TEXT NOT NULL,
      furthest_page INTEGER NOT NULL CHECK(furthest_page > 0),
      PRIMARY KEY(source_key,comic_id,chapter_id))''');
    db.execute('PRAGMA user_version = $_statisticsSchemaVersion');
  }

  final String path;
  final String? historyPath;
  final Database db;
  int revision = 0;

  void _total(ReadingIdentity key) => db.execute(
      '''INSERT OR REPLACE INTO comic_totals
    SELECT ?, ?, COALESCE(SUM(counted),0), COALESCE(SUM(elapsed_ms),0)
    FROM reading_sessions WHERE source_key=? AND comic_id=?''',
      [key.$1, key.$2, key.$1, key.$2]);

  void checkpoint(String sessionId, ReadingIdentity key, int elapsedMs,
      {required bool counted, required int updatedAt}) {
    if (elapsedMs <= 0 || key.$1.isEmpty || key.$2.isEmpty) return;
    db.execute('BEGIN IMMEDIATE');
    try {
      _session(sessionId, key, elapsedMs, counted ? 1 : 0, updatedAt);
      _total(key);
      db.execute('COMMIT');
      revision++;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _session(String id, ReadingIdentity key, int ms, int counted, int time) {
    if (id.isEmpty ||
        key.$1.isEmpty ||
        key.$2.isEmpty ||
        ms < 0 ||
        (counted != 0 && counted != 1) ||
        (counted == 1 && ms < 10000)) {
      throw const FormatException('Invalid reading session');
    }
    final old = db.select(
        'SELECT source_key,comic_id FROM reading_sessions WHERE session_id=?',
        [id]);
    if (old.isNotEmpty &&
        (old.first['source_key'] != key.$1 ||
            old.first['comic_id'] != key.$2)) {
      throw const FormatException('Reading session identity conflict');
    }
    db.execute('''INSERT INTO reading_sessions VALUES (?,?,?,?,?,?)
      ON CONFLICT(session_id) DO UPDATE SET
        elapsed_ms=MAX(elapsed_ms,excluded.elapsed_ms),
        counted=MAX(counted,excluded.counted), updated_at=MAX(updated_at,excluded.updated_at)''',
        [id, key.$1, key.$2, ms, counted, time]);
  }

  ReadingMetrics metrics(ReadingIdentity key) {
    final totals = db.select(
        'SELECT * FROM comic_totals WHERE source_key=? AND comic_id=?',
        [key.$1, key.$2]);
    final images = db.select(
        'SELECT * FROM image_books WHERE source_key=? AND comic_id=?',
        [key.$1, key.$2]);
    var count = images.isEmpty ? null : images.first['known_count'] as int?;
    var complete = images.isNotEmpty && images.first['complete'] == 1;
    if (attachReadingHistory(db, historyPath)) {
      final type = const {
            'picacg': 0,
            'ehentai': 1,
            'jm': 2,
            'hitomi': 3,
            'htmanga': 4,
            'nhentai': 6
          }[key.$1] ??
          key.$1.hashCode;
      final old = db.select(
          'SELECT max_page FROM reading_history.history WHERE target=? AND type=?',
          [
            historyTargetForFavorite(type, key.$2),
            historyTypeForFavorite(type)
          ]);
      final legacy =
          old.isEmpty ? null : int.tryParse('${old.first['max_page']}');
      final combined = combineReadingImages(
          count, complete, legacy, singleChapterFavorite(type));
      count = combined.$1;
      complete = combined.$2;
    }
    return ReadingMetrics(
        count: totals.isEmpty ? 0 : totals.first['read_count'],
        elapsedMs: totals.isEmpty ? 0 : totals.first['elapsed_ms'],
        images: count,
        imagesComplete: complete);
  }

  void _book(ReadingIdentity key) =>
      db.execute('''INSERT OR IGNORE INTO image_books
    (source_key,comic_id,updated_at) VALUES (?,?,0)''', [key.$1, key.$2]);

  void recordTotal(ReadingIdentity key, int count, {int? updatedAt}) {
    if (count <= 0 || key.$1.isEmpty || key.$2.isEmpty) return;
    _book(key);
    db.execute(
        '''UPDATE image_books SET total_hint=?,known_count=?,complete=1,updated_at=?
      WHERE source_key=? AND comic_id=?''',
        [
          count,
          count,
          updatedAt ?? DateTime.now().millisecondsSinceEpoch,
          key.$1,
          key.$2
        ]);
    revision++;
  }

  void recordCatalog(ReadingIdentity key, Iterable<String> chapters,
      {int? updatedAt}) {
    if (key.$1.isEmpty || key.$2.isEmpty) return;
    final ids = chapters.toSet().toList()..sort();
    if (ids.isEmpty) return;
    _book(key);
    final encoded = jsonEncode(ids);
    final old = db.select(
        'SELECT chapter_ids FROM image_books WHERE source_key=? AND comic_id=?',
        [key.$1, key.$2]).first['chapter_ids'];
    if (old != encoded) {
      db.execute('''UPDATE image_books SET chapter_ids=?,
        total_hint=CASE WHEN chapter_ids IS NULL THEN total_hint ELSE NULL END,updated_at=?
        WHERE source_key=? AND comic_id=?''', [
        encoded,
        updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        key.$1,
        key.$2
      ]);
      _images(key);
      revision++;
    }
  }

  void recordChapter(ReadingIdentity key, String chapter, int pages,
      {Iterable<String>? catalog, int? updatedAt}) {
    if (pages <= 0 || chapter.isEmpty || key.$1.isEmpty || key.$2.isEmpty) {
      return;
    }
    if (catalog != null) recordCatalog(key, catalog, updatedAt: updatedAt);
    _book(key);
    final time = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    db.execute('''INSERT INTO image_chapters VALUES (?,?,?,?,?)
      ON CONFLICT(source_key,comic_id,chapter_id) DO UPDATE SET
        pages=excluded.pages,updated_at=excluded.updated_at
      WHERE excluded.updated_at >= image_chapters.updated_at''',
        [key.$1, key.$2, chapter, pages, time]);
    _images(key);
    revision++;
  }

  void _images(ReadingIdentity key) {
    _book(key);
    final book = db.select(
        'SELECT * FROM image_books WHERE source_key=? AND comic_id=?',
        [key.$1, key.$2]).first;
    final catalog = book['chapter_ids'] == null
        ? null
        : Set<String>.from(jsonDecode(book['chapter_ids']));
    final rows = db.select(
        'SELECT chapter_id,pages FROM image_chapters WHERE source_key=? AND comic_id=?',
        [key.$1, key.$2]);
    final counts = {
      for (final row in rows)
        if (catalog == null || catalog.contains(row['chapter_id']))
          row['chapter_id'] as String: row['pages'] as int
    };
    final hint = book['total_hint'] as int?;
    final complete = hint != null ||
        (catalog != null &&
            catalog.isNotEmpty &&
            catalog.every(counts.containsKey));
    final count = hint ??
        (counts.isEmpty ? null : counts.values.fold<int>(0, (a, b) => a + b));
    db.execute(
        'UPDATE image_books SET known_count=?,complete=? WHERE source_key=? AND comic_id=?',
        [count, complete ? 1 : 0, key.$1, key.$2]);
  }

  void recordProgress(ReadingIdentity key, Map<String, int> pages) {
    if (pages.isEmpty) return;
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final entry in pages.entries) {
        _saveProgress(key, entry.key, entry.value);
      }
      db.execute('COMMIT');
      revision++;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _saveProgress(ReadingIdentity key, String chapter, int page) {
    if (key.$1.isEmpty || key.$2.isEmpty || chapter.isEmpty || page <= 0) {
      throw const FormatException('Invalid chapter progress');
    }
    db.execute('''INSERT INTO chapter_progress VALUES (?,?,?,?)
      ON CONFLICT(source_key,comic_id,chapter_id) DO UPDATE SET
        furthest_page=excluded.furthest_page
      WHERE excluded.furthest_page > chapter_progress.furthest_page''',
        [key.$1, key.$2, chapter, page]);
  }

  ReadingProgress? progress(ReadingIdentity key) {
    final rows = db.select('''SELECT p.chapter_id,p.furthest_page,c.pages,b.chapter_ids
      FROM chapter_progress p
      JOIN image_chapters c USING (source_key,comic_id,chapter_id)
      JOIN image_books b USING (source_key,comic_id)
      WHERE p.source_key=? AND p.comic_id=?''', [key.$1, key.$2]);
    if (rows.isEmpty) return null;
    final encoded = rows.first['chapter_ids'] as String?;
    final catalog = encoded == null ? null : Set<String>.from(jsonDecode(encoded));
    var pageCount = 0;
    var finished = 0;
    for (final row in rows) {
      if (catalog != null && !catalog.contains(row['chapter_id'])) continue;
      final length = row['pages'] as int;
      if (length <= 0) continue;
      final page = min(length, row['furthest_page'] as int);
      pageCount += page;
      if (page == length) finished++;
    }
    if (pageCount == 0) return null;
    return (pages: pageCount, complete: catalog != null && finished == catalog.length);
  }

  Map<String, dynamic> exportData([Set<ReadingIdentity>? keys]) {
    List<Map<String, dynamic>> rows(String table) => db
        .select('SELECT * FROM $table')
        .where((row) =>
            keys == null ||
            keys.contains(
                (row['source_key'] as String, row['comic_id'] as String)))
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    return {
      'version': 1,
      'sessions': rows('reading_sessions'),
      'books': rows('image_books'),
      'chapters': rows('image_chapters'),
      'progress': rows('chapter_progress')
    };
  }

  /// Cumulative checkpoints for one session merge by max; different sessions add.
  void mergeData(Map<String, dynamic> data) {
    if (data['version'] != 1) {
      throw const FormatException('Unsupported reading statistics');
    }
    final keys = <ReadingIdentity>{};
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final row in data['sessions'] as List) {
        final key = (row['source_key'] as String, row['comic_id'] as String);
        final ms = row['elapsed_ms'] as int;
        final counted = row['counted'] as int;
        if (ms < 0 || (counted != 0 && counted != 1)) {
          throw const FormatException('Invalid reading checkpoint');
        }
        _session(row['session_id'] as String, key, ms, counted,
            row['updated_at'] as int);
        keys.add(key);
      }
      for (final row in data['books'] as List) {
        final key = (row['source_key'] as String, row['comic_id'] as String);
        final ids = row['chapter_ids'] as String?;
        if (ids != null) List<String>.from(jsonDecode(ids));
        final hint = row['total_hint'] as int?;
        if (hint != null && hint < 0) {
          throw const FormatException('Invalid image count');
        }
        db.execute('''INSERT INTO image_books
          (source_key,comic_id,total_hint,chapter_ids,updated_at) VALUES (?,?,?,?,?)
          ON CONFLICT(source_key,comic_id) DO UPDATE SET total_hint=excluded.total_hint,
            chapter_ids=excluded.chapter_ids,updated_at=excluded.updated_at
          WHERE excluded.updated_at > image_books.updated_at OR
            (excluded.updated_at = image_books.updated_at AND COALESCE(excluded.total_hint,-1) > COALESCE(image_books.total_hint,-1))''',
            [key.$1, key.$2, hint, ids, row['updated_at'] as int]);
        keys.add(key);
      }
      for (final row in data['chapters'] as List) {
        final key = (row['source_key'] as String, row['comic_id'] as String);
        final pages = row['pages'] as int;
        if (pages < 0) throw const FormatException('Invalid chapter count');
        db.execute('''INSERT INTO image_chapters VALUES (?,?,?,?,?)
          ON CONFLICT(source_key,comic_id,chapter_id) DO UPDATE SET
          pages=excluded.pages,updated_at=excluded.updated_at
          WHERE excluded.updated_at >= image_chapters.updated_at''', [
          key.$1,
          key.$2,
          row['chapter_id'] as String,
          pages,
          row['updated_at'] as int
        ]);
        keys.add(key);
      }
      for (final row in (data['progress'] as List? ?? const [])) {
        _saveProgress((row['source_key'] as String, row['comic_id'] as String),
            row['chapter_id'] as String, row['furthest_page'] as int);
      }
      for (final key in keys) {
        _total(key);
        _images(key);
      }
      db.execute('COMMIT');
      revision++;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void clear() {
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final table in [
        'reading_sessions',
        'comic_totals',
        'image_books',
        'image_chapters',
        'chapter_progress'
      ]) {
        db.execute('DELETE FROM $table');
      }
      db.execute('COMMIT');
      revision++;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => db.dispose();

  void snapshotTo(String destination) {
    // VACUUM INTO produces a consistent standalone database, including indexes.
    db.execute('VACUUM INTO ?', [destination]);
  }

  Future<void> mergePending() async {
    final pending = File('${File(path).parent.path}/reading_stats_temp.db');
    if (!pending.existsSync()) return;
    final target = path;
    final source = pending.path;
    await Isolate.run(() => mergeReadingStatisticsFiles(target, source));
    await pending.delete();
    revision++;
  }
}

void validateReadingStatistics(String path) {
  final input = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    if (input.select('PRAGMA quick_check').any((row) => row[0] != 'ok')) {
      throw const FormatException('Invalid statistics database');
    }
    for (final entry in {
      'reading_sessions':
          'session_id,source_key,comic_id,elapsed_ms,counted,updated_at',
      'image_books': 'source_key,comic_id,total_hint,chapter_ids,updated_at',
      'image_chapters': 'source_key,comic_id,chapter_id,pages,updated_at',
    }.entries) {
      input.select('SELECT ${entry.value} FROM ${entry.key} LIMIT 0');
    }
    final version = input.select('PRAGMA user_version').first[0];
    if (version != 1 && version != _statisticsSchemaVersion) {
      throw const FormatException('Unsupported statistics database');
    }
    if (version == _statisticsSchemaVersion) {
      input.select('SELECT source_key,comic_id,chapter_id,furthest_page '
          'FROM chapter_progress LIMIT 0');
    }
  } finally {
    input.dispose();
  }
}

void mergeReadingStatisticsFiles(String target, String source) {
  validateReadingStatistics(source);
  final input = sqlite3.open(source, mode: OpenMode.readOnly);
  final output = ReadingStatistics.open(target);
  try {
    List<Map<String, dynamic>> rows(String table) => input
        .select('SELECT * FROM $table')
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    output.mergeData({
      'version': 1,
      'sessions': rows('reading_sessions'),
      'books': rows('image_books'),
      'chapters': rows('image_chapters'),
      if (input.select('PRAGMA user_version').first[0] == _statisticsSchemaVersion)
        'progress': rows('chapter_progress')
    });
  } finally {
    input.dispose();
    output.close();
  }
}

/// One tracker per reader route; chapters pause/resume the same tracker.
class ReadingSessionTracker {
  ReadingSessionTracker(
      {required this.store,
      required this.identity,
      int Function()? monotonicMs,
      int Function()? wallMs,
      String? sessionId,
      this.onError})
      : sessionId = sessionId ?? _newId(),
        _clock = monotonicMs ?? (() => (_watch..start()).elapsedMilliseconds),
        _wall = wallMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _last = _clock();
  }
  static final Stopwatch _watch = Stopwatch()..start();
  static String _newId() => '${DateTime.now().microsecondsSinceEpoch}-'
      '${List.generate(4, (_) => Random.secure().nextInt(0x7fffffff).toRadixString(16)).join()}';
  final ReadingStatistics store;
  final ReadingIdentity identity;
  final String sessionId;
  final void Function(Object, StackTrace)? onError;
  final int Function() _clock;
  final int Function() _wall;
  late int _last;
  int _elapsed = 0;
  int _savedElapsed = 0;
  int _lastActiveWall = 0;
  bool _active = false;
  bool _closed = false;
  final _reachedPages = <String, int>{};
  final _pendingPages = <String, int>{};
  int get elapsedMs =>
      _elapsed + (_active && !_closed ? max(0, _clock() - _last) : 0);
  bool get counted => elapsedMs >= 10000;
  DateTime? get lastReadAt => _lastActiveWall == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_lastActiveWall);
  void _sample() {
    final now = _clock();
    if (_active && now > _last) {
      _elapsed += now - _last;
      _lastActiveWall = _wall();
    }
    _last = now;
  }

  void setActive(bool value) {
    if (_closed || _active == value) return;
    _sample();
    _active = value;
    if (!value) checkpoint();
  }

  void observeChapterPage(String chapter, int page) {
    if (_closed || page <= (_reachedPages[chapter] ?? 0)) return;
    _reachedPages[chapter] = page;
    _pendingPages[chapter] = page;
  }

  void checkpoint() {
    if (_closed) return;
    _sample();
    try {
      if (_pendingPages.isNotEmpty) {
        store.recordProgress(identity, _pendingPages);
        _pendingPages.clear();
      }
      if (_elapsed != _savedElapsed) {
        store.checkpoint(sessionId, identity, _elapsed,
            counted: _elapsed >= 10000, updatedAt: _lastActiveWall);
        _savedElapsed = _elapsed;
      }
    } catch (error, stack) {
      if (onError == null) rethrow;
      onError!(error, stack);
    }
  }

  void close() {
    if (_closed) return;
    checkpoint();
    _closed = true;
    _active = false;
  }
}
