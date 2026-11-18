import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/favorite_query.dart';
import 'package:pica_comic/pages/favorites/favorite_view_controls.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppTranslation.init();
    appdata.settings[50] = 'cn';
  });
  testWidgets(
      '320px controls wrap, mode/sort/size callbacks and pager boundaries',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var options = const FavoriteViewOptions(paged: true);
    var page = 1;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => Column(children: [
                      FavoriteViewControls(
                          options: options,
                          onChanged: (value) => setState(() => options = value),
                          onRefresh: () {}),
                      const Spacer(),
                      FavoritePager(
                          page: page,
                          pages: 3,
                          total: 125,
                          onChanged: (value) => setState(() => page = value)),
                    ])))));
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '上一页'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    expect(page, 2);
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<CheckedPopupMenuItem<FavoriteSort>>(
                find.byWidgetPredicate(
                    (widget) => widget is CheckedPopupMenuItem<FavoriteSort>))
            .any((widget) => widget.value == FavoriteSort.manual),
        false);
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<FavoriteSort> &&
        widget.value == FavoriteSort.imageCount));
    await tester.pumpAndSettle();
    expect(options.sort, FavoriteSort.imageCount);
    expect(options.descending, true);
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<FavoriteSort> &&
        widget.value == FavoriteSort.imageCount));
    await tester.pumpAndSettle();
    expect(options.sort, FavoriteSort.manual);
    expect(options.descending, false);
    await tester.tap(find.byTooltip('每页数量'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<CheckedPopupMenuItem<int>>(find.byWidgetPredicate(
                (widget) => widget is CheckedPopupMenuItem<int>))
            .map((widget) => widget.value),
        [20, 40, 60, 80, 100]);
    await tester.tap(find.byWidgetPredicate(
        (widget) => widget is CheckedPopupMenuItem<int> && widget.value == 80));
    await tester.pumpAndSettle();
    expect(options.pageSize, 80);
    await tester.tap(find.byTooltip('每页数量'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<int> && widget.value == 100));
    await tester.pumpAndSettle();
    expect(options.pageSize, 100);
    await tester.tap(find.byTooltip('切换连续模式'));
    await tester.pump();
    expect(options.paged, false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pager does not reserve a second bottom system inset',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(bottom: 48)),
            child: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: FavoritePager(
                        page: 1, pages: 2, total: 100, onChanged: (_) {}))))));
    expect(tester.getSize(find.byType(FavoritePager)).height, 48);
  });
}
