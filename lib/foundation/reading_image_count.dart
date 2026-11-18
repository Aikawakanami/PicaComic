import 'dart:io';
import 'dart:math';
import 'package:sqlite3/sqlite3.dart';

int historyTypeForFavorite(int type) => type == 6 ? 5 : type;
bool singleChapterFavorite(int type) => const [1, 3, 4, 6].contains(type);
String historyTargetForFavorite(int type, String target) => type == 3
    ? RegExp(r'(\d+)(?:\.html)?(?:[?#].*)?$').firstMatch(target)?.group(1) ??
        target
    : target;

bool attachReadingHistory(Database db, String? path) {
  if (path == null || !File(path).existsSync()) return false;
  if (!db
      .select('PRAGMA database_list')
      .any((row) => row['name'] == 'reading_history')) {
    db.execute('ATTACH DATABASE ? AS reading_history', [path]);
  }
  final columns = db
      .select('PRAGMA reading_history.table_info(history)')
      .map((row) => row['name'])
      .toSet();
  if (!columns.containsAll(['target', 'type', 'max_page'])) return false;
  db.createFunction(
      functionName: 'reading_history_target',
      argumentCount: const AllowedArgumentCount(2),
      deterministic: true,
      function: (args) =>
          historyTargetForFavorite(args[0] as int, args[1] as String));
  return true;
}

/// History is a chapter-sized lower bound unless the source has one chapter.
/// A fresh complete whole-book count takes precedence over legacy progress.
(int?, bool) combineReadingImages(
    int? known, bool complete, int? legacy, bool legacyComplete) {
  if (complete && known != null) return (known, true);
  if (legacy == null || legacy <= 0) return (known, complete);
  return (max(known ?? 0, legacy), legacyComplete && legacy >= (known ?? 0));
}

const legacyReadingImagesSql =
    'CASE WHEN CAST(h.max_page AS INTEGER)>0 THEN CAST(h.max_page AS INTEGER) END';
String effectiveReadingImagesSql(bool history) {
  if (!history) return 'b.known_count';
  return '''CASE WHEN b.complete=1 THEN b.known_count
    WHEN b.known_count IS NULL THEN ($legacyReadingImagesSql)
    WHEN ($legacyReadingImagesSql) IS NULL THEN b.known_count
    ELSE MAX(b.known_count,($legacyReadingImagesSql)) END''';
}

String effectiveReadingImagesCompleteSql(bool history) => !history
    ? 'b.complete'
    : '''CASE WHEN b.complete=1 THEN 1
    WHEN f.type IN (1,3,4,6) AND ($legacyReadingImagesSql)>=COALESCE(b.known_count,0)
    THEN 1 ELSE 0 END''';
