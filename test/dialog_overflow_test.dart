import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/pages/download_page.dart';
import 'package:pica_comic/pages/tools.dart';
import 'package:pica_comic/tools/translations.dart';

final _longTitle = List.filled(24, 'Illustrated travel notes 漫画標題').join(' ');

class _Comic extends ComicTile {
  const _Comic(this.onLastAction);

  final VoidCallback onLastAction;

  @override
  String get title => _longTitle;
  @override
  String get subTitle => 'Travel notes';
  @override
  String get description => '';
  @override
  Widget get image => const SizedBox.shrink();
  @override
  List<String> get tags => List.generate(40, (i) => 'Landmark number $i');
  @override
  List<ComicTileMenuOption> get addonMenuOptions => [
        ComicTileMenuOption('Last action', Icons.check, (_) => onLastAction()),
      ];
  @override
  void onTap_() {}
}

class _Downloaded extends Fake implements DownloadedItem {
  @override
  String get name => _longTitle;
  @override
  List<String> get eps => const ['First chapter'];
  @override
  List<int> get downloadedEps => const [];
}

class _DownloadPage extends Fake implements DownloadPageLogic {}

Future<void> _pumpLauncher(
  WidgetTester tester,
  void Function(BuildContext context) open, {
  Size size = const Size(360, 520),
  double keyboardHeight = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(MaterialApp(
    navigatorKey: App.navigatorKey,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => open(context),
          child: const Text('Launch'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Launch'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppTranslation.init();
    appdata.settings[50] = 'cn';
  });

  testWidgets('long comic title keeps the last menu action reachable',
      (tester) async {
    var used = false;
    final comic = _Comic(() => used = true);
    await _pumpLauncher(tester, (_) => comic.onLongTap_());
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(SelectableText, _longTitle), findsOneWidget);
    await tester.ensureVisible(find.text('Last action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last action').hitTestable());
    expect(used, isTrue);
  });

  testWidgets('blocking dialog keeps its input and submit action reachable',
      (tester) async {
    await _pumpLauncher(tester, (_) => _Comic(() {}).showBlockPane());
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('提交'.tl));
    await tester.pumpAndSettle();
    expect(find.text('提交'.tl).hitTestable(), findsOneWidget);
  });

  testWidgets('shared content dialog scrolls with the keyboard visible',
      (tester) async {
    var saved = false;
    await _pumpLauncher(tester, (context) {
      showDialog<void>(
        context: context,
        builder: (_) => ContentDialog(
          title: 'Options',
          content: Column(
            children: [
              for (var i = 1; i <= 12; i++)
                const TextField(
                    decoration: InputDecoration(labelText: 'Input')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => saved = true, child: const Text('Save')),
          ],
        ),
      );
    }, keyboardHeight: 220);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').hitTestable());
    expect(saved, isTrue);
  });

  testWidgets('downloaded chapters and actions fit below a long title',
      (tester) async {
    await _pumpLauncher(tester, (context) {
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => DownloadedComicInfoView(_Downloaded(), _DownloadPage()),
      );
    });
    expect(tester.takeException(), isNull);
    expect(find.text('阅读'.tl).hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('First chapter'),
      160,
      scrollable: find.descendant(
        of: find.byType(DownloadedComicInfoView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('First chapter').hitTestable(), findsOneWidget);
  });

  testWidgets('tools sheet scrolls to the last entry on a short screen',
      (tester) async {
    await _pumpLauncher(tester, (_) => openTool());
    expect(tester.takeException(), isNull);
    final lastEntry = find.text('禁漫漫画ID'.tl);
    await tester.scrollUntilVisible(lastEntry, 120);
    await tester.pumpAndSettle();
    expect(lastEntry.hitTestable(), findsOneWidget);
    await tester.tap(lastEntry);
    await tester.pumpAndSettle();
    expect(find.text('输入禁漫漫画ID'.tl), findsOneWidget);
  });

  testWidgets('message dialog keeps confirmation visible with long text',
      (tester) async {
    await _pumpLauncher(tester,
        (context) => showDialogMessage(context, 'Release notes', _longTitle));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('了解'.tl).hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
