import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/network/htmanga_network/models.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'reading_stats.dart';
import 'log.dart';

/// Reuse data already fetched for details/direct reading; never fetch a source.
void recordReadingMetadata(String source, String id, Object? data) {
  try {
    _recordReadingMetadata(source, id, data);
  } catch (error, stack) {
    LogManager.addLog(LogLevel.error, 'Reading metadata', '$error\n$stack');
  }
}

void _recordReadingMetadata(String source, String id, Object? data) {
  if (source.isEmpty || id.isEmpty) return;
  final key = (source, id);
  if (data is ComicItem) {
    ReadingStatistics.instance.recordTotal(key, data.pagesCount);
  } else if (data is ComicItemBrief && data.pages != null) {
    ReadingStatistics.instance.recordTotal(key, data.pages!);
  } else if (data is Gallery) {
    final count = int.tryParse(data.maxPage);
    if (count != null) ReadingStatistics.instance.recordTotal(key, count);
  } else if (data is EhGalleryBrief && data.pages != null) {
    ReadingStatistics.instance.recordTotal(key, data.pages!);
  } else if (data is HtComicInfo) {
    ReadingStatistics.instance.recordTotal(key, data.pages);
  } else if (data is HtComicBrief) {
    ReadingStatistics.instance.recordTotal(key, data.pages);
  } else if (data is HitomiComic) {
    ReadingStatistics.instance.recordTotal(key, data.files.length);
  } else if (data is JmComicInfo) {
    ReadingStatistics.instance.recordCatalog(key, data.series.values);
  }
}
