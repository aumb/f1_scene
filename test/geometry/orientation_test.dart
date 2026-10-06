import 'package:f1_scene/src/geometry/geo.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import '../support/circuits.dart';

/// The scene must read as a map: flutter_scene's world is left-handed, so
/// these pin down which way every axis and "left" point.
void main() {
  test('east is +X and north is +Z', () {
    final projection = LocalProjection(0, 45);
    expect(projection.project(0.001, 45).x, greaterThan(0));
    expect(projection.project(0, 45.001).z, greaterThan(0));
  });

  test('measures a degree as the WGS84 ellipsoid does', () {
    // At 45°, a degree of latitude is 111,132 m and of longitude 78,847 m.
    final projection = LocalProjection(0, 45);
    expect(projection.project(0, 46).z, closeTo(111132, 50));
    expect(projection.project(1, 45).x, closeTo(78847, 5));
  });

  test('left of north is west', () {
    final left = leftOf(Vector3(0, 0, 1));
    expect(left.x, closeTo(-1, 1e-9));
    expect(left.z, closeTo(0, 1e-9));
  });

  test('a turn toward the left is positive', () {
    final north = Vector3(0, 0, 1);
    final northWest = Vector3(-1, 0, 1)..normalize();
    expect(leftTurn(north, northWest), greaterThan(0));
    expect(leftTurn(northWest, north), lessThan(0));
  });

  /// Twice the signed area enclosed by [stations] on a map with east to
  /// the right and north up: negative when they run clockwise.
  double mapArea(TrackStations stations) {
    var sum = 0.0;
    for (var i = 0; i < stations.length; i++) {
      final a = stations.center[i];
      final b = stations.center[(i + 1) % stations.length];
      sum += a.x * b.z - b.x * a.z;
    }
    return sum;
  }

  test('Monza runs clockwise and Interlagos counter-clockwise', () {
    expect(mapArea(TrackStations.sample(loadCircuit('it-1922'))), lessThan(0));
    expect(
      mapArea(TrackStations.sample(loadCircuit('br-1940'))),
      greaterThan(0),
    );
  });
}
