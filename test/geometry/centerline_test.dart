import 'dart:math' as math;

import 'package:f1_scene/src/geometry/centerline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import '../support/circuits.dart';

void main() {
  group('Centerline', () {
    test('passes through its control points', () {
      final points = [
        Vector3(0, 0, 0),
        Vector3(100, 0, 0),
        Vector3(100, 5, 80),
        Vector3(0, 0, 100),
      ];
      final line = Centerline(points);
      for (var i = 0; i < points.length; i++) {
        final p = line.pointAt(line.sAtControlPoint(i));
        expect(p.distanceTo(points[i]), lessThan(1e-6));
      }
    });

    test('approximates a circle closely', () {
      const radius = 200.0;
      final points = [
        for (var i = 0; i < 32; i++)
          Vector3(
            radius * math.cos(i / 32 * 2 * math.pi),
            0,
            radius * math.sin(i / 32 * 2 * math.pi),
          ),
      ];
      final line = Centerline(points);
      expect(line.length, closeTo(2 * math.pi * radius, 1.0));
      for (final p in line.sample(100)) {
        expect(p.length, closeTo(radius, 0.5));
      }
    });

    test('is evenly spaced in arc length', () {
      final line = Centerline([
        Vector3(0, 0, 0),
        Vector3(300, 0, 0),
        Vector3(310, 0, 20),
        Vector3(0, 0, 40),
      ]);
      final samples = line.sample(200);
      final step = line.length / 200;
      for (var i = 0; i < samples.length; i++) {
        final d = samples[i].distanceTo(samples[(i + 1) % samples.length]);
        // Chords are slightly shorter than arcs on curved stretches, and the
        // arc table interpolates linearly, so allow a sliver over.
        expect(d, inInclusiveRange(step * 0.97, step * 1.002));
      }
    });

    test('wraps s outside [0, 1)', () {
      final line = Centerline([
        Vector3(0, 0, 0),
        Vector3(10, 0, 0),
        Vector3(0, 0, 10),
      ]);
      expect(line.pointAt(1.25).distanceTo(line.pointAt(0.25)), lessThan(1e-9));
      expect(
        line.pointAt(-0.25).distanceTo(line.pointAt(0.75)),
        lessThan(1e-9),
      );
    });
  });

  test('every circuit length is within 3% of its official lap length', () {
    for (final summary in loadSummaries()) {
      final circuit = loadCircuit(summary.id);
      final ratio = circuit.centerline.length / circuit.lapLength;
      expect(ratio, inInclusiveRange(0.97, 1.03), reason: summary.id);
    }
  });
}
