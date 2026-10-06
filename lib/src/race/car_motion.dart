import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../geometry/track_alignment.dart';
import '../geometry/track_projector.dart';
import 'location_timeline.dart';

/// Where a car is at some moment, in scene space.
class CarPose {
  const CarPose(this.position, this.heading, {this.inPit = false});

  /// On the driving surface.
  final Vector3 position;

  /// Yaw in radians about +Y; 0 faces +Z.
  final double heading;

  /// In the pit lane, or crossing into or out of it.
  final bool inPit;
}

/// Turns raw OpenF1 position samples into poses that ride the track.
///
/// Each sample is expressed along the circuit (or the pit lane, when the car
/// is clearly beside the track and near it), then interpolated in those
/// coordinates. That follows corners instead of cutting the chords between
/// samples 20 m apart, smooths speed, and keeps every car on the ribbon
/// despite the few meters of alignment error and sensor noise.
class CarMotion {
  CarMotion({required this.alignment, required this.track, this.pitLane});

  final SimilarityTransform2D alignment;
  final TrackProjector track;
  final TrackProjector? pitLane;

  /// Half a car's width; it stays this far inside the edges.
  static const double carHalfWidth = 1.0;

  /// A car this far beyond the track edge may be in the pit lane...
  static const double _pitMinOffTrack = 2.0;

  /// ...if it is also within this of the pit lane path (or in a garage
  /// beside it).
  static const double _pitMaxDistance = 15.0;

  final _trackHints = <int, int>{};
  final _pitHints = <int, int>{};

  /// The pose of [driver] at [t] from its samples [window], or null.
  CarPose? pose(int driver, SampleWindow? window, double t) {
    if (window == null) return null;
    final samples = [
      for (var i = 0; i < window.t.length; i++)
        _locate(driver, window.x[i], window.y[i]),
    ];
    final a = window.bracket, b = a + 1;
    final sa = samples[a], sb = samples[b];
    _trackHints[driver] = sa.track.station;
    if (sa.pit case final pit?) _pitHints[driver] = pit.station;

    final dt = window.t[b] - window.t[a];
    final f = dt > 0 ? ((t - window.t[a]) / dt).clamp(0.0, 1.0) : 0.0;

    if (sa.onPit != sb.onPit) return _blend(sa, sb, f);
    final onPit = sa.onPit;
    final projector = onPit ? pitLane! : track;
    PathPoint pointOf(_Located s) => onPit ? s.pit! : s.track;

    // Positions along the path, unwrapped around the start/finish seam.
    final n = projector.stations.length;
    final origin = pointOf(sa).along;
    double along(_Located s) {
      var d = pointOf(s).along - origin;
      if (projector.stations.closed) {
        if (d > n / 2) d -= n;
        if (d < -n / 2) d += n;
      }
      return origin + d;
    }

    final p0 = along(sa), p1 = along(sb);
    final secant = dt > 0 ? (p1 - p0) / dt : 0.0;
    double tangent(int i, int j) {
      // Only samples on the same path give a meaningful tangent; at the pit
      // entry and exit a neighbour may sit on the other one.
      final usable =
          i >= 0 &&
          j < samples.length &&
          samples[i].onPit == onPit &&
          samples[j].onPit == onPit;
      if (!usable) return secant;
      final m =
          (along(samples[j]) - along(samples[i])) / (window.t[j] - window.t[i]);
      // Monotone: never reverse between samples, never overshoot wildly.
      if (m * secant <= 0) return 0;
      return m.abs() > 3 * secant.abs() ? 3 * secant : m;
    }

    final m0 = tangent(a - 1, b) * dt, m1 = tangent(a, b + 1) * dt;
    final f2 = f * f, f3 = f2 * f;
    final position =
        (2 * f3 - 3 * f2 + 1) * p0 +
        (f3 - 2 * f2 + f) * m0 +
        (-2 * f3 + 3 * f2) * p1 +
        (f3 - f2) * m1;
    final velocity = dt > 0
        ? ((6 * f2 - 6 * f) * p0 +
                  (3 * f2 - 4 * f + 1) * m0 +
                  (-6 * f2 + 6 * f) * p1 +
                  (3 * f2 - 2 * f) * m1) /
              dt
        : 0.0;

    final la = pointOf(sa).lateral, lb = pointOf(sb).lateral;
    final (lo, hi) = projector.lateralLimits(position, margin: carHalfWidth);
    final lateral = (la + (lb - la) * f).clamp(lo, hi);
    final placed = projector.place(position, lateral);

    var heading = math.atan2(placed.forward.x, placed.forward.z);
    final speed = velocity * projector.metersPerStation;
    if (speed > 2 && dt > 0) {
      // Yaw into a lane change, capped so noise never spins a car.
      heading += math.atan2((lb - la) / dt, speed).clamp(-0.5, 0.5);
    }
    return CarPose(placed.position, heading, inPit: onPit);
  }

  /// Crossing between track and pit lane: straight-line blend of the two
  /// samples, at the track's height.
  CarPose _blend(_Located a, _Located b, double f) {
    final x = a.x + (b.x - a.x) * f, z = a.z + (b.z - a.z) * f;
    final y = track.place(a.track.along, 0).position.y;
    return CarPose(
      Vector3(x, y, z),
      math.atan2(b.x - a.x, b.z - a.z),
      inPit: true,
    );
  }

  _Located _locate(int driver, double rawX, double rawY) {
    final (x, z) = alignment.apply(rawX, rawY);
    final onTrack = track.project(x, z, hint: _trackHints[driver]);
    final pitLane = this.pitLane;
    PathPoint? pit;
    if (pitLane != null) {
      final (lo, hi) = track.lateralLimits(onTrack.along);
      final beyond = math.max(onTrack.lateral - hi, lo - onTrack.lateral);
      if (beyond > _pitMinOffTrack) {
        final candidate = pitLane.project(x, z, hint: _pitHints[driver]);
        // Closer to the pit lane than to the track: a car on a straight
        // wider than the track's estimated width (Monaco's grid sits next
        // to the pit lane) stays on track.
        if (candidate.distance <= _pitMaxDistance &&
            candidate.distance < beyond) {
          pit = candidate;
        }
      }
    }
    return _Located(x, z, onTrack, pit);
  }
}

class _Located {
  const _Located(this.x, this.z, this.track, this.pit);

  /// Aligned scene position.
  final double x;
  final double z;
  final PathPoint track;

  /// Set when the sample is in the pit lane.
  final PathPoint? pit;

  bool get onPit => pit != null;
}
