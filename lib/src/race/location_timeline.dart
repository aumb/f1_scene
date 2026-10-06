import 'dart:math' as math;

import 'race_repository.dart';

enum ChunkState { loading, loaded, failed }

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

  final _chunks = <int, ChunkState>{};
  final _series = <int, _Series>{};

  int get chunkCount => ((end - start) / chunkSeconds).ceil();

  int chunkAt(double t) =>
      ((t - start) / chunkSeconds).floor().clamp(0, chunkCount - 1);

  (double, double) chunkRange(int chunk) => (
    start + chunk * chunkSeconds,
    math.min(end, start + (chunk + 1) * chunkSeconds),
  );

  ChunkState? stateOf(int chunk) => _chunks[chunk];

  /// Whether data around [t] is loaded, including the next chunk when [t]
  /// is close enough to its boundary for interpolation to need it.
  bool isReady(double t) {
    final chunk = chunkAt(t);
    if (_chunks[chunk] != ChunkState.loaded) return false;
    final (_, chunkEnd) = chunkRange(chunk);
    return chunkEnd - t > maxGap ||
        chunk == chunkCount - 1 ||
        _chunks[chunk + 1] == ChunkState.loaded;
  }

  /// Chunks to request for playback at [t]: the current one, then [ahead]
  /// more in the direction of travel, skipping any loading or loaded.
  List<int> wanted(double t, {int ahead = 1}) => [
    for (
      var k = chunkAt(t);
      k <= math.min(chunkAt(t) + ahead, chunkCount - 1);
      k++
    )
      if (_chunks[k] == null || _chunks[k] == ChunkState.failed) k,
  ];

  void markLoading(int chunk) => _chunks[chunk] = ChunkState.loading;

  void markFailed(int chunk) => _chunks[chunk] = ChunkState.failed;

  void addChunk(int chunk, LocationBatch batch) {
    for (final MapEntry(key: driver, value: s) in batch.samples.entries) {
      _series.putIfAbsent(driver, _Series.new).splice(s.t, s.x, s.y);
    }
    _chunks[chunk] = ChunkState.loaded;
  }

  Iterable<int> get drivers => _series.keys;

  /// Consecutive samples of [driver] around [t]: the pair bracketing [t]
  /// (at [SampleWindow.bracket] and the next index), the neighbour either
  /// side, and any more within [reach] seconds of [t], none across a gap.
  /// Null when no pair brackets [t] without a gap.
  SampleWindow? windowAt(int driver, double t, {double reach = 0}) =>
      _series[driver]?.window(t, reach);

  /// Interpolated raw position of [driver] at [t], or null without data.
  (double, double)? positionAt(int driver, double t) => _series[driver]?.at(t);
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

class _Series {
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

  (double, double)? at(double time) {
    final i = _lowerBound(time);
    if (i < t.length && t[i] == time) return (x[i], y[i]);
    if (i == 0 || i == t.length) return null;
    final t0 = t[i - 1], t1 = t[i];
    if (t1 - t0 > LocationTimeline.maxGap) return null;
    final f = (time - t0) / (t1 - t0);
    return (x[i - 1] + (x[i] - x[i - 1]) * f, y[i - 1] + (y[i] - y[i - 1]) * f);
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
