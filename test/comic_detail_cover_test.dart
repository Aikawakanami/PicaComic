import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/comic_detail_cover.dart';

class _TestCover extends ImageProvider<_TestCover> {
  final result = Completer<ImageInfo>();
  int loads = 0;

  @override
  Future<_TestCover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_TestCover key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(result.future);
  }

  void fail() => result.completeError(StateError('Image request failed'));

  Future<void> show(WidgetTester tester) async {
    final image = await tester.runAsync(() {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(Colors.green, BlendMode.src);
      return recorder.endRecording().toImage(1, 1);
    });
    result.complete(ImageInfo(image: image!));
    await tester.pumpAndSettle();
  }
}

class _Fixture {
  final entry = _TestCover();
  final detail = _TestCover();
  final saved = <String>[];
  final opened = <String>[];

  Future<void> pump(WidgetTester tester,
          {String? entryUrl = 'entry', String? detailUrl = 'detail'}) =>
      tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 102,
            height: 136,
            child: ColoredBox(
              color: Colors.grey,
              child: ComicDetailCover(
                entryUrl: entryUrl,
                detailUrl: detailUrl,
                imageFor: (url) => url == 'entry' ? entry : detail,
                onOpen: (url, _) => opened.add(url),
                onDetailCoverShown: saved.add,
              ),
            ),
          ),
        ),
      ));
}

void main() {
  testWidgets('entry cover loads first and avoids requesting a newer cover',
      (tester) async {
    final f = _Fixture();
    await f.pump(tester);
    expect(f.entry.loads, 1);
    expect(f.detail.loads, 0);
    await f.entry.show(tester);
    expect(f.detail.loads, 0);
    expect(f.saved, isEmpty);
    await tester.tap(find.byType(ComicDetailCover));
    expect(f.opened, ['entry']);
  });

  testWidgets('a failed entry uses the detail and saves only after display',
      (tester) async {
    final f = _Fixture();
    await f.pump(tester);
    f.entry.fail();
    await tester.pumpAndSettle();
    expect(f.detail.loads, 1);
    expect(f.saved, isEmpty);
    await f.detail.show(tester);
    await f.pump(tester);
    await tester.pumpAndSettle();
    expect(f.saved, ['detail']);
    await tester.tap(find.byType(ComicDetailCover));
    expect(f.opened, ['detail']);
  });

  testWidgets('a direct entry uses the detail immediately', (tester) async {
    final f = _Fixture();
    await f.pump(tester, entryUrl: null);
    expect(f.entry.loads, 0);
    expect(f.detail.loads, 1);
    await f.detail.show(tester);
    expect(f.saved, ['detail']);
  });

  testWidgets('a working entry matching the detail can repair stored covers',
      (tester) async {
    final f = _Fixture();
    await f.pump(tester, detailUrl: 'entry');
    await f.entry.show(tester);
    await f.pump(tester, detailUrl: 'entry');
    await tester.pumpAndSettle();
    expect(f.entry.loads, 1);
    expect(f.saved, ['entry']);
  });

  testWidgets('duplicate addresses fail once and show an error icon',
      (tester) async {
    final f = _Fixture();
    await f.pump(tester, detailUrl: 'entry');
    f.entry.fail();
    await tester.pumpAndSettle();
    expect(f.entry.loads, 1);
    expect(f.saved, isEmpty);
    expect(find.byType(RawImage), findsNothing);
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two failures leave the placeholder and do not write a cover',
      (tester) async {
    final f = _Fixture();
    await f.pump(tester);
    f.entry.fail();
    await tester.pumpAndSettle();
    f.detail.fail();
    await tester.pumpAndSettle();
    expect(f.detail.loads, 1);
    expect(f.saved, isEmpty);
    expect(find.byType(RawImage), findsNothing);
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
