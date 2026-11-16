import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/translations.dart';

FavoriteItem favorite(String id, {int type = 2, String? title}) => FavoriteItem(
    target: id,
    name: title ?? 'Fixture $id',
    author: '',
    coverPath: '',
    type: FavoriteType(type),
    tags: ['original']);

class FixtureComic extends BaseComic {
  const FixtureComic(this.id);
  @override
  final String id;
  @override
  String get title => 'Fixture $id';
  @override
  String get subTitle => '';
  @override
  String get cover => '';
  @override
  List<String> get tags => [];
  @override
  String get description => '';
}

class FixtureTile extends ComicTile {
  const FixtureTile(this.comic, {super.key});
  final FixtureComic comic;
  @override
  Widget get image => const ColoredBox(color: Colors.grey);
  @override
  String get title => comic.title;
  @override
  String get subTitle => '';
  @override
  String get description => '';
  @override
  FavoriteItem get favoriteItem => favorite(comic.id);
  @override
  void onTap_() {}
}

class FixturePage extends ComicsPage<FixtureComic> {
  const FixturePage(this.load, {super.key});
  final Future<Res<List<FixtureComic>>> Function(int) load;
  @override
  String get sourceKey => 'jm';
  @override
  String? get title => null;
  @override
  String get tag => 'cross-page-fixture';
  @override
  bool get enableMultiSelect => true;
  @override
  Future<Res<List<FixtureComic>>> getComics(int page) => load(page);
}

Future<void> frame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppTranslation.init();
    appdata.settings[50] = 'cn';
  });
  setUp(() {
    appdata.settings[25] = '1';
    appdata.settings[64] = '0';
    appdata.settings[72] = '0';
    appdata.settings[73] = '0';
    appdata.blockingKeyword = [];
    ComicSource.sources = [
      ComicSource.named(
        name: 'Fixture',
        key: 'jm',
        filePath: 'fixture',
        comicTileBuilderOverride: (_, item, __) =>
            FixtureTile(item as FixtureComic),
      )
    ];
  });

  test(
      'remote duplicates and mutations preserve the original selected snapshot',
      () {
    final selection = ComicSelectionController();
    addTearDown(selection.dispose);
    final original = favorite('A');
    selection.begin(original);
    original.name = 'changed remotely';
    original.tags.add('changed');
    selection.selectAll([favorite('A', title: 'new response'), favorite('D')]);
    expect(selection.selected.first.name, 'Fixture A');
    expect(selection.selected.first.tags, ['original']);
    expect(selection.countIn([favorite('A'), favorite('A'), favorite('D')]), 2);
    expect(selection.countIn([favorite('A', type: 1)]), 0);
    expect(selection.isSelected(favorite('unseen-new-item')), isFalse);
    // A selected item absent from every new response remains selected.
    expect(selection.selected.map((e) => e.target), ['A', 'D']);
  });

  test(
      'same-page retry, cached return and a shrinking last page retain selection',
      () async {
    final logic = ComicsPageLogic<int>();
    addTearDown(logic.selection.dispose);
    logic.get((_) async => const Res([1], subData: 3));
    await Future<void>.delayed(Duration.zero);
    logic.selection.begin(favorite('removed-remotely'));
    logic.changePage(2);
    logic.get((page) async {
      expect(page, 2);
      return const Res.error('fixture error');
    });
    await Future<void>.delayed(Duration.zero);
    expect(logic.message, 'fixture error');
    expect(logic.current, 2);
    logic.retry();
    logic.get((page) async {
      expect(page, 2);
      return const Res(<int>[], subData: 1);
    });
    await Future<void>.delayed(Duration.zero);
    expect(logic.maxPage, 1);
    expect(logic.selection.isSelected(favorite('removed-remotely')), isTrue);
    logic.changePage(1);
    expect(logic.loading, isFalse);
    expect(logic.dividedComics![1], [1]);
    expect(logic.message, isNull);
    logic.refresh();
    expect(logic.selection.selected, isEmpty);
  });

  test('in-flight page response is cached under its requested page', () async {
    final logic = ComicsPageLogic<int>();
    addTearDown(logic.selection.dispose);
    logic.get((_) async => const Res([1], subData: 3));
    await Future<void>.delayed(Duration.zero);
    logic.selection.begin(favorite('A'));
    final pending = Completer<Res<List<int>>>();
    logic.changePage(2);
    logic.get((_) => pending.future);
    logic.changePage(3);
    pending.complete(const Res([2], subData: 3));
    await Future<void>.delayed(Duration.zero);
    expect(logic.current, 3);
    expect(logic.dividedComics![2], [2]);
    expect(logic.dividedComics![3], isNull);
    logic.get((_) async => const Res([3], subData: 3));
    await Future<void>.delayed(Duration.zero);
    expect(logic.dividedComics![3], [3]);
    expect(logic.selection.active, isTrue);
  });

  testWidgets('actual paging, jump, review/removal and whole-set save',
      (tester) async {
    final calls = <int>[];
    final page = FixturePage((number) async {
      calls.add(number);
      return Res(
          number == 1
              ? const [FixtureComic('A'), FixtureComic('B'), FixtureComic('C')]
              : number == 2
                  ? const [FixtureComic('C'), FixtureComic('D')]
                  : const [FixtureComic('E')],
          subData: 3);
    });
    await tester.pumpWidget(MaterialApp(
        navigatorKey: App.navigatorKey, home: Scaffold(body: page)));
    await frame(tester);
    final logic =
        StateController.find<ComicsPageLogic<FixtureComic>>(tag: page.tag);
    logic.selection.begin(favorite('A'));
    await frame(tester);
    await tester.tap(find.byTooltip('全选当前页'));
    await frame(tester);
    expect(find.text('共选 3 项，本页 3 项'), findsOneWidget);
    await tester.tap(find.text('下一页').first);
    await frame(tester);
    expect(find.text('共选 3 项，本页 1 项'), findsOneWidget);
    await tester.tap(find.byTooltip('全选当前页'));
    await frame(tester);
    expect(find.text('共选 4 项，本页 2 项'), findsOneWidget);
    await tester.tap(find.text('上一页').first);
    await frame(tester);
    expect(find.text('共选 4 项，本页 3 项'), findsOneWidget);
    expect(calls.where((p) => p == 1), hasLength(1));
    await tester.tap(find.textContaining('页面:').first);
    await frame(tester);
    await tester.enterText(find.widgetWithText(TextField, '页码'), '3');
    await tester.tap(find.text('提交'));
    await frame(tester);
    expect(find.text('共选 4 项，本页 0 项'), findsOneWidget);
    await tester.tap(find.byTooltip('查看已选'));
    await frame(tester);
    expect(find.text('Fixture A'), findsOneWidget);
    await tester.tap(find.byTooltip('取消选择').first);
    await frame(tester);
    expect(find.text('Fixture A'), findsNothing);
    await tester.tap(find.text('关闭'));
    await frame(tester);
    expect(find.text('共选 3 项，本页 0 项'), findsOneWidget);
    await logic.selection.save((all) async {
      expect(all.map((comic) => comic.target), ['B', 'C', 'D']);
      return FavoriteBatchResult()..added.addAll(all);
    });
    await frame(tester);
    expect(logic.selection.active, isFalse);
  });

  testWidgets('failed and empty pages keep toolbar and cached-page navigation',
      (tester) async {
    var attempts = 0;
    final page = FixturePage((number) async {
      if (number == 1) return const Res([FixtureComic('A')], subData: 3);
      if (++attempts == 1) return const Res.error('fixture error');
      return const Res(<FixtureComic>[], subData: 1);
    });
    await tester.pumpWidget(MaterialApp(
        navigatorKey: App.navigatorKey, home: Scaffold(body: page)));
    await frame(tester);
    final logic =
        StateController.find<ComicsPageLogic<FixtureComic>>(tag: page.tag);
    logic.selection.begin(favorite('A'));
    await frame(tester);
    await tester.tap(find.text('下一页').first);
    await frame(tester);
    expect(find.text('共选 1 项，本页 0 项'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await frame(tester);
    expect(logic.current, 2);
    expect(attempts, 2);
    expect(find.text('共选 1 项，本页 0 项'), findsOneWidget);
    await tester.tap(find.text('上一页').first);
    await frame(tester);
    expect(find.text('共选 1 项，本页 1 项'), findsOneWidget);
    expect(logic.selection.isSelected(favorite('A')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'paged counts and selected list fit a small screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selection = ComicSelectionController();
    selection.begin(favorite('off-page'));
    selection.selectAll([favorite('visible')]);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Scaffold(
          body: ComicSelectionRegion(
        controller: selection,
        available: [favorite('visible')],
        paged: true,
        child: const SizedBox.expand(),
      )),
    )));
    await frame(tester);
    expect(find.text('共选 2 项，本页 1 项'), findsOneWidget);
    expect(find.text('全选当前页'), findsNothing);
    expect(find.text('查看已选'), findsNothing);
    for (final icon in [Icons.select_all, Icons.deselect, Icons.checklist]) {
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
              .iconSize,
          32);
    }
    await tester.tap(find.byTooltip('查看已选'));
    await frame(tester);
    expect(find.text('Fixture off-page'), findsOneWidget);
    await tester.tap(find.byTooltip('取消选择').first);
    await frame(tester);
    await tester.tap(find.text('关闭'));
    await frame(tester);
    expect(find.text('共选 1 项，本页 1 项'), findsOneWidget);
    selection.selectAll([favorite('another-off-page')]);
    await frame(tester);
    await tester.tap(find.byTooltip('全不选'));
    await frame(tester);
    expect(find.text('共选 0 项，本页 0 项'), findsOneWidget);
    expect(selection.selected, isEmpty);
    expect(selection.active, isTrue);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.deselect))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    selection.dispose();
  });
}
