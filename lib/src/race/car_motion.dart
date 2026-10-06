import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../geometry/track_alignment.dart';
import '../geometry/track_projector.dart';
import 'location_timeline.dart';

/// Where a car is at some moment, in scene space.
class CarPose {
  const CarPose(
    this.position,
    this.heading, {
    this.pitch = 0,
    this.inPit = false,
    this.along,
    this.lateral = 0,
    this.speed = 0,
  });

  /// On the driving surface.
  final Vector3 position;

  /// Yaw in radians about +Y; 0 faces +Z.
  final double heading;

  /// Nose-up angle in radians, following the track's gradient so the car
  /// sits on slopes instead of cutting into them.
  final double pitch;

  /// In the pit lane, or crossing into or out of it.
  final bool inPit;

  /// Position along the circuit in track stations, when on it.
  final double? along;

  /// Offset left of the centerline (of the pit lane when in it), meters.
  final double lateral;

  /// Speed along the path, m/s.
  final double speed;

  /// The car's orientation: yaw, then pitch about its own lateral axis.
  /// Maps the model's forward (+Z) onto the direction of travel.
  Quaternion get rotation =>
      Quaternion.axisAngle(Vector3(0, 1, 0), heading) *
      Quaternion.axisAngle(Vector3(1, 0, 0), -pitch);
}

/// Turns raw OpenF1 position samples into poses that ride the track.
///
/// Each sample is expressed along the circuit (or the pit lane, when the car
/// is clearly beside the track and near it), and the motion is fitted in
/// those coordinates. That follows corners instead of cutting the chords
/// between samples 20 m apart, smooths speed, and keeps every car on the
/// ribbon despite the few meters of alignment error and sensor noise.
class CarMotion {
  CarMotion({required this.alignment, required this.track, this.pitLane});

  final SimilarityTransform2D alignment;
  final TrackProjector track;
  final TrackProjector? pitLane;

  /// Half a car's width; it stays this far inside the edges.
  static const double carHalfWidth = 1.0;

  /// Speed, m/s, below which sideways motion yaws a car no more than it
  /// would at this speed.
  static const double minYawSpeed = 15;

  /// A car this far beyond the track edge may be in the pit lane...
  static const double _pitMinOffTrack = 2.0;

  /// ...if it is also within this of the pit lane path (or in a garage
  /// beside it).
  static const double _pitMaxDistance = 15.0;

  /// Half-width, in seconds, of the window of samples each pose is fitted
  /// to: ~10 samples, enough to average out timing noise while following
  /// full braking.
  static const double smoothing = 1.3;

  final _trackHints = <int, int>{};

  /// Each driver's recently located samples by time. Playback walks forward
  /// a sample or two per frame, so a few windows' worth covers it; locating a
  /// sample once also keeps its place fixed instead of shifting with the
  /// projection hint from frame to frame.
  final _located = <int, Map<double, _Located>>{};
  static const _cacheSize = 32;

  /// The pose of [driver] at [t] from its samples [window], or null. The
  /// window should reach [smoothing] seconds either side of [t].
  CarPose? pose(int driver, SampleWindow? window, double t) {
    if (window == null) return null;
    final cache = _located.putIfAbsent(driver, () => <double, _Located>{});
    final samples = [
      for (var i = 0; i < window.t.length; i++)
        cache[window.t[i]] ??= _locate(driver, window.x[i], window.y[i]),
    ];
    while (cache.length > _cacheSize) {
      cache.remove(cache.keys.first);
    }
    final a = window.bracket, b = a + 1;
    final sa = samples[a], sb = samples[b];
    _trackHints[driver] = sa.track.station;

    if (sa.onPit != sb.onPit) {
      final dt = window.t[b] - window.t[a];
      return _blend(sa, sb, dt > 0 ? ((t - window.t[a]) / dt).clamp(0, 1) : 0);
    }
    final onPit = sa.onPit;
    final projector = onPit ? pitLane! : track;
    PathPoint pointOf(_Located s) => onPit ? s.pit! : s.track;

    // Only the run of samples on the same path counts; beyond a pit entry or
    // exit, positions along the other path mean nothing here.
    var first = a, last = b;
    while (first > 0 && samples[first - 1].onPit == onPit) {
      first--;
    }
    while (last + 1 < samples.length && samples[last + 1].onPit == onPit) {
      last++;
    }

    // Positions along the path relative to the bracketing sample, unwrapped
    // around the start/finish seam.
    final n = projector.stations.length;
    final origin = pointOf(sa).along;
    double along(_Located s) {
      var d = pointOf(s).along - origin;
      if (projector.stations.closed) {
        if (d > n / 2) d -= n;
        if (d < -n / 2) d += n;
      }
      return d;
    }

    // Fit the motion around [t] rather than pass through every sample: even
    // after stamp correction each carries ~10 ms of timing noise, which an
    // interpolating curve turns into surges of several g between samples.
    // Wide enough to always weigh the bracketing pair, across a gap too.
    final reach = math.max(
      smoothing,
      1.2 * math.max(t - window.t[a], window.t[b] - t),
    );
    final alongFit = _Fit(), lateralFit = _Fit();
    for (var i = first; i <= last; i++) {
      final u = window.t[i] - t;
      final w = _tricube(u / reach);
      if (w == 0) continue;
      alongFit.add(u, along(samples[i]), w);
      lateralFit.add(u, pointOf(samples[i]).lateral, w);
    }
    final (offset, velocity) = alongFit.quadratic();
    final position = origin + offset;
    // Lateral offsets carry a meter or so of noise (sensor, alignment) and
    // change slowly, so a straight line through them suffices.
    final (rawLateral, lateralVelocity) = lateralFit.linear();

    final (lo, hi) = projector.lateralLimits(position, margin: carHalfWidth);
    final lateral = rawLateral.clamp(lo, hi);
    final placed = projector.place(position, lateral);

    final forward = placed.forward;
    var heading = math.atan2(forward.x, forward.z);
    final speed = velocity * projector.metersPerStation;
    if (speed > 2) {
      // Yaw into a lane change, capped so noise never twitches a car, and
      // gentle at walking pace, where any sideways drift would swing it.
      heading += math
          .atan2(lateralVelocity, math.max(speed, minYawSpeed))
          .clamp(-0.3, 0.3);
    }
    return CarPose(
      placed.position,
      heading,
      pitch: math.asin(forward.y.clamp(-1.0, 1.0)),
      inPit: onPit,
      along: onPit ? null : position % n,
      lateral: lateral,
      speed: speed,
    );
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
        // Only the pit lane within reach matters; an uncapped search from
        // the far side of the circuit walks thousands of grid cells.
        final candidate = pitLane.projectWithin(
          x,
          z,
          math.min(_pitMaxDistance, beyond),
        );
        // Closer to the pit lane than to the track: a car on a straight
        // wider than the track's estimated width (Monaco's grid sits next
        // to the pit lane) stays on track.
        if (candidate != null &&
            candidate.distance <= _pitMaxDistance &&
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

/// Weighted least-squares polynomial through (u, y) points, evaluated at
/// u = 0: the level and slope there.
class _Fit {
  int _count = 0;
  double _s0 = 0, _s1 = 0, _s2 = 0, _s3 = 0, _s4 = 0;
  double _t0 = 0, _t1 = 0, _t2 = 0;

  void add(double u, double y, double w) {
    final u2 = u * u;
    _count++;
    _s0 += w;
    _s1 += w * u;
    _s2 += w * u2;
    _s3 += w * u2 * u;
    _s4 += w * u2 * u2;
    _t0 += w * y;
    _t1 += w * u * y;
    _t2 += w * u2 * y;
  }

  (double, double) linear() {
    final det = _s0 * _s2 - _s1 * _s1;
    if (_count < 2 || det.abs() < 1e-12) return (_t0 / _s0, 0);
    final slope = (_s0 * _t1 - _s1 * _t0) / det;
    return ((_t0 - slope * _s1) / _s0, slope);
  }

  /// A parabola, which follows braking and acceleration without the lag a
  /// line would add; a line with too few points to fit one.
  (double, double) quadratic() {
    if (_count < 4) return linear();
    // Cramer's rule on the 3x3 normal equations.
    double det3(
      double a,
      double b,
      double c,
      double d,
      double e,
      double f,
      double g,
      double h,
      double i,
    ) => a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    final det = det3(_s0, _s1, _s2, _s1, _s2, _s3, _s2, _s3, _s4);
    if (det.abs() < 1e-12) return linear();
    final level = det3(_t0, _s1, _s2, _t1, _s2, _s3, _t2, _s3, _s4) / det;
    final slope = det3(_s0, _t0, _s2, _s1, _t1, _s3, _s2, _t2, _s4) / det;
    return (level, slope);
  }
}

double _tricube(double u) {
  final a = u.abs();
  if (a >= 1) return 0;
  final b = 1 - a * a * a;
  return b * b * b;
}
