import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/favorite_query.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/reading_stats.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/pages/favorites/local_favorites.dart';
import 'package:pica_comic/pages/favorites/main_favorites_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:sqlite3/sqlite3.dart';
import 'sqlite_test_support.dart';

class _Favorites extends Fake implements LocalFavoritesManager {
  _Favorites(this.query);
  final FavoriteQuery query;
  @override
  List<FolderSync> get folderSync => [];
  @override
  List<String> get folderNames => ['fixture'];
  @override
  int coverRevision = 0;
  @override
  int count(String folder) =>
      query.db.select('SELECT COUNT(*) FROM fixture').first[0];
  @override
  FavoriteSnapshot folderSnapshot(
          String folder, FavoriteSort sort, bool descending) =>
      query.snapshot(folder, sort, descending);
  @override
  List<FavoriteItem> folderItems(FavoriteSnapshot snapshot,
          {int? page, int pageSize = 50}) =>
      query
          .read(snapshot, page: page, pageSize: pageSize)
          .map(FavoriteItem.fromRow)
          .toList();
}

class _Downloads extends Fake implements DownloadManager {
  @override
  bool isExists(String id) => false;
}

class _History extends Fake implements HistoryManager {
  @override
  History? findSync(String target) => target == '1'
      ? History(HistoryType.jmComic, DateTime(2020), 'Neutral', '', '', 1, 1,
          '1', {}, 233)
      : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureTestSqlite();
  late Directory directory;
  late Database db;
  late Database historyDb;
  late FavoritesPageController controller;
  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('pica-local-page-');
    App.dataPath = directory.path;
    App.cachePath = directory.path;
    await AppTranslation.init();
    final cover = File('${directory.path}/neutral.png')
      ..writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aRZkAAAAASUVORK5CYII='));
    db = sqlite3.open('${directory.path}/favorites.db');
    db.execute(
        'CREATE TABLE fixture(target TEXT,type INT,name TEXT,author TEXT,tags TEXT,cover_path TEXT,time TEXT,display_order INT,PRIMARY KEY(target,type))');
    for (var i = 0; i < 45; i++) {
      final id = '$i';
      db.execute('INSERT INTO fixture VALUES (?,2,?,?,?,?,?,?)', [
        id,
        'Neutral comic $id',
        '',
        '',
        cover.path,
        '2020-01-01 00:00:00',
        i
      ]);
      LocalFavoriteTile.cache[(2, id, cover.path)] = cover;
    }
    final historyPath = '${directory.path}/history.db';
    historyDb = sqlite3.open(historyPath);
    historyDb.execute(
        'CREATE TABLE history(target TEXT PRIMARY KEY,type INT,max_page INT)');
    historyDb.execute("INSERT INTO history VALUES ('1',2,233)");
    ReadingStatistics.instance.recordTotal(('jm', '0'), 233);
    LocalFavoritesManager.cache = _Favorites(FavoriteQuery(
        db, ReadingStatistics.instance,
        historyPath: historyPath));
    DownloadManager.cache = _Downloads();
    appdata.settings[50] = 'cn';
    appdata.settings[73] = '0';
    appdata.settings[72] = '0';
    appdata.settings[44] = '0,1.0';
    appdata.settings[92] = jsonEncode({
      'fixture': const FavoriteViewOptions(paged: true, pageSize: 20).toJson()
    });
    appdata.implicitData[0] = '0;0;fixture';
    controller = StateController.put(FavoritesPageController());
  });
  tearDownAll(() {
    controller.dispose();
    LocalFavoritesManager.cache = null;
    DownloadManager.cache = null;
    LocalFavoriteTile.cache.clear();
    db.dispose();
    ReadingStatistics.instance.close();
    historyDb.dispose();
    HistoryManager.cache = null;
    directory.deleteSync(recursive: true);
  });

  testWidgets(
      'real folder page preserves cross-page selections and clamps after deletion',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        navigatorKey: App.navigatorKey, home: Scaffold(body: FavoritesPage())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.visibleLocalComics, hasLength(20));
    final first = controller.visibleLocalComics.first;
    controller.selectedComics.add(first);
    controller.update();
    await tester.pump();
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    expect(find.textContaining('阅读次数: 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    App.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(controller.visibleLocalComics.first.target, '20');
    expect(controller.selectedComics, [first]);
    await tester.tap(find.byTooltip('全选当前页'));
    await tester.pump();
    expect(controller.selectedComics, hasLength(21));
    await tester.tap(find.byTooltip('查看已选'));
    await tester.pumpAndSettle();
    expect(find.text(first.name),
        findsOneWidget); // Off-page item can be reviewed/removed.
    await tester.tap(find.byTooltip('取消选择').first);
    await tester.pump();
    expect(controller.selectedComics.contains(first), false);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(controller.visibleLocalComics, hasLength(5));
    db.execute('DELETE FROM fixture WHERE display_order >= 40');
    controller.update();
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 · 40'), findsOneWidget);
    expect(controller.visibleLocalComics, hasLength(20));
    expect(controller.selectedComics, hasLength(20));
    // An explicit manual reorder/refresh must rebuild the snapshot, even if
    // the folder's item count did not change.
    db.execute(
        'UPDATE fixture SET display_order = -1 WHERE target = ?', ['39']);
    StateController.find<SimpleController>(tag: 'ComicsPageView fixture')
        .refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上一页'));
    await tester.pumpAndSettle();
    expect(controller.visibleLocalComics.first.target, '39');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('unread total is visible and read progress remains visible',
      (tester) async {
    controller.selectedComics.clear();
    HistoryManager.cache = _History();
    appdata.settings[73] = '1';
    await tester.pumpWidget(MaterialApp(
        navigatorKey: App.navigatorKey, home: Scaffold(body: FavoritesPage())));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('unread-image-count-0')))
            .data,
        '233');
    expect(find.byKey(const ValueKey('unread-image-count-1')), findsNothing);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.label == '1/233'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('cover update refreshes the current page without reordering',
      (tester) async {
    controller.selectedComics.clear();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: App.navigatorKey, home: Scaffold(body: FavoritesPage())));
    await tester.pumpAndSettle();
    final before = controller.visibleLocalComics.map((c) => c.target).toList();
    final comic = controller.visibleLocalComics.first;
    final replacement = File(comic.coverPath)
        .copySync('${directory.path}/replacement-cover.png');
    LocalFavoriteTile.cache[(comic.type.key, comic.target, replacement.path)] =
        replacement;
    db.execute('UPDATE fixture SET cover_path = ? WHERE target = ? AND type = ?',
        [replacement.path, comic.target, comic.type.key]);
    (LocalFavoritesManager() as _Favorites).coverRevision++;
    controller.update();
    await tester.pumpAndSettle();
    expect(controller.visibleLocalComics.first.coverPath, replacement.path);
    expect(controller.visibleLocalComics.map((c) => c.target), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
