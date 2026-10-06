import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'track_mesh.dart';
import 'track_projector.dart';

/// Builds the pit lane as an open station path from the scene positions one
/// car drove through a pit stop, in time order.
///
/// The stop's window starts and ends on track, so the lane is the longest
/// run of positions clearly beside the track, with one on-track position at
/// each end joining it to the circuit. Returns null when no such run is
/// long enough to be a pit lane.
TrackStations? pitLaneFromPath(
  List<(double, double)> path,
  TrackProjector track, {
  double halfWidth = 5,
  double spacing = 2,
}) {
  // Drop the stationary part of the stop and sensor jitter.
  final points = <(double, double)>[];
  for (final p in path) {
    if (points.isEmpty || _distance(points.last, p) > 0.5) points.add(p);
  }
  if (points.length < 4) return null;

  // Mark positions more than 2 m beyond the track edge.
  final off = <bool>[];
  int? hint;
  for (final (x, z) in points) {
    final p = track.project(x, z, hint: hint);
    hint = p.station;
    final (:min, :max) = track.lateralLimits(p.along);
    off.add(p.lateral > max + 2 || p.lateral < min - 2);
  }
  var bestStart = 0, bestEnd = -1;
  for (var i = 0; i < off.length; i++) {
    if (!off[i]) continue;
    var j = i;
    while (j + 1 < off.length && off[j + 1]) {
      j++;
    }
    if (j - i > bestEnd - bestStart) (bestStart, bestEnd) = (i, j);
    i = j;
  }
  if (bestEnd < 0) return null;
  final lane = points.sublist(
    math.max(0, bestStart - 1),
    math.min(points.length, bestEnd + 2),
  );
  if (_length(lane) < 80) return null;

  final smoothed = _smooth(lane, radius: 2);
  final resampled = _resample(smoothed, spacing);
  hint = null;
  final heights = <double>[];
  for (final (x, z) in resampled) {
    final p = track.project(x, z, hint: hint);
    hint = p.station;
    heights.add(track.stations.center[p.station].y);
  }
  return TrackStations.fromPath(
    [
      for (var i = 0; i < resampled.length; i++)
        Vector3(resampled[i].$1, heights[i], resampled[i].$2),
    ],
    List.filled(resampled.length, halfWidth),
    closed: false,
  );
}

double _distance((double, double) a, (double, double) b) {
  final dx = a.$1 - b.$1, dz = a.$2 - b.$2;
  return math.sqrt(dx * dx + dz * dz);
}

double _length(List<(double, double)> points) {
  var length = 0.0;
  for (var i = 1; i < points.length; i++) {
    length += _distance(points[i - 1], points[i]);
  }
  return length;
}

/// Moving average that keeps both endpoints fixed.
List<(double, double)> _smooth(
  List<(double, double)> points, {
  int radius = 2,
}) {
  final n = points.length;
  // The average around point i, narrowing toward the ends.
  (double, double) averageAt(int i) {
    final r = math.min(radius, math.min(i, n - 1 - i));
    var x = 0.0, z = 0.0;
    for (var k = -r; k <= r; k++) {
      x += points[i + k].$1;
      z += points[i + k].$2;
    }
    return (x / (2 * r + 1), z / (2 * r + 1));
  }

  return [for (var i = 0; i < n; i++) averageAt(i)];
}

/// Points every [spacing] meters along the polyline, keeping both ends.
List<(double, double)> _resample(
  List<(double, double)> points,
  double spacing,
) {
  final total = _length(points);
  final count = math.max(2, (total / spacing).round() + 1);
  final step = total / (count - 1);
  final out = <(double, double)>[points.first];
  var segment = 0;
  var segmentStart = 0.0;
  for (var k = 1; k < count - 1; k++) {
    final target = k * step;
    while (segment < points.length - 2 &&
        segmentStart + _distance(points[segment], points[segment + 1]) <
            target) {
      segmentStart += _distance(points[segment], points[segment + 1]);
      segment++;
    }
    final a = points[segment], b = points[segment + 1];
    final length = _distance(a, b);
    final t = length == 0
        ? 0.0
        : ((target - segmentStart) / length).clamp(0.0, 1.0);
    out.add((a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t));
  }
  out.add(points.last);
  return out;
}
