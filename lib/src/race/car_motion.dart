import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../geometry/track_alignment.dart';
import '../geometry/track_projector.dart';
import 'local_fit.dart';
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

  /// Yaw in radians about +Y: 0 faces +Z (north), and it grows as the car
  /// turns right (clockwise seen from above).
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

  /// The change in heading, radians, that points a car where it is going
  /// when it moves left at [leftward] m/s while driving at [speed] m/s
  /// (negative: heading grows turning right). Capped, so noise never
  /// twitches a car, and gentle at walking pace, where any sideways drift
  /// would swing it round; none at all below [_minTurnSpeed].
  static double yawFor(double leftward, double speed) {
    if (speed <= _minTurnSpeed) return 0;
    return -math
        .atan2(leftward, math.max(speed, _gentleBelow))
        .clamp(-_maxYaw, _maxYaw);
  }

  /// Speeds, m/s, below which a car doesn't turn into sideways motion at
  /// all, and below which it turns as little as it would at that speed.
  static const double _minTurnSpeed = 2, _gentleBelow = 15;

  /// The most a car turns into sideways motion: about 17°, a sharp lane
  /// change.
  static const double _maxYaw = 0.3;

  /// A car this far beyond the track edge may be in the pit lane...
  static const double _pitMinOffTrack = 2.0;

  /// ...if it is also within this of the pit lane path (or in a garage
  /// beside it).
  static const double _pitMaxDistance = 15.0;

  /// Half-width, in seconds, of the window of samples each pose is fitted
  /// to: ~10 samples, enough to average out timing noise while following
  /// full braking.
  static const double fitHalfWidth = 1.3;

  final _trackHints = <int, int>{};

  /// Each driver's recently located samples by time. Playback moves on at
  /// most a few samples per frame, even at 64x, so a few windows' worth
  /// covers it; locating a sample once also keeps its place fixed instead of
  /// shifting with the projection hint from frame to frame.
  final _located = <int, Map<double, _Located>>{};
  static const _cacheSize = 32;

  /// The pose of [driver] at [t] from its samples [window], or null. The
  /// window should reach [fitHalfWidth] seconds either side of [t].
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
      return _blend(sa, sb, window.t[a], window.t[b], t);
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
      fitHalfWidth,
      1.2 * math.max(t - window.t[a], window.t[b] - t),
    );
    final alongFit = LocalFit(), lateralFit = LocalFit();
    for (var i = first; i <= last; i++) {
      final u = window.t[i] - t;
      final w = tricube(u / reach);
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
    final speed = velocity * projector.metersPerStation;
    return CarPose(
      placed.position,
      math.atan2(forward.x, forward.z) + yawFor(lateralVelocity, speed),
      pitch: math.asin(forward.y.clamp(-1.0, 1.0)),
      inPit: onPit,
      along: onPit ? null : position % n,
      lateral: lateral,
      speed: speed,
    );
  }

  /// Crossing between track and pit lane at [t]: a straight line from
  /// sample [a] at [ta] to [b] at [tb], at the track's height.
  CarPose _blend(_Located a, _Located b, double ta, double tb, double t) {
    final dx = b.x - a.x, dz = b.z - a.z;
    final dt = tb - ta;
    final f = dt > 0 ? ((t - ta) / dt).clamp(0.0, 1.0) : 0.0;
    return CarPose(
      Vector3(
        a.x + dx * f,
        track.place(a.track.along, 0).position.y,
        a.z + dz * f,
      ),
      math.atan2(dx, dz),
      inPit: true,
      speed: dt > 0 ? math.sqrt(dx * dx + dz * dz) / dt : 0,
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
