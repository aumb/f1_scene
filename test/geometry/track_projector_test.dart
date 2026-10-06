import 'dart:math' as math;

import 'package:f1_scene/src/geometry/pit_lane.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/circuits.dart';

void main() {
  final stations = TrackStations.sample(loadCircuit('bh-2002'));
  final projector = TrackProjector(stations);

  test('place and project round-trip along the whole lap', () {
    for (var along = 0.0; along < stations.length; along += 37.3) {
      for (final lateral in [-4.0, 0.0, 3.5]) {
        final p = projector.place(along, lateral).position;
        final back = projector.project(p.x, p.z);
        expect(back.along, closeTo(along, 0.05), reason: 'along $along');
        expect(back.lateral, closeTo(lateral, 0.05), reason: 'along $along');
      }
    }
  });

  test('a hint keeps the projection on its own stretch of track', () {
    // Turn 1 hairpin: the two sides of it lie close together.
    final into = projector.place(285, 0).position;
    final hinted = projector.project(into.x, into.z, hint: 280);
    expect(hinted.along, closeTo(285, 0.5));
  });

  test('a point just beyond the hinted window is not pinned to its edge', () {
    // 66 stations ahead of the hint (a car 1.3 s ahead at 330 km/h), and
    // within reach of the window's last segment.
    for (final hint in [100, stations.length - 30]) {
      final along = (hint + 66) % stations.length;
      final p = projector.place(along.toDouble(), 0).position;
      final hinted = projector.project(p.x, p.z, hint: hint);
      expect(hinted.along, closeTo(along, 0.05), reason: 'hint $hint');
    }
  });

  test('lateral limits keep a car inside the edges', () {
    final (right, left) = projector.lateralLimits(100, margin: 1);
    expect(left, closeTo(stations.leftOffset[100] - 1, 1e-9));
    expect(right, closeTo(-(stations.rightOffset[100] - 1), 1e-9));
  });

  group('pit lane from a stop', () {
    // A car leaves the track, runs 25 m to the right of it for ~400 m with a
    // stationary stop, then rejoins. Samples every 6 m, like 3.7 Hz at the
    // pit speed limit.
    List<(double, double)> stopPath() {
      final path = <(double, double)>[];
      void at(double along, double lateral) {
        final p = projector.place(along, lateral).position;
        path.add((p.x, p.z));
      }

      for (var a = 0.0; a < 60; a += 3) {
        at(a, -a / 60 * 25); // drifting out to the lane
      }
      for (var a = 60.0; a < 260; a += 3) {
        at(a, -25);
      }
      for (var k = 0; k < 10; k++) {
        at(260, -25); // stationary in the box
      }
      for (var a = 260.0; a < 320; a += 3) {
        at(a, -25 + (a - 260) / 60 * 25); // rejoining
      }
      return path;
    }

    test('follows the lane beside the track', () {
      final lane = pitLaneFromPath(stopPath(), projector)!;
      expect(lane.closed, isFalse);
      // Every lane point sits beside the track, not on it (except the ends).
      for (var i = 5; i < lane.length - 5; i++) {
        final c = lane.center[i];
        final p = projector.project(c.x, c.z);
        expect(p.lateral, lessThan(-8), reason: 'station $i');
      }
      final length = (lane.length - 1) * 2.0;
      expect(length, inInclusiveRange(400, 640));
    });

    test('is absent when the car never leaves the track', () {
      final path = [
        for (var a = 0.0; a < 300; a += 3)
          () {
            final p = projector.place(a, 1).position;
            return (p.x, p.z);
          }(),
      ];
      expect(pitLaneFromPath(path, projector), isNull);
    });
  });

  test('open paths have one fewer segment than stations', () {
    final lane = TrackStations.fromPath(
      [for (var i = 0; i < 10; i++) stations.center[i] + stations.left[i] * 30],
      List.filled(10, 5),
      closed: false,
    );
    expect(lane.segmentCount, 9);
    expect(
      ribbonSurface(
        lane,
        uniformRibbonColors(lane, linearColor(0)),
      ).triangleCount,
      18,
    );
    expect(math.max(lane.leftOffset.first, lane.rightOffset.last), 5);
  });
}
