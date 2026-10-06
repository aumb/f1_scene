import 'dart:math' as math;

import 'location_batch.dart';

enum _ChunkState { loading, loaded, failed }

/// Per-driver position history assembled from fixed-length time chunks.
///
/// Times are seconds since the session epoch. Chunks may arrive in any order
/// (scrubbing jumps around), so each driver's samples are kept sorted by
/// splicing every chunk in at its place.
class LocationTimeline {
  LocationTimeline({
    required this.start,
    required this.end,
    this.chunkSeconds = 300,
  });

  final double start;
  final double end;
  final double chunkSeconds;

  /// Two samples further apart than this bracket missing data, not motion.
  static const double maxGap = 4.0;

  final _chunks = <int, _ChunkState>{};
  final _series = <int, _DriverSamples>{};

  int get chunkCount => ((end - start) / chunkSeconds).ceil();

  int chunkAt(double t) =>
      ((t - start) / chunkSeconds).floor().clamp(0, chunkCount - 1);

  (double, double) chunkRange(int chunk) => (
    start + chunk * chunkSeconds,
    math.min(end, start + (chunk + 1) * chunkSeconds),
  );

  /// Whether data around [t] is loaded, including the next chunk when [t]
  /// is within [maxGap] of its end, where the samples bracketing [t] and
  /// the motion fit around it may reach into it.
  bool isReady(double t) {
    final chunk = chunkAt(t);
    if (_chunks[chunk] != _ChunkState.loaded) return false;
    final (_, chunkEnd) = chunkRange(chunk);
    return chunkEnd - t > maxGap ||
        chunk == chunkCount - 1 ||
        _chunks[chunk + 1] == _ChunkState.loaded;
  }

  /// Chunks to request for playback at [t]: the current one and the next
  /// [ahead], plus the previous one when [t] is within [maxGap] of its start
  /// (just after a seek, the motion fit reaches back into it). Chunks loading
  /// or loaded are left out.
  List<int> wanted(double t, {int ahead = 1}) {
    final current = chunkAt(t);
    final (chunkStart, _) = chunkRange(current);
    final first = t - chunkStart < maxGap ? math.max(0, current - 1) : current;
    final last = math.min(current + ahead, chunkCount - 1);
    return [
      for (var k = first; k <= last; k++)
        if (_chunks[k] == null || _chunks[k] == _ChunkState.failed) k,
    ];
  }

  void markLoading(int chunk) => _chunks[chunk] = _ChunkState.loading;

  void markFailed(int chunk) => _chunks[chunk] = _ChunkState.failed;

  void addChunk(int chunk, LocationBatch batch) {
    for (final MapEntry(key: driver, value: s) in batch.samples.entries) {
      _series.putIfAbsent(driver, _DriverSamples.new).splice(s.t, s.x, s.y);
    }
    _chunks[chunk] = _ChunkState.loaded;
  }

  Iterable<int> get drivers => _series.keys;

  /// Consecutive samples of [driver] around [t]: the pair bracketing [t]
  /// (at [SampleWindow.bracket] and the next index), the neighbour either
  /// side, and any more within [reach] seconds of [t], none across a gap.
  /// Null when no pair brackets [t] without a gap.
  SampleWindow? windowAt(int driver, double t, {double reach = 0}) =>
      _series[driver]?.window(t, reach);
}

/// Consecutive raw samples; see [LocationTimeline.windowAt].
class SampleWindow {
  const SampleWindow(this.t, this.x, this.y, this.bracket);

  final List<double> t;
  final List<double> x;
  final List<double> y;

  /// Index of the sample at or before the requested time.
  final int bracket;
}

/// One driver's samples, sorted by time.
class _DriverSamples {
  final t = <double>[];
  final x = <double>[];
  final y = <double>[];

  void splice(List<double> ts, List<double> xs, List<double> ys) {
    if (ts.isEmpty) return;
    // Rows arrive date-ordered per driver; make sure before splicing.
    final order = List.generate(ts.length, (i) => i)
      ..sort((a, b) => ts[a].compareTo(ts[b]));
    final at = _lowerBound(ts[order.first]);
    t.insertAll(at, order.map((i) => ts[i]));
    x.insertAll(at, order.map((i) => xs[i]));
    y.insertAll(at, order.map((i) => ys[i]));
  }

  SampleWindow? window(double time, double reach) {
    final i = _lowerBound(time);
    // a: last sample at or before [time].
    final a = (i < t.length && t[i] == time) ? i : i - 1;
    if (a < 0 || a + 1 >= t.length) return null;
    const maxGap = LocationTimeline.maxGap;
    if (t[a + 1] - t[a] > maxGap) return null;
    var from = a, to = a + 1;
    while (from > 0 &&
        t[from] - t[from - 1] <= maxGap &&
        (from == a || t[from - 1] >= time - reach)) {
      from--;
    }
    while (to + 1 < t.length &&
        t[to + 1] - t[to] <= maxGap &&
        (to == a + 1 || t[to + 1] <= time + reach)) {
      to++;
    }
    return SampleWindow(
      t.sublist(from, to + 1),
      x.sublist(from, to + 1),
      y.sublist(from, to + 1),
      a - from,
    );
  }

  /// First index whose time is >= [time].
  int _lowerBound(double time) {
    var lo = 0, hi = t.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (t[mid] < time) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
