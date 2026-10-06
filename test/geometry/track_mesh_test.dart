import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import '../support/circuits.dart';

/// Face normals of every triangle, from the winding order.
Iterable<Vector3> faceNormals(MeshArrays mesh) sync* {
  Vector3 vertex(int i) => Vector3(
    mesh.positions[i * 3],
    mesh.positions[i * 3 + 1],
    mesh.positions[i * 3 + 2],
  );
  for (var t = 0; t < mesh.triangleCount; t++) {
    final a = vertex(mesh.indices[t * 3]);
    final b = vertex(mesh.indices[t * 3 + 1]);
    final c = vertex(mesh.indices[t * 3 + 2]);
    yield (b - a).cross(c - a);
  }
}

void main() {
  final bahrain = loadCircuit('bh-2002');
  final stations = TrackStations.sample(bahrain);
  final builder = TrackMeshBuilder(bahrain, stations);

  test('stations cover the lap about every 2 m', () {
    final spacing = bahrain.centerline.length / stations.length;
    expect(spacing, inInclusiveRange(1.9, 2.0));
  });

  test('surface faces up on every circuit, hairpins included', () {
    for (final summary in loadSummaries()) {
      final circuit = loadCircuit(summary.id);
      final mesh = TrackMeshBuilder(
        circuit,
        TrackStations.sample(circuit),
      ).surface(TrackColorMode.sectors);
      var t = 0;
      for (final n in faceNormals(mesh)) {
        expect(n.y, greaterThan(0), reason: '${summary.id} triangle $t');
        t++;
      }
    }
  });

  test('inner edge is pulled in only where a corner is too tight', () {
    var pinched = 0;
    for (var i = 0; i < stations.length; i++) {
      expect(stations.leftOffset[i], lessThanOrEqualTo(stations.halfWidth[i]));
      expect(stations.rightOffset[i], lessThanOrEqualTo(stations.halfWidth[i]));
      if (stations.leftOffset[i] < stations.halfWidth[i] - 1e-9 ||
          stations.rightOffset[i] < stations.halfWidth[i] - 1e-9) {
        pinched++;
      }
    }
    expect(pinched / stations.length, lessThan(0.05));
  });

  test('start/finish line faces up', () {
    final mesh = builder.startFinishLine();
    expect(mesh.triangleCount, 32);
    for (final n in faceNormals(mesh)) {
      expect(n.y, greaterThan(0));
    }
  });

  test('skirts face outward from the track', () {
    final mesh = builder.skirts(bahrain.elevationRange.$1 - 1);
    var t = 0;
    for (final n in faceNormals(mesh)) {
      final station = t ~/ 4;
      final left = stations.left[station];
      // Triangles 0-1 of each station are the left skirt, 2-3 the right.
      final outward = (t % 4) < 2 ? left : -left;
      expect(n.dot(outward), greaterThan(0), reason: 'triangle $t');
      t++;
    }
  });

  test('uses the measured width profile', () {
    expect(bahrain.hasMeasuredWidth, isTrue);
    final widths = stations.halfWidth.map((h) => h * 2);
    expect(widths.reduce((a, b) => a < b ? a : b), closeTo(10.77, 0.5));
    expect(widths.reduce((a, b) => a > b ? a : b), closeTo(21.99, 0.5));
  });

  test('sectors follow lap distance from the start/finish line', () {
    expect(bahrain.sectorAt(bahrain.sAtLapDistance(10)).number, 1);
    expect(bahrain.sectorAt(bahrain.sAtLapDistance(2500)).number, 2);
    expect(bahrain.sectorAt(bahrain.sAtLapDistance(5000)).number, 3);
    expect(
      bahrain.lapDistanceAt(bahrain.sAtLapDistance(1234)),
      closeTo(1234, 1e-6),
    );
  });

  group('track details', () {
    test('kerbs line the hairpin but not the main straight', () {
      final kerbs = builder.kerbs();
      expect(kerbs.triangleCount, greaterThan(100));
      for (final n in faceNormals(kerbs)) {
        expect(n.y, greaterThan(0));
      }
      final projector = TrackProjector(stations);
      var atHairpin = false, onStraight = false;
      for (var v = 0; v < kerbs.vertexCount; v++) {
        final p = projector.project(
          kerbs.positions[v * 3],
          kerbs.positions[v * 3 + 2],
        );
        if ((p.along - 285).abs() < 15) atHairpin = true;
        // The pit straight runs either side of the start line (station 0).
        if (p.along > 2600 || p.along < 120) onStraight = true;
      }
      expect(atHairpin, isTrue);
      expect(onStraight, isFalse);
    });

    test('DRS bands cover their spans, across the seam too', () {
      final bands = builder.drsBands([(100.0, 150.0), (2700.0, 20.0)]);
      // 50 stations, plus 16 + 20 across the seam.
      expect(bands.triangleCount, (50 + 36) * 2);
      for (final n in faceNormals(bands)) {
        expect(n.y, greaterThan(0));
      }
    });

    test('one sector line per split after the first', () {
      expect(builder.sectorLines().triangleCount, 2 * 2);
    });
  });
}
