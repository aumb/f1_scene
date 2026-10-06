import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/data_cache.dart';

/// Thin client for the OpenF1 REST API (https://openf1.org).
///
/// Historical data needs no key. The free tier allows 3 requests per second
/// and 30 per minute from each visitor's address, so every request goes
/// through a sliding-window limiter, a 429 response is retried after a
/// backoff, and responses are cached ([DataCache]) for as long as the caller
/// says they stay valid.
class OpenF1Client {
  OpenF1Client({http.Client? httpClient, Uri? baseUri, DataCache? cache})
    : _http = httpClient ?? http.Client(),
      _base = baseUri ?? Uri.parse('https://api.openf1.org/v1/'),
      cache = cache ?? DataCache.instance;

  final http.Client _http;
  final Uri _base;

  /// Where responses are kept.
  final DataCache cache;

  final _limiter = _RateLimiter([
    (count: 3, window: const Duration(seconds: 1)),
    (count: 30, window: const Duration(minutes: 1)),
  ]);

  /// Requests on their way, so asking twice at once sends one.
  final _inFlight = <String, Future<Uint8List>>{};

  /// The URL [get] requests for [endpoint] with [filters], which also names
  /// its cached response.
  Uri uriFor(String endpoint, Map<String, Object> filters) {
    final query = [
      for (final MapEntry(:key, :value) in filters.entries)
        filterText(key, value.toString()),
    ].join('&');
    return _base.resolve('$endpoint?$query');
  }

  /// GETs [endpoint] with [filters], returning the decoded JSON rows, from
  /// the cache when there and kept there as [keep] allows.
  ///
  /// Filter keys may carry OpenF1's comparison suffixes, e.g.
  /// `{'date>=': '2024-03-02T15:20:00'}`.
  Future<List<Map<String, dynamic>>> get(
    String endpoint,
    Map<String, Object> filters, {
    Keep keep = Keep.session,
  }) async {
    final uri = uriFor(endpoint, filters);
    final key = uri.toString();
    if (keep != Keep.nothing) {
      final cached = await cache.read(key);
      if (cached != null) return _decode(cached);
    }
    // A block body: returning the removed future would make the request
    // wait on itself.
    final body = await (_inFlight[key] ??= _fetch(uri).whenComplete(() {
      _inFlight.remove(key);
    }));
    await cache.write(key, body, keep);
    return _decode(body);
  }

  Future<Uint8List> _fetch(Uri uri) async {
    for (var attempt = 0; ; attempt++) {
      await _limiter.acquire();
      final response = await _http.get(uri);
      if (response.statusCode == 200) return response.bodyBytes;
      // OpenF1 answers an empty result with 404 and a detail message.
      if (response.statusCode == 404) return _empty;
      if (response.statusCode == 429 && attempt < 4) {
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
        continue;
      }
      throw OpenF1Exception(uri, response.statusCode, response.body);
    }
  }

  static final _empty = Uint8List.fromList(utf8.encode('[]'));

  static List<Map<String, dynamic>> _decode(Uint8List body) =>
      (jsonDecode(utf8.decode(body)) as List).cast<Map<String, dynamic>>();

  /// Encodes one filter. OpenF1 reads comparisons from the raw query text:
  /// `date>=X` arrives as key `date>` with value `X`, and `date<X` as a bare
  /// key, so only plain and `…=` keys get a separator.
  static String filterText(String key, String value) {
    final strict = key.endsWith('<') || key.endsWith('>');
    final name = key.endsWith('=') ? key.substring(0, key.length - 1) : key;
    return '${Uri.encodeQueryComponent(name)}${strict ? '' : '='}'
        '${Uri.encodeQueryComponent(value)}';
  }

  void close() => _http.close();
}

class OpenF1Exception implements Exception {
  OpenF1Exception(this.uri, this.statusCode, this.body);

  final Uri uri;
  final int statusCode;
  final String body;

  @override
  String toString() => 'OpenF1 request failed ($statusCode): $uri';
}

/// Allows at most `count` acquisitions per sliding `window`, for each limit.
class _RateLimiter {
  _RateLimiter(this._limits);

  final List<({int count, Duration window})> _limits;
  final _history = <DateTime>[];
  Future<void> _tail = Future.value();

  /// Completes when a request may be sent. Calls are served in order.
  Future<void> acquire() {
    final next = _tail.then((_) => _waitForSlot());
    _tail = next;
    return next;
  }

  Future<void> _waitForSlot() async {
    while (true) {
      final now = DateTime.now();
      var wait = Duration.zero;
      for (final limit in _limits) {
        final recent = _history
            .where((t) => now.difference(t) < limit.window)
            .toList();
        if (recent.length >= limit.count) {
          final free = recent[recent.length - limit.count].add(limit.window);
          final d = free.difference(now);
          if (d > wait) wait = d;
        }
      }
      if (wait == Duration.zero) {
        _history
          ..add(now)
          ..removeWhere((t) => now.difference(t) > const Duration(minutes: 2));
        return;
      }
      await Future<void>.delayed(wait);
    }
  }
}
