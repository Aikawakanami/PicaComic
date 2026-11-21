import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/cache_network.dart';
import 'package:pica_comic/network/eh_network/eh_dawn.dart';
import 'package:pica_comic/network/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const newsHtml = '<a href="/home.php">My Home</a>';
const claimedHtml = '<div id="eventpane"><b>It is the dawn</b> of a new day! '
    'You gain <b>98,765</b> EXP! You received 1,234 Credits and 567 GP.</div>';
const homeHtml = '<div class="homebox"><p>You are currently at '
    '<strong>0</strong> hits.</p></div>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late EhDawnSession? session;
  late bool enabled;
  late bool foreground;
  late List<(Uri, String)> requests;
  late EhDawnFetch response;

  EhDawn service() => EhDawn(
        loadSession: (_) => session,
        isEnabled: () => enabled,
        canCheck: () => foreground,
        clock: () => now,
        fetch: (uri, cookie) {
          requests.add((uri, cookie));
          return response(uri, cookie);
        },
      );

  CachedNetworkRes<String> page(Uri uri, String html,
          {int status = 200, Map<String, List<String>> headers = const {}}) =>
      CachedNetworkRes(html, status, uri.toString(), headers);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.parse('2026-11-21T07:59:00+08:00');
    enabled = foreground = true;
    session = (id: '10', hash: 'fake-hash', cookie: 'simulated-cookie');
    requests = [];
    response = (uri, _) async => page(uri, claimedHtml);
  });

  test('checks once across concurrent triggers, resume and service restart',
      () async {
    final dawn = service();
    final results = await Future.wait([dawn.check(), dawn.check(manual: true)]);
    expect(results.map((r) => r!.status), everyElement(EhDawnStatus.claimed));
    expect(results.first!.credits, 1234);
    expect(results.first!.exp, 98765);
    expect(results.first!.gp, 567);
    expect(await service().check(), isNotNull);
    expect(requests,
        [(Uri.https('e-hentai.org', '/news.php'), 'simulated-cookie')]);
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('ehDawn.10')!;
    expect(jsonDecode(value)['checkedDay'], '2026-11-20');
    expect(jsonDecode(value)['claimedDay'], '2026-11-20');
    expect(value, isNot(contains('fake-hash')));
    expect(value, isNot(contains('simulated-cookie')));
  });

  test('switches day at 08:00 Beijing time and isolates accounts', () async {
    final dawn = service();
    await dawn.check();
    now = DateTime.parse('2026-11-21T08:00:00+08:00');
    expect(await dawn.latest(), isNull);
    await dawn.check();
    session = (id: '11', hash: 'new-hash', cookie: 'other-cookie');
    expect(await dawn.latest(), isNull);
    await dawn.check();
    expect(requests.map((r) => r.$2),
        ['simulated-cookie', 'simulated-cookie', 'other-cookie']);
  });

  test('details refreshes balances without repeating the daily reward request',
      () async {
    response = (uri, _) async {
      if (uri == EhDawn.gpExchange) {
        return page(uri, '<div>Available: <b>5,321</b> kGP</div>');
      }
      if (uri == EhDawn.hathExchange) {
        return page(uri,
            '<div>Available: 1,234,567 Credits</div><div>Available: 0 Hath</div>');
      }
      return page(uri, claimedHtml);
    };
    final dawn = service();
    await dawn.check();
    final details = await dawn.checkDetails();
    expect(details.result?.exp, 98765);
    expect(details.result?.gp, 567);
    expect(details.result?.credits, 1234);
    expect(details.gp, '5,321 kGP');
    expect(details.credits, '1,234,567');
    expect(details.hath, '0');
    expect(requests.map((r) => r.$1),
        [EhDawn.news, EhDawn.gpExchange, EhDawn.hathExchange]);
  });

  test('confirmed prior credits remain visible when a balance page fails',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'ehDawn.10',
        jsonEncode({
          'checkedDay': '2026-11-20',
          'claimedDay': '2026-11-20',
          'last': {
            'status': 'claimed',
            'at': now.toIso8601String(),
            'credits': 1234
          },
        }));
    response = (uri, _) async {
      if (uri == EhDawn.gpExchange) {
        return page(uri,
            '<div>Available: 123 Credits</div><div>Available: 4 kGP</div>');
      }
      throw TimeoutException('simulated Hath Exchange timeout');
    };
    final details = await service().checkDetails();
    expect(details.result?.exp, isNull);
    expect(details.result?.gp, isNull);
    expect(details.result?.credits, 1234);
    expect(details.gp, '4 kGP');
    expect(details.credits, '123');
    expect(details.hath, isNull);
    expect(requests.map((r) => r.$1), [EhDawn.gpExchange, EhDawn.hathExchange]);
  });

  test('balances and missing reward notice cannot confirm a claim elsewhere',
      () async {
    response = (uri, _) async => page(
        uri,
        {
          EhDawn.news: newsHtml,
          EhDawn.home: homeHtml,
          EhDawn.gpExchange: '<div>Available: 12 kGP</div>',
          EhDawn.hathExchange: '<div>Available: 999 Credits</div>',
        }[uri]!);
    final details = await service().checkDetails();
    expect(details.result?.status, EhDawnStatus.unconfirmed);
    expect(details.result?.exp, isNull);
    expect(details.result?.gp, isNull);
    expect(details.result?.credits, isNull);
    expect(details.credits, '999');
  });

  test('requires foreground, an account and enabled autodetection', () async {
    final dawn = service();
    foreground = false;
    expect(await dawn.check(manual: true), isNull);
    foreground = true;
    enabled = false;
    expect(await dawn.check(), isNull);
    final saved = session;
    session = null;
    expect((await dawn.check(manual: true))!.status, EhDawnStatus.noSession);
    expect(requests, isEmpty);
    session = saved;
    expect((await dawn.check(manual: true))!.status, EhDawnStatus.claimed);
    expect(requests, hasLength(1));
  });

  test('checks protected home when no reward is visible', () async {
    response =
        (uri, _) async => page(uri, uri == EhDawn.news ? newsHtml : homeHtml);
    final dawn = service();
    expect((await dawn.check())!.status, EhDawnStatus.unconfirmed);
    expect((await dawn.check())!.status, EhDawnStatus.unconfirmed);
    final prefs = await SharedPreferences.getInstance();
    final value = jsonDecode(prefs.getString('ehDawn.10')!);
    expect(value['checkedDay'], '2026-11-20');
    expect(value['claimedDay'], isNull);
    expect(requests.map((r) => r.$1), [EhDawn.news, EhDawn.home]);
  });

  test('public news and login redirect do not count as a successful check',
      () async {
    response = (uri, _) async => uri == EhDawn.news
        ? page(uri, newsHtml)
        : page(uri, '', status: 302, headers: {
            'location': ['/bounce_login.php?b=d']
          });
    final result = await service().check();
    expect(result!.status, EhDawnStatus.expiredSession);
    expect(result.checked, isFalse);
  });

  test('ignores a Dawn phrase outside the authentic notice or site', () async {
    response =
        (uri, _) async => page(uri, '<main>It is the dawn of a new day</main>');
    expect((await service().check())!.status, EhDawnStatus.unexpectedResponse);
    now = now.add(const Duration(minutes: 1));
    response = (_, __) async =>
        page(Uri.https('fixture.invalid', '/news.php'), claimedHtml);
    expect((await service().check())!.status, EhDawnStatus.unexpectedResponse);
  });

  test('reports a verification page and honors longer Retry-After', () async {
    response = (uri, _) async =>
        page(uri, '<form id="challenge-form"></form>', status: 403);
    final dawn = service();
    expect((await dawn.check())!.status, EhDawnStatus.challenge);
    now = now.add(const Duration(minutes: 5));
    response = (uri, _) async => page(uri, '', status: 429, headers: {
          'retry-after': ['1800']
        });
    final rateLimit = (await dawn.check())!;
    expect(rateLimit.status, EhDawnStatus.rateLimited);
    expect(rateLimit.retryAt, now.add(const Duration(minutes: 30)));
    now = now.add(const Duration(minutes: 15));
    await service().check(manual: true);
    expect(requests, hasLength(2));
    now = now.add(const Duration(minutes: 15));
    response = (uri, _) async => page(uri, claimedHtml);
    expect((await service().check())!.status, EhDawnStatus.claimed);
    expect(requests, hasLength(3));
  });

  test('a connection failure remains eligible on a later resume', () async {
    response =
        (_, __) async => throw TimeoutException('simulated proxy timeout');
    final dawn = service();
    expect((await dawn.check())!.status, EhDawnStatus.networkError);
    await dawn.check();
    expect(requests, hasLength(1));
    now = now.add(const Duration(minutes: 1));
    response = (uri, _) async => page(uri, claimedHtml);
    expect((await dawn.check())!.status, EhDawnStatus.claimed);
  });

  for (final scenario in ['logout', 'account switch', 'UTC rollover']) {
    test('discards an in-flight result after $scenario', () async {
      final started = Completer<void>();
      final reply = Completer<CachedNetworkRes<String>>();
      response = (_, __) {
        started.complete();
        return reply.future;
      };
      final dawn = service();
      final pending = dawn.check();
      await started.future;
      if (scenario == 'logout') {
        session = null;
      } else if (scenario == 'account switch') {
        session = (id: '11', hash: 'other-hash', cookie: 'other-cookie');
      } else {
        now = now.add(const Duration(minutes: 1));
      }
      reply.complete(page(EhDawn.news, claimedHtml));
      expect(await pending, isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });
  }

  test('does not start the session probe after leaving the foreground',
      () async {
    response = (uri, _) async {
      foreground = false;
      return page(uri, newsHtml);
    };
    expect(await service().check(), isNull);
    expect(requests.map((request) => request.$1), [EhDawn.news]);
  });

  test('production transport sends CONNECT to the configured local proxy',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final originalOverrides = proxyHttpOverrides;
    final originalSettings = appdata;
    appdata = Appdata();
    appdata.settings[8] = '127.0.0.1:${server.port}';
    addTearDown(() {
      appdata = originalSettings;
      proxyHttpOverrides = originalOverrides;
      HttpOverrides.global = originalOverrides;
    });
    final request = Completer<String>();
    server.listen((socket) {
      addTearDown(socket.destroy);
      final buffer = StringBuffer();
      socket.listen((data) {
        buffer.write(ascii.decode(data));
        final text = buffer.toString();
        if (!request.isCompleted && text.contains('\r\n\r\n')) {
          request.complete(text);
          // The local fixture declines the tunnel without contacting EH.
          socket.write(
              'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
          unawaited(socket.close());
        }
      });
    });

    await expectLater(
        EhDawn.instance.fetch(EhDawn.news, 'fixture=1'), throwsException);
    expect(await request.future.timeout(const Duration(seconds: 2)),
        startsWith('CONNECT e-hentai.org:443 HTTP/1.1\r\n'));
  });
}
