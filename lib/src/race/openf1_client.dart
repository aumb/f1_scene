import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin client for the OpenF1 REST API (https://openf1.org).
///
/// Historical data needs no key. The free tier allows 3 requests per second
/// and 30 per minute, so every request goes through a sliding-window limiter,
/// and a 429 response is retried after a backoff.
class OpenF1Client {
  OpenF1Client({http.Client? httpClient, Uri? baseUri})
    : _http = httpClient ?? http.Client(),
      _base = baseUri ?? Uri.parse('https://api.openf1.org/v1/');

  final http.Client _http;
  final Uri _base;
  final _limiter = _RateLimiter([
    (count: 3, window: const Duration(seconds: 1)),
    (count: 30, window: const Duration(minutes: 1)),
  ]);

  /// GETs [endpoint] with [filters], returning the decoded JSON rows.
  ///
  /// Filter keys may carry OpenF1's comparison suffixes, e.g.
  /// `{'date>=': '2024-03-02T15:20:00'}`.
  Future<List<Map<String, dynamic>>> get(
    String endpoint,
    Map<String, Object> filters,
  ) async {
    final query = [
      for (final MapEntry(:key, :value) in filters.entries)
        filterText(key, value.toString()),
    ].join('&');
    final uri = _base.resolve('$endpoint?$query');

    for (var attempt = 0; ; attempt++) {
      await _limiter.acquire();
      final response = await _http.get(uri);
      if (response.statusCode == 200) {
        return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      }
      // OpenF1 answers an empty result with 404 and a detail message.
      if (response.statusCode == 404) return const [];
      if (response.statusCode == 429 && attempt < 4) {
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
        continue;
      }
      throw OpenF1Exception(uri, response.statusCode, response.body);
    }
  }

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
