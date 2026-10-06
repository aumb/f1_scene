import 'dart:math' as math;

import 'package:f1_scene/src/geometry/track_alignment.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/circuits.dart';

/// Builds a fake lap in an "OpenF1 frame": centerline points pushed onto a
/// racing line that swaps sides every corner or so, then mapped through the
/// inverse of a known transform (decimeters, rotated, optionally mirrored,
/// offset).
({List<(double, double)> source, List<(double, double)> truth}) fakeLap(
  TrackStations stations, {
  required double rotation,
  required bool mirrored,
  double wander = 4,
}) {
  final random = math.Random(42);
  final source = <(double, double)>[];
  final truth = <(double, double)>[];
  // A sample every ~16 m, as OpenF1 gives them (~3.85 Hz) at racing speed.
  for (var i = 0; i < stations.length; i += 8) {
    final lateral = wander == 0
        ? 0.0
        : wander * math.sin(i / 12) + (random.nextDouble() - 0.5);
    final p = stations.center[i] + stations.left[i] * lateral;
    truth.add((p.x, p.z));
    // Invert scene = 0.1 * R * M * src + offset.
    final dx = (p.x - 812.0) / 0.1, dz = (p.z + 2290.0) / 0.1;
    final c = math.cos(-rotation), s = math.sin(-rotation);
    final x = c * dx - s * dz, y = s * dx + c * dz;
    source.add((x, mirrored ? -y : y));
  }
  return (source: source, truth: truth);
}

void main() {
  for (final id in ['bh-2002', 'mc-1929', 'be-1925']) {
    final circuit = loadCircuit(id);
    final stations = TrackStations.sample(circuit);
    final target = [for (final c in stations.center) (c.x, c.z)];

    for (final (rotation, mirrored) in [
      (0.4, false),
      (2.9, true),
      (-1.7, false),
    ]) {
      test('$id: recovers rotation $rotation, mirrored $mirrored', () {
        final lap = fakeLap(stations, rotation: rotation, mirrored: mirrored);
        final result = alignToPath(source: lap.source, target: target);

        expect(result.transform.mirrored, mirrored);
        expect(result.transform.scale, closeTo(0.1, 0.002));
        // The racing line wanders up to 4.5 m off the centerline.
        expect(result.rmsError, lessThan(5));
        var worst = 0.0;
        for (var i = 0; i < lap.source.length; i++) {
          final (x, z) = result.transform.apply(
            lap.source[i].$1,
            lap.source[i].$2,
          );
          final (tx, tz) = lap.truth[i];
          worst = math.max(
            worst,
            math.sqrt((x - tx) * (x - tx) + (z - tz) * (z - tz)),
          );
        }
        expect(worst, lessThan(3), reason: '${result.transform}');
      });
    }

    test('$id: is exact when the lap follows the centerline', () {
      final lap = fakeLap(stations, rotation: 1.1, mirrored: true, wander: 0);
      final result = alignToPath(source: lap.source, target: target);
      for (var i = 0; i < lap.source.length; i++) {
        final (x, z) = result.transform.apply(
          lap.source[i].$1,
          lap.source[i].$2,
        );
        expect(x, closeTo(lap.truth[i].$1, 0.05));
        expect(z, closeTo(lap.truth[i].$2, 0.05));
      }
    });
  }
}
