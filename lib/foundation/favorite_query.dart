import 'package:sqlite3/sqlite3.dart';
import 'reading_stats.dart';
import 'reading_image_count.dart';

typedef FavoriteKey = (int, String);

enum FavoriteSort { manual, lastRead, readCount, readTime, imageCount }

enum FavoriteReadDateFormat {
  dash('yyyy-MM-dd HH:mm:ss'),
  slash('yyyy/MM/dd HH:mm:ss');

  const FavoriteReadDateFormat(this.pattern);
  final String pattern;

  String format(String time) {
    if (this == dash || time.length < 10) return time;
    return time.substring(0, 10).replaceAll('-', '/') + time.substring(10);
  }
}

enum FavoriteReadDurationFormat {
  hoursClock('HH:mm:ss'),
  minutesClock('mm:ss'),
  hoursUnits('XhXmXs'),
  minutesSeconds('XmXs'),
  minutesOnly('Xm');

  const FavoriteReadDurationFormat(this.pattern);
  final String pattern;

  String format(ReadingMetrics metrics) {
    final duration = Duration(milliseconds: metrics.elapsedMs);
    final totalMinutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return switch (this) {
      hoursClock => metrics.durationLabel,
      minutesClock =>
        "${totalMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}",
      hoursUnits =>
        '${duration.inHours}h${totalMinutes % 60}m${seconds}s',
      minutesSeconds => '${totalMinutes}m${seconds}s',
      minutesOnly => '${totalMinutes}m',
    };
  }
}

const favoritePageSizes = [20, 40, 60, 80, 100];
const defaultFavoritePageSize = 60;
int normalizeFavoritePageSize(int? size) =>
    favoritePageSizes.contains(size) ? size! : defaultFavoritePageSize;

class FavoriteViewOptions {
  const FavoriteViewOptions(
      {this.sort = FavoriteSort.manual,
      this.descending = false,
      this.paged = false,
      this.pageSize = defaultFavoritePageSize});
  final FavoriteSort sort;
  final bool descending;
  final bool paged;
  final int pageSize;
  factory FavoriteViewOptions.fromJson(Map<String, dynamic> json,
      {bool paged = false, int pageSize = defaultFavoritePageSize}) {
    final index = json['sort'];
    final size = json['size'] ?? pageSize;
    final sort =
        index is int && index >= 0 && index < FavoriteSort.values.length
            ? FavoriteSort.values[index]
            : FavoriteSort.manual;
    return FavoriteViewOptions(
        sort: sort,
        descending: sort != FavoriteSort.manual && json['descending'] == true,
        paged: json['paged'] is bool ? json['paged'] : paged,
        pageSize: normalizeFavoritePageSize(size is int ? size : null));
  }
  Map<String, dynamic> toJson() => {
        'sort': sort.index,
        'descending': descending,
        'paged': paged,
        'size': pageSize
      };
  FavoriteViewOptions copyWith(
          {FavoriteSort? sort, bool? descending, bool? paged, int? pageSize}) =>
      FavoriteViewOptions(
          sort: sort ?? this.sort,
          descending: descending ?? this.descending,
          paged: paged ?? this.paged,
          pageSize: pageSize ?? this.pageSize);
}

String sqlIdentifier(String value) => '"${value.replaceAll('"', '""')}"';

class FavoriteSnapshot {
  FavoriteSnapshot(this.folder, Iterable<FavoriteKey> keys)
      : keys = List.unmodifiable(keys);
  final String folder;
  final List<FavoriteKey> keys;
  int pageCount(int size) => keys.isEmpty ? 1 : (keys.length / size).ceil();
}

/// Sort the whole folder once; then retrieve metadata for bounded page keys.
class FavoriteQuery {
  FavoriteQuery(this.db, ReadingStatistics statistics,
      {String? historyPath,
      Map<int, String> sources = const {
        0: 'picacg',
        1: 'ehentai',
        2: 'jm',
        3: 'hitomi',
        4: 'htmanga',
        6: 'nhentai'
      }})
      : _sources = sources {
    if (!db
        .select('PRAGMA database_list')
        .any((row) => row['name'] == 'reading_statistics')) {
      db.execute('ATTACH DATABASE ? AS reading_statistics', [statistics.path]);
    }
    _hasHistory = attachReadingHistory(db, historyPath);
  }
  late final bool _hasHistory;
  final Database db;
  final Map<int, String> _sources;
  String get _source =>
      'CASE f.type ${_sources.keys.map((_) => 'WHEN ? THEN ?').join(' ')} ELSE \'unknown:\' || f.type END';
  List<Object?> get _sourceArgs => _sources.entries
      .expand<Object?>((entry) => [entry.key, entry.value])
      .toList();
  String get _joins => '''LEFT JOIN reading_statistics.comic_totals r
    ON r.source_key=($_source) AND r.comic_id=f.target
    LEFT JOIN reading_statistics.image_books b
    ON b.source_key=($_source) AND b.comic_id=f.target
    ${_hasHistory ? 'LEFT JOIN reading_history.history h ON h.type=CASE f.type WHEN 6 THEN 5 ELSE f.type END AND h.target=reading_history_target(f.type,f.target)' : ''}''';
  List<Object?> get _args => [..._sourceArgs, ..._sourceArgs];

  FavoriteSnapshot snapshot(String folder, FavoriteSort sort, bool descending) {
    final direction = descending ? 'DESC' : 'ASC';
    final expression = switch (sort) {
      FavoriteSort.manual => 'f.display_order',
      FavoriteSort.lastRead => "strftime('%s',f.time)",
      FavoriteSort.readCount => 'COALESCE(r.read_count,0)',
      FavoriteSort.readTime => 'COALESCE(r.elapsed_ms,0)',
      FavoriteSort.imageCount => effectiveReadingImagesSql(_hasHistory),
    };
    final rows =
        db.select('''SELECT f.type,f.target FROM ${sqlIdentifier(folder)} f
      $_joins ORDER BY ($expression IS NULL) ASC,$expression $direction,
      f.type ASC,f.target ASC''', _args);
    return FavoriteSnapshot(folder,
        rows.map((row) => (row['type'] as int, row['target'] as String)));
  }

  List<Row> read(FavoriteSnapshot snapshot,
      {int? page, int pageSize = defaultFavoritePageSize}) {
    if (snapshot.keys.isEmpty) return [];
    final keys = page == null
        ? snapshot.keys
        : snapshot.keys
            .skip(((page - 1).clamp(0, snapshot.pageCount(pageSize) - 1)) *
                pageSize)
            .take(pageSize)
            .toList();
    if (keys.isEmpty) return [];
    final params = <Object?>[..._args];
    final where = page == null
        ? ''
        : 'WHERE ${keys.map((key) {
            params.addAll([key.$1, key.$2]);
            return '(f.type=? AND f.target=?)';
          }).join(' OR ')}';
    final rows = db.select(
        '''SELECT f.*, COALESCE(r.read_count,0) AS reading_count,
      COALESCE(r.elapsed_ms,0) AS reading_ms,${effectiveReadingImagesSql(_hasHistory)} AS image_count,
      ${effectiveReadingImagesCompleteSql(_hasHistory)} AS images_complete FROM ${sqlIdentifier(snapshot.folder)} f $_joins $where''',
        params);
    final byKey = {
      for (final row in rows) (row['type'] as int, row['target'] as String): row
    };
    return [
      for (final key in keys)
        if (byKey.containsKey(key)) byKey[key]!
    ];
  }
}
