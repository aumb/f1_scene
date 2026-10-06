import 'package:flutter_test/flutter_test.dart';

import '../support/circuits.dart';

void main() {
  final (:stations, track: projector) = bahrain();

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
    final (:min, :max) = projector.lateralLimits(100, margin: 1);
    expect(max, closeTo(stations.leftOffset[100] - 1, 1e-9));
    expect(min, closeTo(-(stations.rightOffset[100] - 1), 1e-9));
  });
}
