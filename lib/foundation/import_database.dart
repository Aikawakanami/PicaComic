import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

String _identifier(String name) => '"${name.replaceAll('"', '""')}"';

Set<String> _tables(Database db) => db
    .select("SELECT name FROM sqlite_master WHERE type = 'table'")
    .map((row) => row['name'] as String)
    .toSet();

void _check(Database db) {
  if (db.select('PRAGMA quick_check').any((row) => row[0] != 'ok')) {
    throw const FormatException('Invalid import database');
  }
}

void _requireColumns(Database db, String table, List<String> columns) {
  final actual = db
      .select('PRAGMA table_info(${_identifier(table)})')
      .map((row) => row['name'])
      .toSet();
  if (!actual.containsAll(columns)) {
    throw const FormatException('Unsupported import database schema');
  }
}

const _favoriteColumns = [
  'target',
  'name',
  'author',
  'type',
  'tags',
  'cover_path',
  'time',
];
const _historyColumns = [
  'target',
  'title',
  'subtitle',
  'cover',
  'time',
  'type',
  'ep',
  'page',
  'readEpisode',
];
const _imageColumns = ['id', 'title', 'cover', 'ep', 'page', 'other'];

/// Runs before live files or services are changed. Old history exports may
/// omit max_page and image_favorites.
void validateImportDatabase(String path, {required bool favorites}) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    _check(db);
    if (favorites) {
      for (final table in _tables(db).where((name) =>
          name != 'folder_order' &&
          name != 'folder_sync' &&
          !name.startsWith('sqlite_'))) {
        _requireColumns(db, table, _favoriteColumns);
      }
    } else {
      _requireColumns(db, 'history', _historyColumns);
      if (_tables(db).contains('image_favorites')) {
        _requireColumns(db, 'image_favorites', _imageColumns);
      }
    }
  } finally {
    db.dispose();
  }
}

/// Import avoids UI updates, WebDAV uploads and cover downloads per record.
/// Each database commits atomically, retaining existing records by their key.
Future<int> mergeFavoriteDatabases(String target, String source, bool append) =>
    Isolate.run(() => _mergeFavorites(target, source, append));

int _mergeFavorites(String target, String source, bool append) {
  validateImportDatabase(source, favorites: true);
  final input = sqlite3.open(source, mode: OpenMode.readOnly);
  final output = sqlite3.open(target);
  var added = 0;
  try {
    output.execute('PRAGMA busy_timeout = 5000');
    output.execute('BEGIN IMMEDIATE');
    try {
      final tables = _tables(input);
      final folders = tables
          .where((name) =>
              name != 'folder_order' &&
              name != 'folder_sync' &&
              !name.startsWith('sqlite_'))
          .toList();
      final order = <String, int>{};
      if (tables.contains('folder_order')) {
        for (final row in input.select('SELECT * FROM folder_order')) {
          order[row['folder_name'] as String] = row['order_value'] as int;
        }
      }
      folders.sort((a, b) => (order[a] ?? 0).compareTo(order[b] ?? 0));
      for (final folder in folders) {
        final table = _identifier(folder);
        output.execute('''CREATE TABLE IF NOT EXISTS $table (
          target TEXT, name TEXT, author TEXT, type INT, tags TEXT,
          cover_path TEXT, time TEXT, display_order INT,
          PRIMARY KEY(target, type))''');
        final bound = output
                .select(
                    'SELECT ${append ? 'MAX' : 'MIN'}(display_order) FROM $table')
                .first[0] as int? ??
            0;
        var position = bound;
        final statement = output.prepare('''INSERT INTO $table
          (target, name, author, type, tags, cover_path, time, display_order)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(target, type) DO NOTHING''');
        try {
          final hasOrder = input
              .select('PRAGMA table_info($table)')
              .any((row) => row['name'] == 'display_order');
          final rows = input.select('SELECT * FROM $table'
              '${hasOrder ? ' ORDER BY display_order' : ''}');
          // Prepending backwards keeps the imported block in its source order.
          for (final row in append ? rows : rows.reversed) {
            final next = position + (append ? 1 : -1);
            statement.execute([
              ..._favoriteColumns.map((column) => row[column]),
              next,
            ]);
            if (output.getUpdatedRows() > 0) {
              added++;
              position = next;
            }
          }
        } finally {
          statement.dispose();
        }
        output.execute('''INSERT INTO folder_order(folder_name, order_value)
          VALUES (?, ?) ON CONFLICT(folder_name) DO NOTHING''',
            [folder, order[folder] ?? 0]);
      }
      output.execute('COMMIT');
    } catch (_) {
      output.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    output.dispose();
    input.dispose();
  }
  return added;
}

Future<(int, int)> mergeHistoryDatabases(String target, String source) =>
    Isolate.run(() => _mergeHistory(target, source));

(int, int) _mergeHistory(String target, String source) {
  validateImportDatabase(source, favorites: false);
  final input = sqlite3.open(source, mode: OpenMode.readOnly);
  final output = sqlite3.open(target);
  var history = 0;
  var images = 0;
  try {
    output.execute('PRAGMA busy_timeout = 5000');
    output.execute('BEGIN IMMEDIATE');
    try {
      final hasMaxPage = input
          .select('PRAGMA table_info(history)')
          .any((row) => row['name'] == 'max_page');
      final insertHistory = output.prepare('''INSERT INTO history
        (${_historyColumns.join(',')}, max_page)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(target) DO NOTHING''');
      try {
        for (final row in input.select('SELECT * FROM history')) {
          insertHistory.execute([
            ..._historyColumns.map((column) => row[column]),
            hasMaxPage ? row['max_page'] : null,
          ]);
          history += output.getUpdatedRows();
        }
      } finally {
        insertHistory.dispose();
      }
      if (_tables(input).contains('image_favorites')) {
        final insertImage = output.prepare('''INSERT INTO image_favorites
          (${_imageColumns.join(',')}) VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(id, ep, page) DO NOTHING''');
        try {
          for (final row in input.select('SELECT * FROM image_favorites')) {
            insertImage
                .execute(_imageColumns.map((column) => row[column]).toList());
            images += output.getUpdatedRows();
          }
        } finally {
          insertImage.dispose();
        }
      }
      output.execute('COMMIT');
    } catch (_) {
      output.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    output.dispose();
    input.dispose();
  }
  return (history, images);
}
