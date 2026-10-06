import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../geometry/track_projector.dart';
import 'car_motion.dart';

/// Moves cars beside each other where the data has them on top of each
/// other.
///
/// OpenF1 places every car on one shared line around the lap: cars at the
/// same distance along it are at the same spot, to a few centimetres, so
/// the data says nothing about who is beside whom. Real cars within a car
/// length of each other are side by side, so this steps them apart across
/// the track: smoothly as they close in (sooner the faster they close) and
/// back onto the line as they part. Side by side, the lower car number is
/// always on the left, so no car crosses through another to swap sides.
///
/// Each pair is a spring that grows from nothing as the cars close in, so
/// every car moves continuously, even when two pairs meet and the pack
/// reorders across the track: that happens while they are still apart
/// along it. Every result depends only on the poses given, so it holds when
/// scrubbing.
class TrafficSeparation {
  TrafficSeparation(this.track);

  final TrackProjector track;

  /// Along-track gap, meters, under which two cars must be fully side by
  /// side: a car length with a little room.
  static const double sideBySideGap = 5.6;

  /// Center-to-center distance the springs pull cars side by side to,
  /// meters; a lone pair settles at [_maxShare] of it.
  static const double sideBySideSpacing = 2.4;

  /// The most of [sideBySideSpacing] a lone pair is held to: a stiffer
  /// spring would settle slower in the solve.
  static const double _maxShare = 0.95;

  /// Gauss-Seidel sweeps; enough to settle a pack several abreast.
  static const _sweeps = 40;

  /// Seconds back to solve again, to tell how fast each car is stepping
  /// sideways and so how far to turn it into the step.
  static const double _yawLead = 0.15;

  /// [poses] with every car on the circuit moved clear of the others.
  Map<int, CarPose> separate(Map<int, CarPose> poses) {
    // By car number, so the solve visits cars in the same order whoever
    // joins or leaves the track.
    final cars = [
      for (final MapEntry(key: driver, value: pose) in poses.entries)
        if (pose.along != null) (driver: driver, pose: pose),
    ]..sort((a, b) => a.driver.compareTo(b.driver));
    if (cars.length < 2) return poses;
    final now = _solve(cars, 0);
    final before = _solve(cars, _yawLead);
    final out = Map.of(poses);
    for (var i = 0; i < cars.length; i++) {
      final (:driver, :pose) = cars[i];
      // Untouched now and a moment ago; a car just back on the line is
      // still turning out of its step.
      if ((now[i] - pose.lateral).abs() < 1e-4 &&
          (before[i] - pose.lateral).abs() < 1e-4) {
        continue;
      }
      final placed = track.place(pose.along!, now[i]);
      final sideways = (now[i] - before[i]) / _yawLead;
      out[driver] = CarPose(
        placed.position,
        pose.heading + CarMotion.yawFor(sideways, pose.speed),
        pitch: pose.pitch,
        along: pose.along,
        lateral: now[i],
        speed: pose.speed,
      );
    }
    return out;
  }

  /// Each car's lateral offset clear of the others, with every car moved
  /// [back] seconds back along the track at its speed.
  List<double> _solve(List<({int driver, CarPose pose})> cars, double back) {
    final mps = track.metersPerStation;
    final lap = track.stations.length * mps;
    final along = [
      for (final c in cars) c.pose.along! * mps - c.pose.speed * back,
    ];
    final base = [for (final c in cars) c.pose.lateral];
    final limits = [
      for (var i = 0; i < cars.length; i++)
        track.lateralLimits(
          (along[i] / mps) % track.stations.length,
          margin: CarMotion.carHalfWidth,
        ),
    ];

    // Each car's springs to the cars close to it: the other car, the
    // spring's stiffness and which side this car takes (+1 left). Cars are
    // in number order, so car i, the lower number, always takes the left.
    final springs = [for (final _ in cars) <(int, double, double)>[]];
    var any = false;
    for (var i = 0; i < cars.length; i++) {
      for (var j = i + 1; j < cars.length; j++) {
        var gap = (along[i] - along[j]).abs() % lap;
        if (gap > lap / 2) gap = lap - gap;
        // Start stepping aside sooner the faster the gap closes.
        final closing = (cars[i].pose.speed - cars[j].pose.speed).abs();
        final reach = sideBySideGap + (1.2 * closing).clamp(4.0, 25.0);
        if (gap >= reach) continue;
        final f = ((reach - gap) / (reach - sideBySideGap)).clamp(0.0, 1.0);
        final share = math.min(f * f * (3 - 2 * f), _maxShare); // smoothstep
        if (share <= 0) continue;
        // Stiffness that holds a lone pair exactly [share] of
        // [sideBySideSpacing] apart against each car's pull back to the line.
        final k = share / (2 * (1 - share));
        springs[i].add((j, k, 1.0));
        springs[j].add((i, k, -1.0));
        any = true;
      }
    }
    if (!any) return base;

    // Each car in turn settles where its pull back to the line balances
    // its springs, inside the track edges. A spring only pushes: once its
    // two cars are [sideBySideSpacing] apart it lets go, so the outer cars
    // of three abreast don't squeeze the middle one.
    final lateral = [...base];
    for (var sweep = 0; sweep < _sweeps; sweep++) {
      for (var i = 0; i < cars.length; i++) {
        final mine = springs[i];
        if (mine.isEmpty) continue;
        // Where each spring lets go of this car, given the other's place.
        bool pushing((int, double, double) spring, double at) {
          final (j, _, side) = spring;
          final free = lateral[j] + side * sideBySideSpacing;
          return side > 0 ? at < free : at > free;
        }

        // The balance is piecewise linear in this car's offset; settle the
        // set of springs still pushing at the balance (a few rounds do).
        var at = lateral[i];
        for (var round = 0; round < 6; round++) {
          var sum = base[i], weight = 1.0;
          for (final spring in mine) {
            if (!pushing(spring, at)) continue;
            final (j, k, side) = spring;
            sum += k * (lateral[j] + side * sideBySideSpacing);
            weight += k;
          }
          final next = sum / weight;
          final settled = mine.every(
            (spring) => pushing(spring, next) == pushing(spring, at),
          );
          at = next;
          if (settled) break;
        }
        lateral[i] = at.clamp(limits[i].min, limits[i].max);
      }
    }
    return lateral;
  }
}

/// How far each car in [poses] can be enlarged, up to [scale], before its
/// footprint would overlap another's.
///
/// Cars at real size are a few pixels from a whole-circuit view, so the
/// orbit camera enlarges them; enlarged cars racing a few meters apart
/// would merge into one. Each car shrinks toward real size as another
/// comes within [scale] car lengths, smoothly, so a lone car stays easy to
/// spot and a battle shows who is where.
Map<int, double> readableScales(Map<int, CarPose> poses, double scale) {
  // A car's footprint with a little room, meters.
  const footprintLength = 5.4, footprintWidth = 2.1;
  final cars = poses.entries.toList();
  final out = {for (final MapEntry(:key) in cars) key: scale};
  for (var i = 0; i < cars.length; i++) {
    final a = cars[i].value;
    final forward = Vector2(math.sin(a.heading), math.cos(a.heading));
    for (var j = i + 1; j < cars.length; j++) {
      final b = cars[j].value;
      final d = Vector2(
        b.position.x - a.position.x,
        b.position.z - a.position.z,
      );
      if (d.length > scale * footprintLength) continue;
      // How many times its own footprint fits between the two, measured
      // along and across the car, with rounded corners so it varies
      // smoothly as cars move round each other.
      final along = d.dot(forward) / footprintLength;
      final across = d.cross(forward) / footprintWidth;
      final fits = math
          .pow(math.pow(along, 4) + math.pow(across, 4), 0.25)
          .toDouble();
      final limit = math.max(1.0, fits);
      out[cars[i].key] = math.min(out[cars[i].key]!, limit);
      out[cars[j].key] = math.min(out[cars[j].key]!, limit);
    }
  }
  return out;
}
