import '../geometry/track_alignment.dart';
import '../geometry/track_projector.dart';
import 'location_batch.dart';
import 'location_timeline.dart';

/// A stretch of track, in stations along the circuit. [start] is greater
/// than [end] when the stretch crosses the start/finish seam.
class TrackSpan {
  const TrackSpan(this.start, this.end);

  final double start;
  final double end;

  @override
  String toString() =>
      'TrackSpan(${start.toStringAsFixed(0)}, ${end.toStringAsFixed(0)})';
}

/// Where cars had DRS open, as spans of track: the race's DRS zones.
///
/// [openTimes] are the moments each driver had the flap open, [locations]
/// their positions over the same window. Each open moment is placed on the
/// track, and the places cluster into zones. Short or sparse clusters are
/// dropped. Empty when nobody used DRS in the window (or the season had
/// none).
List<TrackSpan> drsZonesFrom({
  required Map<int, List<double>> openTimes,
  required LocationBatch locations,
  required SimilarityTransform2D transform,
  required TrackProjector track,
}) {
  final along = <double>[];
  for (final MapEntry(key: driver, value: times) in openTimes.entries) {
    final s = locations.samples[driver];
    if (s == null || s.t.length < 2) continue;
    int? hint;
    for (final t in times) {
      final i = _upperBound(s.t, t);
      if (i == 0 || i == s.t.length) continue;
      final t0 = s.t[i - 1], t1 = s.t[i];
      if (t1 - t0 > LocationTimeline.maxGap) continue;
      final f = (t - t0) / (t1 - t0);
      final (x, z) = transform.apply(
        s.x[i - 1] + (s.x[i] - s.x[i - 1]) * f,
        s.y[i - 1] + (s.y[i] - s.y[i - 1]) * f,
      );
      final p = track.project(x, z, hint: hint);
      hint = p.station;
      along.add(p.along);
    }
  }
  if (along.length < _minPoints) return const [];

  final n = track.stations.length.toDouble();
  final gap = _splitGap / track.metersPerStation;
  along.sort();
  final clusters = <List<double>>[
    [along.first],
  ];
  for (var i = 1; i < along.length; i++) {
    if (along[i] - along[i - 1] > gap) clusters.add([]);
    clusters.last.add(along[i]);
  }
  final spans = <(TrackSpan, int)>[
    for (final c in clusters) (TrackSpan(c.first, c.last), c.length),
  ];
  // A zone across the seam shows up as one cluster at each end.
  if (spans.length > 1 && along.first + n - along.last <= gap) {
    final (head, headCount) = spans.removeAt(0);
    final (tail, tailCount) = spans.removeLast();
    spans.add((TrackSpan(tail.start, head.end), headCount + tailCount));
  }
  double length(TrackSpan span) =>
      ((span.end - span.start) % n) * track.metersPerStation;
  return [
    for (final (span, count) in spans)
      if (count >= _minClusterPoints && length(span) >= _minLength) span,
  ];
}

/// Open moments needed to say anything; fewer is noise.
const _minPoints = 5;

/// Open moments a zone needs, and its shortest length in meters.
const _minClusterPoints = 3;
const double _minLength = 100;

/// Meters without an open moment that split one zone from the next.
const double _splitGap = 50;

int _upperBound(List<double> values, double v) {
  var lo = 0, hi = values.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (values[mid] <= v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}
