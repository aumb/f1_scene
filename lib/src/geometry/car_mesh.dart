import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'track_mesh.dart';

/// A low-poly 2026-proportioned F1 car, one mesh per material.
///
/// Car space: origin on the ground under the middle of the car, +Z forward,
/// +Y up, +X to the car's left. About 5.4 m long and 1.9 m wide.
class CarMeshes {
  CarMeshes._(this.body, this.carbon, this.tyres, this.accent);

  /// Builds the car. Pure Dart; no GPU needed.
  factory CarMeshes.build() {
    final body = _Accumulator();
    final carbon = _Accumulator();
    final tyres = _Accumulator();
    final accent = _Accumulator();

    // Monocoque, nose to gearbox: (z, center height, width, height).
    body.loft(const [
      (2.62, 0.21, 0.14, 0.10),
      (2.05, 0.29, 0.30, 0.22),
      (1.35, 0.37, 0.46, 0.36),
      (0.70, 0.45, 0.62, 0.50),
      (0.00, 0.46, 0.78, 0.56),
      (-0.80, 0.52, 0.66, 0.66),
      (-1.60, 0.42, 0.44, 0.42),
      (-2.15, 0.34, 0.26, 0.24),
    ]);
    // Sidepods either side of the cockpit, undercut toward the back.
    body.loft(const [
      (0.45, 0.34, 1.30, 0.30),
      (-0.20, 0.35, 1.44, 0.40),
      (-1.25, 0.28, 0.86, 0.26),
    ]);
    // Airbox and engine-cover fin above and behind the driver.
    body.loft(const [
      (-0.05, 0.86, 0.20, 0.16),
      (-0.45, 0.84, 0.24, 0.26),
      (-1.30, 0.66, 0.06, 0.20),
    ]);

    // Floor, wings and their supports.
    carbon.box(Vector3(0, 0.06, -0.25), Vector3(1.50, 0.04, 3.30));
    carbon.box(Vector3(0, 0.10, 2.45), Vector3(1.80, 0.05, 0.42));
    body.box(Vector3(0, 0.18, 2.36), Vector3(1.66, 0.04, 0.20), pitch: -0.35);
    for (final side in [-1.0, 1.0]) {
      carbon.box(Vector3(side * 0.91, 0.16, 2.45), Vector3(0.03, 0.22, 0.46));
      carbon.box(Vector3(side * 0.50, 0.70, -2.36), Vector3(0.03, 0.50, 0.56));
    }
    body.box(Vector3(0, 0.88, -2.40), Vector3(1.00, 0.05, 0.32));
    body.box(Vector3(0, 0.98, -2.28), Vector3(1.00, 0.04, 0.18), pitch: 0.5);
    carbon.box(Vector3(0, 0.62, -2.30), Vector3(0.06, 0.48, 0.20));
    // Beam wing, its top kept clear of the pylon's base.
    carbon.box(Vector3(0, 0.34, -2.30), Vector3(0.94, 0.04, 0.16));

    // Halo over the cockpit, and its centre pillar.
    carbon.tube([
      Vector3(-0.30, 0.68, 0.12),
      Vector3(-0.28, 0.78, 0.42),
      Vector3(0.00, 0.82, 0.64),
      Vector3(0.28, 0.78, 0.42),
      Vector3(0.30, 0.68, 0.12),
    ], 0.028);
    carbon.tube([Vector3(0, 0.62, 0.66), Vector3(0, 0.81, 0.64)], 0.03);
    accent.sphere(Vector3(0, 0.80, 0.08), 0.13);

    // Wheels: 18-inch rims on 0.72 m tyres; rears wider than fronts. The
    // covers stand 1 cm off the sidewalls so the two never share a plane.
    for (final side in [-1.0, 1.0]) {
      tyres.wheel(Vector3(side * 0.80, 0.36, 1.75), radius: 0.36, width: 0.30);
      tyres.wheel(Vector3(side * 0.80, 0.36, -1.70), radius: 0.36, width: 0.38);
      accent.wheel(Vector3(side * 0.97, 0.36, 1.75), radius: 0.2, width: 0.02);
      accent.wheel(Vector3(side * 1.01, 0.36, -1.70), radius: 0.2, width: 0.02);
    }

    return CarMeshes._(
      body.build(),
      carbon.build(),
      tyres.build(),
      accent.build(),
    );
  }

  /// Painted in the team colour.
  final MeshArrays body;

  /// Floor, wing elements, halo.
  final MeshArrays carbon;
  final MeshArrays tyres;

  /// Helmet and wheel covers.
  final MeshArrays accent;

  List<MeshArrays> get all => [body, carbon, tyres, accent];
}

/// Collects triangles wound to face away from each part's interior, then
/// derives area-weighted vertex normals (smooth where vertices are shared,
/// flat where faces have their own).
class _Accumulator {
  final _positions = <Vector3>[];
  final _indices = <int>[];

  int _vertex(Vector3 p) {
    _positions.add(p);
    return _positions.length - 1;
  }

  /// Adds triangle [a], [b], [c], flipping it if it faces [interior].
  void _triangle(int a, int b, int c, Vector3 interior) {
    final pa = _positions[a], pb = _positions[b], pc = _positions[c];
    final normal = (pb - pa).cross(pc - pa);
    final outward = (pa + pb + pc) / 3 - interior;
    if (normal.dot(outward) >= 0) {
      _indices.addAll([a, b, c]);
    } else {
      _indices.addAll([a, c, b]);
    }
  }

  void _quad(int a, int b, int c, int d, Vector3 interior) {
    _triangle(a, b, c, interior);
    _triangle(a, c, d, interior);
  }

  /// An axis-aligned box, optionally pitched about X (nose up for positive
  /// [pitch]). Faces get their own vertices so they shade flat.
  void box(Vector3 center, Vector3 size, {double pitch = 0}) {
    final rotation = Matrix3.rotationX(-pitch);
    Vector3 corner(double sx, double sy, double sz) =>
        center +
        rotation.transformed(
          Vector3(sx * size.x / 2, sy * size.y / 2, sz * size.z / 2),
        );
    const faces = [
      [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
      [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)],
      [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)],
      [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
      [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
      [(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)],
    ];
    for (final face in faces) {
      final v = [
        for (final (x, y, z) in face)
          _vertex(corner(x.toDouble(), y.toDouble(), z.toDouble())),
      ];
      _quad(v[0], v[1], v[2], v[3], center);
    }
  }

  /// A body lofted through chamfered-rectangle sections
  /// `(z, center height, width, height)`, capped at both ends.
  void loft(List<(double, double, double, double)> sections) {
    final rings = <List<int>>[];
    final centers = <Vector3>[];
    for (final (z, y, w, h) in sections) {
      final c = math.min(w, h) * 0.32;
      final hw = w / 2, hh = h / 2;
      final outline = [
        (hw - c, hh),
        (hw, hh - c),
        (hw, -hh + c),
        (hw - c, -hh),
        (-hw + c, -hh),
        (-hw, -hh + c),
        (-hw, hh - c),
        (-hw + c, hh),
      ];
      rings.add([
        for (final (x, dy) in outline) _vertex(Vector3(x, y + dy, z)),
      ]);
      centers.add(Vector3(0, y, z));
    }
    for (var k = 0; k + 1 < rings.length; k++) {
      final interior = (centers[k] + centers[k + 1]) / 2;
      final a = rings[k], b = rings[k + 1];
      for (var j = 0; j < a.length; j++) {
        final j1 = (j + 1) % a.length;
        _quad(a[j], a[j1], b[j1], b[j], interior);
      }
    }
    // Fan caps, oriented away from the neighbouring section.
    for (final (ring, center, inside) in [
      (rings.first, centers.first, centers[1]),
      (rings.last, centers.last, centers[centers.length - 2]),
    ]) {
      final hub = _vertex(center);
      for (var j = 0; j < ring.length; j++) {
        _triangle(hub, ring[j], ring[(j + 1) % ring.length], inside);
      }
    }
  }

  /// A wheel: a cylinder along X with flat sidewalls.
  void wheel(Vector3 center, {required double radius, required double width}) {
    const segments = 18;
    final sides = [
      for (final dx in [-width / 2, width / 2]) center.x + dx,
    ];
    final rings = [
      for (final x in sides)
        [
          for (var k = 0; k < segments; k++)
            Vector3(
              x,
              center.y + radius * math.cos(2 * math.pi * k / segments),
              center.z + radius * math.sin(2 * math.pi * k / segments),
            ),
        ],
    ];
    // Tread: shared vertices around, so it shades round.
    final tread = [
      for (final ring in rings) [for (final p in ring) _vertex(p)],
    ];
    for (var k = 0; k < segments; k++) {
      final k1 = (k + 1) % segments;
      _quad(tread[0][k], tread[0][k1], tread[1][k1], tread[1][k], center);
    }
    // Sidewalls: their own vertices, so they shade flat.
    for (var s = 0; s < 2; s++) {
      final hub = _vertex(Vector3(sides[s], center.y, center.z));
      final rim = [for (final p in rings[s]) _vertex(p)];
      final inside = Vector3(center.x + (s == 0 ? 1 : -1), center.y, center.z);
      for (var k = 0; k < segments; k++) {
        _triangle(hub, rim[k], rim[(k + 1) % segments], inside);
      }
    }
  }

  /// A round tube of [radius] through [points].
  void tube(List<Vector3> points, double radius) {
    const segments = 8;
    final rings = <List<int>>[];
    var normal = Vector3(0, 1, 0);
    for (var i = 0; i < points.length; i++) {
      final a = points[math.max(0, i - 1)],
          b = points[math.min(points.length - 1, i + 1)];
      final tangent = (b - a)..normalize();
      // Keep the ring frame from twisting: re-orthogonalize the last normal.
      normal = (normal - tangent * normal.dot(tangent));
      if (normal.length2 < 1e-6) normal = tangent.cross(Vector3(1, 0, 0));
      normal.normalize();
      final binormal = tangent.cross(normal);
      rings.add([
        for (var k = 0; k < segments; k++)
          _vertex(
            points[i] +
                normal * (radius * math.cos(2 * math.pi * k / segments)) +
                binormal * (radius * math.sin(2 * math.pi * k / segments)),
          ),
      ]);
    }
    for (var i = 0; i + 1 < rings.length; i++) {
      final interior = (points[i] + points[i + 1]) / 2;
      for (var k = 0; k < segments; k++) {
        final k1 = (k + 1) % segments;
        _quad(
          rings[i][k],
          rings[i][k1],
          rings[i + 1][k1],
          rings[i + 1][k],
          interior,
        );
      }
    }
  }

  /// A UV sphere.
  void sphere(Vector3 center, double radius) {
    const rings = 8, segments = 12;
    final grid = [
      for (var r = 0; r <= rings; r++)
        [
          for (var k = 0; k < segments; k++)
            () {
              final phi = math.pi * r / rings;
              final theta = 2 * math.pi * k / segments;
              return _vertex(
                center +
                    Vector3(
                          math.sin(phi) * math.cos(theta),
                          math.cos(phi),
                          math.sin(phi) * math.sin(theta),
                        ) *
                        radius,
              );
            }(),
        ],
    ];
    for (var r = 0; r < rings; r++) {
      for (var k = 0; k < segments; k++) {
        final k1 = (k + 1) % segments;
        _quad(grid[r][k], grid[r][k1], grid[r + 1][k1], grid[r + 1][k], center);
      }
    }
  }

  MeshArrays build() {
    final n = _positions.length;
    final positions = Float32List(n * 3);
    for (var i = 0; i < n; i++) {
      positions[i * 3] = _positions[i].x;
      positions[i * 3 + 1] = _positions[i].y;
      positions[i * 3 + 2] = _positions[i].z;
    }
    // Area-weighted vertex normals from the (outward) windings.
    final sums = List.generate(n, (_) => Vector3.zero());
    for (var t = 0; t < _indices.length; t += 3) {
      final a = _indices[t], b = _indices[t + 1], c = _indices[t + 2];
      final face = (_positions[b] - _positions[a]).cross(
        _positions[c] - _positions[a],
      );
      sums[a].add(face);
      sums[b].add(face);
      sums[c].add(face);
    }
    final normals = Float32List(n * 3);
    for (var i = 0; i < n; i++) {
      final v = sums[i].length2 > 0 ? sums[i].normalized() : Vector3(0, 1, 0);
      normals[i * 3] = v.x;
      normals[i * 3 + 1] = v.y;
      normals[i * 3 + 2] = v.z;
    }
    return MeshArrays(
      positions: positions,
      normals: normals,
      indices: Uint32List.fromList(_indices),
    );
  }
}
