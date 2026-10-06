import 'dart:math' as math;

import 'package:f1_scene/src/geometry/track_alignment.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';
import 'package:f1_scene/src/race/car_motion.dart';
import 'package:f1_scene/src/race/location_timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../support/circuits.dart';

const identity = SimilarityTransform2D(scale: 1, rotation: 0, tx: 0, ty: 0);

void main() {
  final stations = TrackStations.sample(loadCircuit('bh-2002'));
  final track = TrackProjector(stations);

  /// Samples of a car driving at [speed] m/s from station [from], [lateral]
  /// meters left of the centerline, every 0.26 s (OpenF1's ~3.85 Hz).
  SampleWindow windowAround(
    double t, {
    required double from,
    double speed = 30,
    double lateral = 2,
  }) {
    final times = <double>[], xs = <double>[], ys = <double>[];
    final base = (t / 0.26).floor() - 1;
    for (var k = base; k < base + 4; k++) {
      final time = k * 0.26;
      final along = from + time * speed / track.metersPerStation;
      final p = track.place(along, lateral).position;
      times.add(time);
      xs.add(p.x);
      ys.add(p.z);
    }
    return SampleWindow(times, xs, ys, 1);
  }

  test('follows the track through a hairpin instead of cutting it', () {
    final motion = CarMotion(alignment: identity, track: track);
    // Bahrain T1 is around station 285.
    var maxOffCenter = 0.0;
    for (var t = 0.3; t < 6; t += 0.05) {
      final pose = motion.pose(1, windowAround(t, from: 250), t)!;
      final p = track.project(pose.position.x, pose.position.z);
      maxOffCenter = math.max(maxOffCenter, (p.lateral - 2).abs());
    }
    // A straight line between samples 8 m apart would stray much further
    // at the apex; track-space interpolation stays on the racing line.
    expect(maxOffCenter, lessThan(0.3));
  });

  test('moves at a steady speed between samples', () {
    final motion = CarMotion(alignment: identity, track: track);
    Vector3 at(double t) => motion
        .pose(1, windowAround(t, from: 1000, speed: 80, lateral: 0), t)!
        .position;

    const dt = 0.05;
    for (var t = 0.3; t < 3; t += 0.1) {
      final speed = at(t + dt).distanceTo(at(t)) / dt;
      expect(speed, closeTo(80, 2), reason: 't $t');
    }
  });

  test('keeps the car inside the track edges', () {
    final motion = CarMotion(alignment: identity, track: track);
    // Samples 3 m beyond the left edge (alignment error, a wide moment).
    for (var t = 0.3; t < 2; t += 0.1) {
      final pose = motion.pose(
        1,
        windowAround(t, from: 600, lateral: stations.leftOffset[600] + 3),
        t,
      )!;
      final p = track.project(pose.position.x, pose.position.z);
      final edge = math.max(
        stations.leftOffset[p.station],
        stations.leftOffset[p.station + 1],
      );
      expect(
        p.lateral,
        lessThanOrEqualTo(edge - CarMotion.carHalfWidth + 0.05),
      );
    }
  });

  test('faces along the track when stationary on the grid', () {
    final motion = CarMotion(alignment: identity, track: track);
    final pose = motion.pose(1, windowAround(1, from: 40, speed: 0), 1)!;
    final forward = stations.forward[40];
    expect(pose.heading, closeTo(math.atan2(forward.x, forward.z), 0.05));
  });

  test('handles neighbours on the other path at the pit entry', () {
    // A pit lane 25 m right of the track along stations 100-400.
    final lane = TrackStations.fromPath(
      [
        for (var i = 100; i <= 400; i++)
          stations.center[i] - stations.left[i] * 25,
      ],
      List.filled(301, 5),
      closed: false,
    );
    final motion = CarMotion(
      alignment: identity,
      track: track,
      pitLane: TrackProjector(lane),
    );
    Vector3 lanePoint(int i) => lane.center[i];
    Vector3 trackPoint(int i) => stations.center[i];
    // Two samples in the lane, then the next one back on track.
    final points = [
      lanePoint(200),
      lanePoint(205),
      lanePoint(210),
      trackPoint(320),
    ];
    final window = SampleWindow(
      [0, 0.26, 0.52, 0.78],
      [for (final p in points) p.x],
      [for (final p in points) p.z],
      1,
    );
    final pose = motion.pose(1, window, 0.4)!;
    expect(
      TrackProjector(lane).project(pose.position.x, pose.position.z).distance,
      lessThan(1),
    );
  });

  test('a car just wide of the estimated edge is not in the pit lane', () {
    // Pit lane 10 m beyond the left edge along stations 100-400, as at
    // Monaco, where the grid is wider than the estimated track width.
    final lane = TrackStations.fromPath(
      [
        for (var i = 100; i <= 400; i++)
          stations.center[i] + stations.left[i] * (stations.leftOffset[i] + 10),
      ],
      List.filled(301, 5),
      closed: false,
    );
    final motion = CarMotion(
      alignment: identity,
      track: track,
      pitLane: TrackProjector(lane),
    );
    final wide = motion.pose(
      1,
      windowAround(
        1,
        from: 200,
        speed: 0,
        lateral: stations.leftOffset[200] + 2.5,
      ),
      1,
    )!;
    expect(wide.inPit, isFalse);
    final inLane = motion.pose(
      2,
      windowAround(
        1,
        from: 200,
        speed: 0,
        lateral: stations.leftOffset[200] + 10,
      ),
      1,
    )!;
    expect(inLane.inPit, isTrue);
  });

  test('crosses the start/finish seam without a jump', () {
    final motion = CarMotion(alignment: identity, track: track);
    final n = stations.length.toDouble();
    Vector? last;
    for (var t = 0.3; t < 3; t += 0.05) {
      final pose = motion.pose(1, windowAround(t, from: n - 20, speed: 40), t)!;
      final p = (pose.position.x, pose.position.z);
      if (last != null) {
        final step = math.sqrt(
          math.pow(p.$1 - last.$1, 2) + math.pow(p.$2 - last.$2, 2),
        );
        expect(step, lessThan(3), reason: 't $t');
      }
      last = p;
    }
  });
}

typedef Vector = (double, double);
