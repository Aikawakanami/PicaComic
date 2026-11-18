import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/reading_stats.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'sqlite_test_support.dart';

class _File extends Fake implements HitomiFile {}

class _Comic extends Fake implements HitomiComic {
  @override
  List<HitomiFile> get files => [_File(), _File()];
}

class _History extends Fake implements HistoryManager {
  @override
  Future<History?> find(String target) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureTestSqlite();
  test(
      'details store image totals with favorite identity, not legacy history ID',
      () async {
    final directory = Directory.systemTemp.createTempSync('pica-metadata-');
    App.dataPath = directory.path;
    HistoryManager.cache = _History();
    final logic = ComicPageLogic<HitomiComic>();
    try {
      await logic.get(() => Future.value(Res(_Comic())),
          (_) => Future.value(false), () => '42',
          sourceKey: 'hitomi', statisticsId: () => 'https://neutral/42.html');
      expect(logic.loading, false);
      expect(
          ReadingStatistics.instance
              .metrics(('hitomi', 'https://neutral/42.html')).imageLabel,
          '2');
      expect(
          ReadingStatistics.instance.metrics(('hitomi', '42')).images, isNull);
    } finally {
      HistoryManager.cache = null;
      ReadingStatistics.instance.close();
      directory.deleteSync(recursive: true);
    }
  });
}
