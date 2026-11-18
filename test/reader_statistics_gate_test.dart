import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/reading_stats.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'sqlite_test_support.dart';

class _ControlledImage extends ImageProvider<_ControlledImage> {
  final completion = Completer<ImageInfo>();
  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
          _ControlledImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(completion.future);
  void succeed() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    completion.complete(ImageInfo(image: picture.toImageSync(1, 1)));
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureTestSqlite();
  testWidgets(
      'only a decoded current image counts, across loading, routes and chapter switches',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('pica-reader-gate-');
    final store = ReadingStatistics.open('${directory.path}/stats.db');
    var now = 0;
    final data =
        JmReadingData('Neutral', '42', ['chapter-a', 'chapter-b'], ['A', 'B']);
    final logic = ComicReadingPageLogic(1, data, 1, () {});
    final tracker = ReadingSessionTracker(
        store: store,
        identity: data.statisticsIdentity,
        monotonicMs: () => now,
        wallMs: () => 100000 + now,
        sessionId: 'reader');
    logic.statisticsSession = tracker;
    addTearDown(() {
      logic.finishReadingSession();
      logic.pageController.dispose();
      logic.scrollController.dispose();
      logic.focusNode.dispose();
      PaintingBinding.instance.imageCache.clear();
      store.close();
      directory.deleteSync(recursive: true);
    });
    appdata.settings[9] = '1';
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    logic.urls = ['one', 'two'];
    logic.isLoading = false;
    logic.setReadingVisibility(true);
    now += 20000;
    tracker.checkpoint();
    expect(store.metrics(data.statisticsIdentity).elapsedMs, 0);
    final adjacent = _ControlledImage();
    logic.observeImage(2, adjacent, context);
    adjacent.succeed();
    await tester.pump();
    now += 20000;
    tracker.checkpoint();
    expect(store.metrics(data.statisticsIdentity).elapsedMs, 0);
    final current = _ControlledImage();
    logic.observeImage(1, current, context);
    current.succeed();
    await tester.pump();
    now += 6000;
    logic.setReadingVisibility(false); // Background or covering route.
    now += 100000;
    logic.setReadingVisibility(true);
    now += 5000;
    logic.isLoading = true; // Next chapter, same session.
    now += 20000;
    logic.urls = ['new'];
    logic.order = 2;
    logic.index = 1;
    logic.isLoading = false;
    now += 20000;
    tracker.checkpoint();
    expect(store.metrics(data.statisticsIdentity).elapsedMs, 11000);
    final next = _ControlledImage();
    logic.observeImage(1, next, context);
    next.succeed();
    await tester.pump();
    now += 4000;
    logic.finishReadingSession();
    expect(store.metrics(data.statisticsIdentity).count, 1);
    expect(store.metrics(data.statisticsIdentity).elapsedMs, 15000);
    expect(logic.hasReadContent, true);
  });

  test(
      'statistics use favorite source/ID, stable chapters and single chapter fallback',
      () {
    expect(HtReadingData('Neutral', '7').statisticsIdentity, ('htmanga', '7'));
    final single = JmReadingData('Neutral', '42', [], []);
    expect(single.statisticsChapter(1), '42');
    expect(single.statisticsCatalog, ['42']);
    final pc = PicacgReadingData('Neutral', 'same', ['A', 'B']);
    expect(pc.statisticsChapter(1), '@chapter:1');
    expect(pc.statisticsCatalog, ['@chapter:1', '@chapter:2']);
    final hi =
        HitomiReadingData('Neutral', 'numeric', [], 'https://neutral/42.html');
    expect(hi.statisticsIdentity, ('hitomi', 'https://neutral/42.html'));
    expect(NhentaiReadingData('Neutral', '42').statisticsIdentity,
        ('nhentai', '42'));
  });

  testWidgets(
      'boundary pauses on actual lifecycle events and covering navigation routes',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('pica-reader-lifecycle-');
    final store = ReadingStatistics.open('${directory.path}/stats.db');
    var now = 0;
    final data = JmReadingData('Neutral', '77', [], []);
    final logic = ComicReadingPageLogic(1, data, 1, () {});
    final session = ReadingSessionTracker(
        store: store,
        identity: data.statisticsIdentity,
        monotonicMs: () => now,
        wallMs: () => 100000 + now,
        sessionId: 'lifecycle');
    final navigator = GlobalKey<NavigatorState>();
    logic.urls = ['one'];
    logic.isLoading = false;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: Builder(builder: (value) {
          context = value;
          return ReadingStatisticsBoundary(
              logic: logic, session: session, child: const SizedBox());
        })));
    final image = _ControlledImage();
    logic.observeImage(1, image, context);
    image.succeed();
    await tester.pump();
    now += 5000;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now += 100000;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    now += 6000;
    navigator.currentState!
        .push(MaterialPageRoute(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    now += 100000;
    session.checkpoint();
    expect(store.metrics(data.statisticsIdentity).elapsedMs, 11000);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    now += 2000;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(store.metrics(data.statisticsIdentity).count, 1);
    expect(store.metrics(data.statisticsIdentity).elapsedMs, 13000);
    logic.pageController.dispose();
    logic.scrollController.dispose();
    logic.focusNode.dispose();
    PaintingBinding.instance.imageCache.clear();
    store.close();
    directory.deleteSync(recursive: true);
  });
}
