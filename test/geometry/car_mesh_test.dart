import 'package:f1_scene/src/geometry/car_mesh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final car = CarMeshes.build();

  test('has F1 proportions and sits on the ground', () {
    final lo = Vector3.all(double.infinity), hi = Vector3.all(-double.infinity);
    for (final mesh in car.all) {
      for (var i = 0; i < mesh.vertexCount; i++) {
        final p = Vector3(
          mesh.positions[i * 3],
          mesh.positions[i * 3 + 1],
          mesh.positions[i * 3 + 2],
        );
        Vector3.min(lo, p, lo);
        Vector3.max(hi, p, hi);
      }
    }
    final size = hi - lo;
    expect(size.z, closeTo(5.4, 0.15), reason: 'length');
    expect(size.x, closeTo(2.0, 0.1), reason: 'width over the wheels');
    expect(size.y, closeTo(1.0, 0.1), reason: 'height to the rear wing');
    expect(lo.y, closeTo(0, 0.01), reason: 'tyres touch the ground');
    expect(hi.z, greaterThan(-lo.z), reason: 'nose points to +Z');
  });

  test('every mesh is non-empty with unit normals and valid indices', () {
    for (final mesh in car.all) {
      expect(mesh.triangleCount, greaterThan(10));
      for (final index in mesh.indices) {
        expect(index, lessThan(mesh.vertexCount));
      }
      for (var i = 0; i < mesh.vertexCount; i++) {
        final n = Vector3(
          mesh.normals[i * 3],
          mesh.normals[i * 3 + 1],
          mesh.normals[i * 3 + 2],
        );
        expect(n.length, closeTo(1, 1e-5));
      }
    }
  });

  test('tyre treads face away from their axles', () {
    final tyres = car.tyres;
    var outward = 0, inward = 0;
    for (var t = 0; t < tyres.triangleCount; t++) {
      final v = [
        for (var k = 0; k < 3; k++)
          () {
            final i = tyres.indices[t * 3 + k];
            return Vector3(
              tyres.positions[i * 3],
              tyres.positions[i * 3 + 1],
              tyres.positions[i * 3 + 2],
            );
          }(),
      ];
      final normal = (v[1] - v[0]).cross(v[2] - v[0]);
      final centroid = (v[0] + v[1] + v[2]) / 3;
      // Radial direction from the nearest axle (y = 0.36, z = +-1.7).
      final axleZ = centroid.z > 0 ? 1.75 : -1.70;
      final radial = Vector3(0, centroid.y - 0.36, centroid.z - axleZ);
      if (radial.length < 0.3) continue; // sidewall, not tread
      if (normal.dot(radial) > 0) {
        outward++;
      } else {
        inward++;
      }
    }
    expect(inward, 0);
    expect(outward, greaterThan(0));
  });
}
