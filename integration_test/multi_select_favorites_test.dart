import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/pages/category_comics_page.dart';
import 'package:pica_comic/pages/ranking_page.dart';
import 'package:pica_comic/pages/explore_page.dart';
import 'package:pica_comic/pages/favorites/network_favorite_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:sqlite3/sqlite3.dart';

// Neutral fixtures only. This target never loads an account or calls a comic API.
const folder = '__multi_select_device_test__';
int detailOpens = 0;

class FixtureComic extends BaseComic {
  const FixtureComic(this.id);
  @override
  final String id;
  @override
  String get title => '验证漫画 $id';
  @override
  String get subTitle => '临时验证条目';
  @override
  String get cover => '';
  @override
  String get description => '仅用于多选验收';
  @override
  List<String> get tags => [];
}

class FixtureTile extends ComicTile {
  const FixtureTile(this.comic, this.type, {super.key});
  final BaseComic comic;
  final FavoriteType type;
  @override
  Widget get image => const ColoredBox(
        color: Color(0xffe1e5f2),
        child: Icon(Icons.menu_book, size: 40),
      );
  @override
  String get title => comic.title;
  @override
  String get subTitle => comic.subTitle;
  @override
  String get description => comic.description;
  @override
  String get comicID => comic.id;
  @override
  FavoriteItem get favoriteItem => FavoriteItem(
        target: comic.id,
        name: comic.title,
        coverPath: '',
        author: '临时验证',
        type: type,
        tags: [],
      );
  @override
  void onTap_() => detailOpens++;
}

FavoriteItem fixtureFavorite(String id, [int type = 2]) =>
    FixtureTile(FixtureComic(id), FavoriteType(type)).favoriteItem;

Future<void> frame(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 100));
}

void registerSource(String key, Future<Res<List<BaseComic>>> Function(int) load,
    {bool withOptions = false}) {
  final type = switch (key) {
    'picacg' => 0,
    'ehentai' => 1,
    'jm' => 2,
    'hitomi' => 3,
    'htmanga' => 4,
    'nhentai' => 6,
    _ => throw StateError(key),
  };
  ComicSource.sources = [
    ComicSource.named(
      name: '验证 $key',
      key: key,
      filePath: 'test-fixture',
      categoryData: CategoryData(
          title: '验证分类',
          key: key,
          categories: const [],
          enableRankingPage: true),
      categoryComicsData: CategoryComicsData.named(
        load: (_, __, ___, page) => load(page),
        rankingData: RankingData.named(
            options: const {'recent': '近期'}, load: (_, page) => load(page)),
      ),
      explorePages: [
        ExplorePageData.named(
            title: '验证最新',
            type: ExplorePageType.multiPageComicList,
            loadPage: load)
      ],
      searchPageData: SearchPageData.named(
        loadPage: (_, page, __) => load(page),
        searchOptions: withOptions
            ? [
                SearchOptions.named(
                    label: '验证排序',
                    options: LinkedHashMap.of({'a': '验证排序 A', 'b': '验证排序 B'}))
              ]
            : null,
      ),
      comicTileBuilderOverride: (_, comic, __) =>
          FixtureTile(comic, FavoriteType(type)),
    ),
  ];
}

Future<void> mountSearch(
    WidgetTester tester, String key, String session) async {
  await tester.pumpWidget(MaterialApp(
    navigatorKey: App.navigatorKey,
    theme: ThemeData(useMaterial3: true),
    home: SearchResultPage(
      key: ValueKey(session),
      keyword: '中性验证',
      sourceKey: key,
    ),
  ));
  await frame(tester);
  await frame(tester);
}

String selectedLabel(int total, [int? onPage]) => appdata.settings[25] == '0'
    ? '已选择 $total 个项目' : '共选 $total 项，本页 ${onPage ?? total} 项';

Future<void> beginSelection(WidgetTester tester, String id) async {
  await tester.longPress(find.text('验证漫画 $id').first);
  await frame(tester);
  expect(find.text('多选'), findsOneWidget);
  await tester.tap(find.text('多选'));
  await frame(tester);
}

Future<void> openSearchAction(
    WidgetTester tester, IconData icon, String compactLabel) async {
  final direct = find.byIcon(icon);
  if (direct.evaluate().isNotEmpty) {
    await tester.tap(direct);
  } else {
    await tester.tap(find.byIcon(Icons.more_horiz));
    await frame(tester);
    await tester.tap(find.text(compactLabel));
  }
  await frame(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final manager = LocalFavoritesManager();
  setUpAll(() async {
    await App.init();
    await AppTranslation.init();
    appdata.settings[45] = ''; // No remote synchronization in this test target.
    appdata.settings[50] = 'cn';
    appdata.settings[72] = '0';
    appdata.settings[73] = '0';
    await manager.init();
    if (!manager.folderNames.contains(folder)) manager.createFolder(folder);
    appdata.settings[51] = folder;
  });
  tearDownAll(() {
    if (manager.folderNames.contains(folder)) manager.deleteFolder(folder);
  });

  testWidgets('five actual search entry points: menu, toggle, clear and back',
      (tester) async {
    appdata.settings[25] = '1';
    for (final key in ['jm', 'ehentai', 'picacg', 'htmanga', 'nhentai']) {
      registerSource(
          key,
          (_) async => const Res<List<BaseComic>>(
                [FixtureComic('1'), FixtureComic('2'), FixtureComic('3')],
                subData: 2,
              ));
      await mountSearch(tester, key, 'smoke-$key');
      await beginSelection(tester, '1');
      expect(find.text(selectedLabel(1)), findsOneWidget);
      final before = detailOpens;
      await tester.tapAt(tester.getCenter(find.text('验证漫画 2')));
      await frame(tester);
      expect(find.text(selectedLabel(2)), findsOneWidget);
      expect(detailOpens, before);
      if (key == 'jm' && const bool.fromEnvironment('CAPTURE_SELECTION')) {
        // Gives the host time to capture the real device's rendered selection UI.
        debugPrint('MULTI_SELECT_SCREENSHOT_READY');
        await Future<void>.delayed(const Duration(seconds: 20));
      }
      await tester.tap(find.byTooltip('全不选'));
      await frame(tester);
      expect(find.text(selectedLabel(0)), findsOneWidget);
      final button = tester.widget<FilledButton>(find.widgetWithText(
        FilledButton,
        '本地收藏',
      ));
      expect(button.onPressed, isNull);
      await tester.binding.handlePopRoute();
      await frame(tester);
      expect(find.textContaining(RegExp(r'^(已选择|共选)')), findsNothing);
      expect(find.text('验证漫画 1'), findsOneWidget);
    }
  });

  testWidgets('page changes and jump retain selections; refresh clears them',
      (tester) async {
    appdata.settings[25] = '1';
    registerSource(
        'jm',
        (page) async => Res<List<BaseComic>>([
              FixtureComic('$page-1'),
              FixtureComic('$page-2'),
              FixtureComic('$page-1'),
            ], subData: 3));
    await mountSearch(tester, 'jm', 'page-boundaries');
    await beginSelection(tester, '1-1');
    await tester.tap(find.byTooltip('全选当前页'));
    await frame(tester);
    expect(find.text(selectedLabel(2)), findsOneWidget);
    await tester.tap(find.text('下一页').first);
    await frame(tester);
    await frame(tester);
    expect(find.text(selectedLabel(2, 0)), findsOneWidget);
    expect(find.text('验证漫画 2-1'), findsNWidgets(2));
    await tester.tap(find.text('验证漫画 2-1').first);
    await frame(tester);
    await tester.tap(find.text('上一页').first);
    await frame(tester);
    expect(find.text(selectedLabel(3, 2)), findsOneWidget);
    await tester.tap(find.textContaining('页面:').first);
    await frame(tester);
    await tester.enterText(find.widgetWithText(TextField, '页码'), '3');
    await tester.tap(find.text('提交'));
    await frame(tester);
    await frame(tester);
    expect(find.text(selectedLabel(3, 0)), findsOneWidget);
    expect(find.text('验证漫画 3-1'), findsNWidgets(2));
    await tester.tap(find.text('验证漫画 3-1').first);
    await frame(tester);
    final logic = StateController.find<ComicsPageLogic<BaseComic>>();
    logic.refresh();
    await frame(tester);
    await frame(tester);
    expect(find.textContaining(RegExp(r'^(已选择|共选)')), findsNothing);
    expect(logic.current, 1);
    expect(find.text('验证漫画 1-1'), findsNWidgets(2));
  });

  testWidgets('category, ranking, explore entry points and excluded lists',
      (tester) async {
    appdata.settings[25] = '1';
    Future<Res<List<BaseComic>>> load(int page) async =>
        const Res<List<BaseComic>>([FixtureComic('1'), FixtureComic('2')],
            subData: 1);
    registerSource('jm', load);
    appdata.appSettings.explorePages = ['验证最新'];
    for (final page in <Widget>[
      const CategoryComicsPage(category: '验证分类', categoryKey: 'jm'),
      const RankingPage(sourceKey: 'jm'),
      const Scaffold(body: ExplorePage()),
    ]) {
      await tester
          .pumpWidget(MaterialApp(navigatorKey: App.navigatorKey, home: page));
      await frame(tester);
      await frame(tester);
      await beginSelection(tester, '1');
      expect(find.text(selectedLabel(1)), findsOneWidget);
      await tester.tap(find.byTooltip('退出多选'));
      await frame(tester);
    }
    await tester.pumpWidget(MaterialApp(
        navigatorKey: App.navigatorKey,
        home: NetworkFavoritePage(FavoriteData(
            key: 'jm',
            title: '验证网络收藏',
            multiFolder: false,
            loadComic: (page, [folder]) => load(page)))));
    await frame(tester);
    await frame(tester);
    await tester.longPress(find.text('验证漫画 1'));
    await frame(tester);
    expect(find.text('多选'), findsNothing);
    Navigator.of(App.globalContext!).pop();
    await frame(tester);
    registerSource('hitomi', load);
    await mountSearch(tester, 'hitomi', 'excluded-hitomi');
    await tester.longPress(find.text('验证漫画 1'));
    await frame(tester);
    expect(find.text('多选'), findsNothing);
    Navigator.of(App.globalContext!).pop();
    await frame(tester);
  });

  testWidgets('continuous append, cancel, one-folder save and duplicate skip',
      (tester) async {
    appdata.settings[25] = '0';
    final next = Completer<Res<List<BaseComic>>>();
    registerSource('jm', (page) async {
      if (page == 1) {
        return const Res<List<BaseComic>>([
          FixtureComic('c1'),
          FixtureComic('c2'),
          FixtureComic('c3'),
        ], subData: 2);
      }
      return await next.future;
    });
    await mountSearch(tester, 'jm', 'continuous');
    await beginSelection(tester, 'c1');
    next.complete(const Res<List<BaseComic>>([
      FixtureComic('c4'),
      FixtureComic('c5'),
      FixtureComic('c6'),
    ], subData: 2));
    await frame(tester);
    await frame(tester);
    expect(find.text(selectedLabel(1)), findsOneWidget);
    await tester.tap(find.byTooltip('全选已加载'));
    await frame(tester);
    expect(find.text(selectedLabel(6)), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '本地收藏'));
    await frame(tester);
    expect(find.text('收藏夹'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await frame(tester);
    expect(manager.getAllComics(folder), isEmpty);
    expect(find.text(selectedLabel(6)), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '本地收藏'));
    await frame(tester);
    await tester.tap(find.text('确认'));
    await frame(tester);
    await frame(tester);
    expect(manager.getAllComics(folder), hasLength(6));
    expect(find.textContaining(RegExp(r'^(已选择|共选)')), findsNothing);
    await beginSelection(tester, 'c1');
    await tester.tap(find.byTooltip('全选已加载'));
    await frame(tester);
    await tester.tap(find.widgetWithText(FilledButton, '本地收藏'));
    await frame(tester);
    await tester.tap(find.text('确认'));
    await frame(tester);
    expect(manager.getAllComics(folder), hasLength(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('query, sorting and source changes reset the selection',
      (tester) async {
    appdata.settings[25] = '1';
    Future<Res<List<BaseComic>>> load(int page) async =>
        const Res<List<BaseComic>>([FixtureComic('1'), FixtureComic('2')],
            subData: 1);
    registerSource('jm', load, withOptions: true);
    final jm = ComicSource.sources.single;
    registerSource('ehentai', load);
    final eh = ComicSource.sources.single;
    ComicSource.sources = [jm, eh];
    await mountSearch(tester, 'jm', 'query-sort-source');
    await beginSelection(tester, '1');
    tester.widget<TextField>(find.byType(TextField).first).controller!.text =
        '更换关键词';
    await tester.tap(find.byType(FloatingActionButton));
    await frame(tester);
    await frame(tester);
    expect(find.textContaining(RegExp(r'^(已选择|共选)')), findsNothing);
    await beginSelection(tester, '1');
    await openSearchAction(tester, Icons.tune, '搜索选项');
    await tester.tap(find.text('验证排序 B'));
    await tester.tap(find.text('确认'));
    await frame(tester);
    await frame(tester);
    expect(find.textContaining(RegExp(r'^(已选择|共选)')), findsNothing);
    await beginSelection(tester, '1');
    await openSearchAction(tester, Icons.dataset_outlined, '切换源');
    await tester.tap(find.text('验证 ehentai'));
    await tester.tap(find.text('确认'));
    await frame(tester);
    await frame(tester);
    expect(find.textContaining(RegExp(r'^(已选择|共选)')), findsNothing);
    await beginSelection(tester, '1');
    expect(find.text(selectedLabel(1)), findsOneWidget);
  });

  testWidgets('real SQLite partial failure and source-aware identity',
      (tester) async {
    final db = sqlite3.open('${App.dataPath}/local_favorite.db');
    final selection = ComicSelectionController();
    try {
      db.execute(
          '''CREATE TRIGGER multi_select_reject BEFORE INSERT ON "$folder"
        WHEN NEW.target = 'reject'
        BEGIN SELECT RAISE(FAIL, 'intentional fixture failure'); END;''');
      await manager.addComicsToFolder(folder, [fixtureFavorite('already')]);
      selection.begin(fixtureFavorite('same-id', 1));
      selection.selectAll([
        fixtureFavorite('same-id', 2),
        fixtureFavorite('reject'),
        fixtureFavorite('already'),
      ]);
      final result = await selection
          .save((items) => manager.addComicsToFolder(folder, items));
      expect(result!.added, hasLength(2));
      expect(result.existing, hasLength(1));
      expect(result.failed, hasLength(1));
      expect(selection.selected.single.target, 'reject');
      db.execute('DROP TRIGGER multi_select_reject');
      await selection.save((items) => manager.addComicsToFolder(folder, items));
      expect(selection.active, isFalse);
      expect(manager.comicExists(folder, 'same-id', 1), isTrue);
      expect(manager.comicExists(folder, 'same-id', 2), isTrue);
      expect(manager.comicExists(folder, 'reject', 2), isTrue);
    } finally {
      db.execute('DROP TRIGGER IF EXISTS multi_select_reject');
      db.dispose();
      selection.dispose();
    }
  });
}
