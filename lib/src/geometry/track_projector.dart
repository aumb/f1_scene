import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'point_grid.dart';
import 'track_mesh.dart';

/// A position expressed relative to a path of [TrackStations].
class PathPoint {
  const PathPoint({
    required this.station,
    required this.along,
    required this.lateral,
    required this.distance,
  });

  /// Index of the station starting the segment the point projects onto.
  final int station;

  /// Position along the path in stations: `station + fraction`, within
  /// `[0, length)` on a closed path.
  final double along;

  /// Signed offset from the centerline, positive to the left of travel.
  final double lateral;

  /// Horizontal distance from the centerline.
  final double distance;
}

/// Projects scene positions onto a station path and back.
///
/// Projection searches near a hint station first, so a car keeps to its own
/// stretch where the track passes close to itself (Suzuka's crossover,
/// parallel straights), and falls back to a global search when the hint is
/// lost.
class TrackProjector {
  TrackProjector(this.stations)
    : _grid = PointGrid(
        [for (final c in stations.center) c.x],
        [for (final c in stations.center) c.z],
      ),
      metersPerStation = _spacing(stations);

  final TrackStations stations;
  final PointGrid _grid;

  /// Average distance between consecutive stations.
  final double metersPerStation;

  static double _spacing(TrackStations stations) {
    var length = 0.0;
    for (var i = 0; i < stations.segmentCount; i++) {
      length += stations.center[i].distanceTo(
        stations.center[(i + 1) % stations.length],
      );
    }
    return length / stations.segmentCount;
  }

  /// Stations either side of the hint searched before giving up on it.
  static const int _window = 60;

  /// A hinted match further than this from the path is treated as lost.
  static const double _maxHintedDistance = 25;

  /// Projects ([x], [z]) onto the path.
  PathPoint project(double x, double z, {int? hint}) {
    if (hint != null) {
      final near = _best(x, z, hint - _window, hint + _window);
      if (near.distance <= _maxHintedDistance) return near;
    }
    final nearest = _grid.nearest(x, z).index;
    return _best(x, z, nearest - 2, nearest + 2);
  }

  /// Scene position at [along] stations with a [lateral] offset, and the
  /// unit forward direction there.
  ({Vector3 position, Vector3 forward}) place(double along, double lateral) {
    final n = stations.length;
    final double a;
    if (stations.closed) {
      a = along % n;
    } else {
      a = along.clamp(0.0, n - 1.0);
    }
    final i0 = math.min(a.floor(), stations.segmentCount - 1);
    final i1 = (i0 + 1) % n;
    final f = a - i0;
    final center = _lerp(stations.center[i0], stations.center[i1], f);
    final left = _lerp(stations.left[i0], stations.left[i1], f)..normalize();
    final forward = _lerp(stations.forward[i0], stations.forward[i1], f)
      ..normalize();
    return (position: center + left * lateral, forward: forward);
  }

  /// Lateral offsets keeping a body of [margin] half-width inside the edges
  /// at [along].
  (double, double) lateralLimits(double along, {double margin = 0}) {
    final n = stations.length;
    final i = stations.closed
        ? along.floor() % n
        : along.floor().clamp(0, n - 1);
    return (
      -math.max(0.0, stations.rightOffset[i] - margin),
      math.max(0.0, stations.leftOffset[i] - margin),
    );
  }

  PathPoint _best(double x, double z, int from, int to) {
    final n = stations.length;
    PathPoint? best;
    for (var k = from; k <= to; k++) {
      final int i;
      if (stations.closed) {
        i = (k % n + n) % n;
      } else {
        if (k < 0 || k >= stations.segmentCount) continue;
        i = k;
      }
      final a = stations.center[i], b = stations.center[(i + 1) % n];
      final dx = b.x - a.x, dz = b.z - a.z;
      final length2 = dx * dx + dz * dz;
      final t = length2 == 0
          ? 0.0
          : (((x - a.x) * dx + (z - a.z) * dz) / length2).clamp(0.0, 1.0);
      final px = a.x + dx * t, pz = a.z + dz * t;
      final ex = x - px, ez = z - pz;
      final distance = math.sqrt(ex * ex + ez * ez);
      if (best == null || distance < best.distance) {
        final left = _lerp(stations.left[i], stations.left[(i + 1) % n], t)
          ..normalize();
        best = PathPoint(
          station: i,
          along: stations.closed ? (i + t) % n : i + t,
          lateral: ex * left.x + ez * left.z,
          distance: distance,
        );
      }
    }
    return best!;
  }

  static Vector3 _lerp(Vector3 a, Vector3 b, double t) => a + (b - a) * t;
}
