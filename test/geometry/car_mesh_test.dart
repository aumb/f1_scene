import 'package:f1_scene/src/geometry/car_mesh.dart';
import 'package:f1_scene/src/geometry/mesh_arrays.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import '../support/mesh.dart';

void main() {
  final car = CarMeshes.build();

  test('has F1 proportions and sits on the ground', () {
    final lo = Vector3.all(double.infinity), hi = Vector3.all(-double.infinity);
    for (final mesh in car.all) {
      for (var i = 0; i < mesh.vertexCount; i++) {
        final p = vertexOf(mesh, i);
        Vector3.min(lo, p, lo);
        Vector3.max(hi, p, hi);
      }
    }
    final size = hi - lo;
    expect(size.z, closeTo(5.3, 0.15), reason: 'length');
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
    var outward = 0, inward = 0;
    for (final (a, b, c) in trianglesOf(car.tyres)) {
      final normal = (b - a).cross(c - a);
      final centroid = (a + b + c) / 3;
      // Radial direction from the nearer axle (y = 0.36; z = 1.75 front,
      // -1.70 rear).
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

  group('car paint', () {
    final colours = (
      upper: Vector4(1, 0, 0, 1),
      lower: Vector4(0, 1, 0, 1),
      nose: Vector4(0, 0, 1, 1),
      engineCover: Vector4(1, 1, 0, 1),
      wings: Vector4(0, 1, 1, 1),
    );
    final painted = car.paint(colours);
    Vector4 colourOf(int v) => Vector4(
      painted.colors![v * 4],
      painted.colors![v * 4 + 1],
      painted.colors![v * 4 + 2],
      painted.colors![v * 4 + 3],
    );

    test('every face is one colour, so paints meet along crisp lines', () {
      final parts = [
        car.upper,
        car.lower,
        car.nose,
        car.engineCover,
        car.wings,
      ];
      expect(painted.vertexCount, parts.fold(0, (n, p) => n + p.vertexCount));
      for (var t = 0; t < painted.indices.length; t += 3) {
        final a = colourOf(painted.indices[t]);
        expect(colourOf(painted.indices[t + 1]), a);
        expect(colourOf(painted.indices[t + 2]), a);
      }
    });

    test('the lower paint is below the upper', () {
      double meanHeight(MeshArrays mesh) {
        var sum = 0.0;
        for (var v = 0; v < mesh.vertexCount; v++) {
          sum += mesh.positions[v * 3 + 1];
        }
        return sum / mesh.vertexCount;
      }

      expect(meanHeight(car.lower), lessThan(meanHeight(car.upper) - 0.1));
    });

    test('number plates map the whole image', () {
      final plates = car.numberPlates;
      expect(plates.triangleCount, 6); // nose and both endplates
      expect(plates.texCoords, everyElement(inInclusiveRange(0, 1)));
    });
  });
}
