import 'dart:math' as math;

import 'package:f1_scene/src/geometry/mesh_arrays.dart';
import 'package:f1_scene/src/geometry/pit_lane.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/circuits.dart';

void main() {
  final (:stations, track: projector) = bahrain();

  group('pit lane from a stop', () {
    // A car leaves the track, runs 25 m to the right of it for ~400 m with a
    // stationary stop, then rejoins. Samples every 3 stations (~6 m), as
    // OpenF1 gives them at the pit speed limit (~3.85 Hz).
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
      (double, double) onTrack(double along) {
        final p = projector.place(along, 1).position;
        return (p.x, p.z);
      }

      final path = [for (var a = 0.0; a < 300; a += 3) onTrack(a)];
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
    expect(ribbonSurface(lane, linearColor(0)).triangleCount, 18);
    expect(math.max(lane.leftOffset.first, lane.rightOffset.last), 5);
  });
}
