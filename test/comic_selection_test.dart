import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/translations.dart';

FavoriteItem comic(String id, [FavoriteType type = const FavoriteType(2)]) =>
    FavoriteItem(
      target: id,
      name: '测试漫画 $id',
      coverPath: '',
      author: '',
      type: type,
      tags: [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppTranslation.init();
    appdata.settings[50] = 'cn';
  });
  test('selection deduplicates by source and identity, not title or position',
      () {
    final selection = ComicSelectionController();
    addTearDown(selection.dispose);
    selection.begin(comic('same'));
    selection.selectAll([
      comic('same'),
      comic('same', FavoriteType.ehentai),
      comic('other'),
    ]);
    expect(selection.selected, hasLength(3));
    selection.toggle(comic('same'));
    expect(selection.isSelected(comic('same')), isFalse);
    expect(selection.isSelected(comic('same', FavoriteType.ehentai)), isTrue);
    selection.clear();
    expect(selection.active, isTrue);
    expect(selection.selected, isEmpty);
  });

  test('empty selection never invokes writer', () async {
    final selection = ComicSelectionController();
    addTearDown(selection.dispose);
    final result =
        await selection.save((_) => throw StateError('must not run'));
    expect(result, isNull);
  });

  test('busy save uses a snapshot and prevents duplicate submission', () async {
    final selection = ComicSelectionController();
    addTearDown(selection.dispose);
    final done = Completer<FavoriteBatchResult>();
    selection.begin(comic('one'));
    final first = selection.save((snapshot) {
      expect(snapshot.map((e) => e.target), ['one']);
      return done.future;
    });
    selection.toggle(comic('two'));
    selection.exit();
    expect(selection.busy, isTrue);
    expect(selection.selected, hasLength(1));
    expect(await selection.save((_) => throw StateError('duplicate')), isNull);
    done.complete(FavoriteBatchResult()..added.add(comic('one')));
    await first;
    expect(selection.busy, isFalse);
    expect(selection.active, isFalse);
    expect(selection.selected, isEmpty);
  });

  test('partial failure keeps only failed comics; retry excludes successes',
      () async {
    final selection = ComicSelectionController();
    addTearDown(selection.dispose);
    selection.begin(comic('added'));
    selection.selectAll([comic('existing'), comic('failed')]);
    await selection.save((_) async => FavoriteBatchResult()
      ..added.add(comic('added'))
      ..existing.add(comic('existing'))
      ..failed.add(comic('failed')));
    expect(selection.active, isTrue);
    expect(selection.selected.map((e) => e.target), ['failed']);
    await selection.save((snapshot) async {
      expect(snapshot.map((e) => e.target), ['failed']);
      return FavoriteBatchResult()..added.addAll(snapshot);
    });
    expect(selection.active, isFalse);
  });

  test('unexpected write failure preserves selection and releases busy state',
      () async {
    final selection = ComicSelectionController();
    addTearDown(selection.dispose);
    selection.begin(comic('one'));
    await expectLater(
        selection.save((_) async => throw StateError('disk error')),
        throwsStateError);
    expect(selection.busy, isFalse);
    expect(selection.active, isTrue);
    expect(selection.selected.single.target, 'one');
  });

  test(
      'constant response lists can be appended and stale refresh results are ignored',
      () async {
    final logic = ComicsPageLogic<int>();
    addTearDown(logic.selection.dispose);
    logic.get((_) async => const Res([1], subData: 3));
    await Future<void>.delayed(Duration.zero);
    logic.loadNextPage((_) async => const Res([2], subData: 3));
    await Future<void>.delayed(Duration.zero);
    expect(logic.comics, [1, 2]);
    expect(logic.current, 2);
    final old = Completer<Res<List<int>>>();
    logic.loadNextPage((_) => old.future);
    logic.selection.begin(comic('old'));
    logic.refresh();
    logic.get((_) async => const Res([99], subData: 1));
    old.complete(const Res([3], subData: 3));
    await Future<void>.delayed(Duration.zero);
    expect(logic.comics, [99]);
    expect(logic.current, 1);
    expect(logic.selection.selected, isEmpty);
  });

  test('switching list display mode clears the old selection', () {
    final logic = ComicsPageLogic<int>();
    addTearDown(logic.selection.dispose);
    logic.updateMode(false);
    logic.selection.begin(comic('one'));
    logic.updateMode(true);
    expect(logic.selection.active, isFalse);
    expect(logic.selection.selected, isEmpty);
  });

  testWidgets(
      'small screen and large text keep toolbar usable and preserve scroll',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selection = ComicSelectionController();
    final scroll = ScrollController();
    addTearDown(selection.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: ComicSelectionRegion(
            controller: selection,
            available: [comic('one')],
            paged: false,
            child: ListView.builder(
              controller: scroll,
              itemCount: 50,
              itemBuilder: (_, i) => SizedBox(height: 80, child: Text('条目 $i')),
            ),
          ),
        ),
      ),
    ));
    scroll.jumpTo(500);
    await tester.pump();
    selection.begin(comic('one'));
    await tester.pump();
    expect(scroll.offset, 500);
    expect(find.byTooltip('全选已加载'), findsOneWidget);
    expect(find.text('本地收藏'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(selection.active, isFalse);
    expect(scroll.offset, 500);
  });
}
