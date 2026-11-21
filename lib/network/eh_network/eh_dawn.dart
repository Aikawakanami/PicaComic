import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';

import '../../base.dart';
import '../../comic_source/built_in/ehentai.dart';
import '../../pages/auth_page.dart';
import '../cache_network.dart';
import '../cookie_jar.dart';

enum EhDawnStatus {
  claimed,
  unconfirmed,
  noSession,
  expiredSession,
  challenge,
  rateLimited,
  networkError,
  unexpectedResponse,
}

class EhDawnResult {
  const EhDawnResult(this.status, this.at,
      {this.exp, this.gp, this.credits, this.retryAt});

  final EhDawnStatus status;
  final DateTime at;
  final int? exp;
  final int? gp;
  final int? credits;
  final DateTime? retryAt;

  bool get checked =>
      status == EhDawnStatus.claimed || status == EhDawnStatus.unconfirmed;

  Map<String, Object?> toJson() => {
        'status': status.name,
        'at': at.toIso8601String(),
        'exp': exp,
        'gp': gp,
        'credits': credits,
        'retryAt': retryAt?.toIso8601String(),
      };

  factory EhDawnResult.fromJson(Map<String, dynamic> json) => EhDawnResult(
        EhDawnStatus.values.byName(json['status'] as String),
        DateTime.parse(json['at'] as String),
        exp: json['exp'] as int?,
        gp: json['gp'] as int?,
        credits: json['credits'] as int?,
        retryAt: DateTime.tryParse(json['retryAt'] as String? ?? ''),
      );
}

typedef EhDawnSession = ({String id, String hash, String cookie});
typedef EhDawnFetch = Future<CachedNetworkRes<String>> Function(
    Uri uri, String cookie);
typedef EhDawnDetails = ({
  EhDawnResult? result,
  String? gp,
  String? credits,
  String? hath
});

/// A foreground-only check. Only sanitized results and site dates are saved.
class EhDawn {
  EhDawn({
    required this.loadSession,
    required this.isEnabled,
    required this.canCheck,
    required this.fetch,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  static final news = Uri.https('e-hentai.org', '/news.php');
  static final home = Uri.https('e-hentai.org', '/home.php');
  static final gpExchange =
      Uri.https('e-hentai.org', '/exchange.php', {'t': 'gp'});
  static final hathExchange =
      Uri.https('e-hentai.org', '/exchange.php', {'t': 'hath'});

  static final instance = EhDawn(
    loadSession: _loadSession,
    isEnabled: () => appdata.appSettings.ehDawnOnOpen,
    canCheck: () =>
        !AuthPage.lock &&
        SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed,
    fetch: _fetch,
  );

  final EhDawnSession? Function(SharedPreferences prefs) loadSession;
  final bool Function() isEnabled;
  final bool Function() canCheck;
  final EhDawnFetch fetch;
  final DateTime Function() clock;

  final changes = ValueNotifier(0);
  final _pending = <(String, String), Future<EhDawnResult?>>{};
  bool get checking => _pending.isNotEmpty;

  static String siteDay(DateTime time) =>
      time.toUtc().toIso8601String().split('T').first;

  static Future<void> onForeground() async {
    try {
      await instance.check();
    } catch (_) {
      // Checking rewards must not interfere with startup or resume.
    }
  }

  Future<EhDawnResult?> latest() async {
    final prefs = await SharedPreferences.getInstance();
    final session = loadSession(prefs);
    if (session == null) return null;
    final last = _read(prefs, session.id).last;
    return last != null && siteDay(last.at) == siteDay(clock()) ? last : null;
  }

  Future<EhDawnDetails> checkDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final session = loadSession(prefs);
    final result = await check(manual: true);
    EhDawnDetails withoutBalances() =>
        (result: result, gp: null, credits: null, hath: null);
    if (session == null || result == null || !canCheck()) {
      return withoutBalances();
    }

    bool sameSession() {
      final current = loadSession(prefs);
      return current?.id == session.id && current?.hash == session.hash;
    }

    const unavailable = (result: null, gp: null, credits: null, hath: null);
    if (!sameSession()) return unavailable;
    if (!result.checked) return withoutBalances();
    final [gpPage, hathPage] = await Future.wait([
      _loadExchange(gpExchange, session.cookie),
      _loadExchange(hathExchange, session.cookie),
    ]);
    if (!sameSession() || siteDay(result.at) != siteDay(clock())) {
      return unavailable;
    }
    return (
      result: result,
      gp: _available(gpPage, 'GP|kGP'),
      credits:
          _available(hathPage, 'Credits?') ?? _available(gpPage, 'Credits?'),
      hath: _available(hathPage, 'Hath'),
    );
  }

  Future<String> _loadExchange(Uri uri, String cookie) async {
    try {
      final response = await fetch(uri, cookie);
      if (_classifyFailure(response, uri) == null) {
        final body = html.parse(response.data).body;
        return body == null ? '' : _textParts(body).join(' ');
      }
    } catch (_) {
      // A missing balance must not obscure a confirmed daily reward.
    }
    return '';
  }

  static Iterable<String> _textParts(dom.Node node) sync* {
    if (node is dom.Text) {
      yield node.data;
    } else if (node is! dom.Element ||
        (node.localName != 'script' && node.localName != 'style')) {
      for (final child in node.nodes) {
        yield* _textParts(child);
      }
    }
  }

  static String? _available(String text, String unit) {
    final value = RegExp(
            r'\bAvailable\s*:\s*(\d[\d,]*(?:\.\d+)?)\s*(' + unit + r')\b',
            caseSensitive: false)
        .firstMatch(text);
    if (value == null) return null;
    return value[2]!.toLowerCase() == 'kgp' ? '${value[1]} kGP' : value[1];
  }

  static int? _reward(String text, String unit) {
    final amount = RegExp(r'(?<![\d.,])\b(\d[\d,]*)\s*(' + unit + r')\b',
            caseSensitive: false)
        .firstMatch(text)
        ?.group(1);
    return int.tryParse(amount?.replaceAll(',', '') ?? '');
  }

  Future<EhDawnResult?> check({bool manual = false}) async {
    bool allowed() => canCheck() && (manual || isEnabled());
    if (!allowed()) return null;
    final prefs = await SharedPreferences.getInstance();
    if (!allowed()) return null;
    final now = clock().toUtc();
    final session = loadSession(prefs);
    if (session == null) {
      return manual ? EhDawnResult(EhDawnStatus.noSession, now) : null;
    }
    final day = siteDay(now);
    final key = (session.id, day);
    final pending = _pending[key];
    if (pending != null) return pending;

    final previous = _read(prefs, session.id);
    final retryAt = previous.last?.retryAt;
    if (previous.checkedDay == day ||
        (retryAt != null && now.isBefore(retryAt))) {
      return previous.last;
    }

    bool sameSession() {
      final current = loadSession(prefs);
      return current?.id == session.id && current?.hash == session.hash;
    }

    final operation = _request(
      prefs,
      session,
      day,
      canRequest: () => allowed() && sameSession() && siteDay(clock()) == day,
      canSave: () => sameSession() && siteDay(clock()) == day,
    );
    _pending[key] = operation;
    changes.value++;
    try {
      return await operation;
    } finally {
      _pending.remove(key);
      changes.value++;
    }
  }

  Future<EhDawnResult?> _request(
    SharedPreferences prefs,
    EhDawnSession session,
    String day, {
    required bool Function() canRequest,
    required bool Function() canSave,
  }) async {
    EhDawnResult result;
    try {
      final response = await fetch(news, session.cookie);
      final failure = _classifyFailure(response, news);
      final document = html.parse(response.data);
      final noticeNode = document.querySelector('#eventpane');
      final notice = noticeNode == null ? '' : _textParts(noticeNode).join(' ');
      if (failure != null) {
        result = failure;
      } else if (RegExp(r'\bit is the dawn of a new day\b',
              caseSensitive: false)
          .hasMatch(notice.replaceAll(RegExp(r'\s+'), ' '))) {
        result = EhDawnResult(EhDawnStatus.claimed, clock().toUtc(),
            exp: _reward(notice, 'EXP'),
            gp: _reward(notice, 'GP|Gallery Points?'),
            credits: _reward(notice, 'Credits?'));
      } else if (!document.querySelectorAll('a[href]').any((element) =>
          news.resolve(element.attributes['href']!).path == home.path)) {
        result = _failure(EhDawnStatus.unexpectedResponse);
      } else {
        // The public News page is also available to guests. Verify the
        // captured session against the protected My Home page only if needed.
        if (!canRequest()) return null;
        final account = await fetch(home, session.cookie);
        result = _classifyFailure(account, home) ??
            (html.parse(account.data).querySelectorAll('div.homebox > p').any(
                    (element) => element.text.contains('You are currently at'))
                ? EhDawnResult(EhDawnStatus.unconfirmed, clock().toUtc())
                : _failure(EhDawnStatus.unexpectedResponse));
      }
    } catch (_) {
      result = _failure(EhDawnStatus.networkError);
    }
    if (!canSave()) return null;

    final previous = _read(prefs, session.id);
    await prefs.setString(
        _key(session.id),
        jsonEncode({
          'checkedDay': result.checked ? day : previous.checkedDay,
          'claimedDay':
              result.status == EhDawnStatus.claimed ? day : previous.claimedDay,
          'last': result.toJson(),
        }));
    return result;
  }

  EhDawnResult? _classifyFailure(
      CachedNetworkRes<String> response, Uri expected) {
    final status = response.statusCode;
    final headers = response.headers;
    final responseUrl = Uri.tryParse(response.url);
    final location = headers['location']?.firstOrNull;
    final target = location == null ? null : expected.resolve(location);
    final body = response.data.toLowerCase();
    if (status == 429 ||
        body.contains('ip address has been temporarily banned')) {
      return _failure(
          EhDawnStatus.rateLimited, headers['retry-after']?.firstOrNull);
    }
    if (status == 401 ||
        responseUrl?.path == '/bounce_login.php' ||
        ((status ?? 0) >= 300 &&
            (status ?? 0) < 400 &&
            target?.host == expected.host &&
            target?.path == '/bounce_login.php') ||
        body.contains('this page requires you to log on')) {
      return _failure(EhDawnStatus.expiredSession);
    }
    if (headers['cf-mitigated']?.contains('challenge') == true ||
        body.contains('cf-chl-') ||
        body.contains('id="challenge-form"')) {
      return _failure(EhDawnStatus.challenge);
    }
    if ((status ?? 0) >= 500) return _failure(EhDawnStatus.networkError);
    if (status != 200 || responseUrl != expected) {
      return _failure(EhDawnStatus.unexpectedResponse);
    }
    return null;
  }

  EhDawnResult _failure(EhDawnStatus status, [String? retryAfter]) {
    final now = clock().toUtc();
    var until = now.add(Duration(
        minutes: switch (status) {
      EhDawnStatus.rateLimited => 15,
      EhDawnStatus.expiredSession || EhDawnStatus.challenge => 5,
      _ => 1,
    }));
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      DateTime? requested;
      if (seconds != null && seconds >= 0) {
        requested = now.add(Duration(seconds: seconds));
      } else {
        try {
          requested = HttpDate.parse(retryAfter);
        } on FormatException {
          // Fall back to the local delay for a malformed header.
        }
      }
      if (requested != null && requested.isAfter(until)) until = requested;
    }
    return EhDawnResult(status, now, retryAt: until);
  }

  static String _key(String id) => 'ehDawn.$id';

  static ({String? checkedDay, String? claimedDay, EhDawnResult? last}) _read(
      SharedPreferences prefs, String id) {
    try {
      final data =
          jsonDecode(prefs.getString(_key(id)) ?? '{}') as Map<String, dynamic>;
      final last = data['last'] as Map<String, dynamic>?;
      return (
        checkedDay: data['checkedDay'] as String?,
        claimedDay: data['claimedDay'] as String?,
        last: last == null ? null : EhDawnResult.fromJson(last),
      );
    } catch (_) {
      return (checkedDay: null, claimedDay: null, last: null);
    }
  }

  static EhDawnSession? _loadSession(SharedPreferences prefs) {
    final jar = SingleInstanceCookieJar.instance;
    if (!ehentai.isLogin || jar == null) return null;
    var header = jar.loadForRequestCookieHeader(news);
    var id =
        RegExp(r'(?:^|;\s*)ipb_member_id=([^;]*)').firstMatch(header)?.group(1);
    var hash =
        RegExp(r'(?:^|;\s*)ipb_pass_hash=([^;]*)').firstMatch(header)?.group(1);
    if (id == null && hash == null) {
      id = prefs.getString('ehId');
      hash = prefs.getString('ehPassHash');
      if (id != null && hash != null && hash.isNotEmpty) {
        final legacy =
            '${Cookie('ipb_member_id', id)}; ${Cookie('ipb_pass_hash', hash)}';
        header = header.isEmpty ? legacy : '$header; $legacy';
      }
    }
    if (id == null ||
        !RegExp(r'^\d+$').hasMatch(id) ||
        hash == null ||
        hash.isEmpty) {
      return null;
    }
    return (id: id, hash: hash, cookie: header);
  }

  static Future<CachedNetworkRes<String>> _fetch(Uri uri, String cookie) =>
      CachedNetwork().get(
        uri.toString(),
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          followRedirects: false,
          validateStatus: (status) => status != null,
          headers: {
            'user-agent': webUA,
            'cookie': cookie,
            'cache-control': 'no-cache'
          },
        ),
        expiredTime: CacheExpiredTime.no,
        log: false,
      );
}
