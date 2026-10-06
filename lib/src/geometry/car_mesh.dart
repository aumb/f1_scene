import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'mesh_arrays.dart';

/// Colours for the painted parts of a car, linear RGBA.
typedef CarPaint = ({
  Vector4 upper,
  Vector4 lower,
  Vector4 nose,
  Vector4 engineCover,
  Vector4 wings,
});

/// A low-poly 2026-proportioned F1 car, built in parts so a livery can
/// paint each its own colour.
///
/// Car space: origin on the ground under the middle of the car, +Z forward,
/// +Y up and, flutter_scene's world being left-handed, +X to the car's
/// right. About 5.3 m long and 2.0 m wide over the wheels.
class CarMeshes {
  CarMeshes._({
    required this.upper,
    required this.lower,
    required this.nose,
    required this.engineCover,
    required this.wings,
    required this.carbon,
    required this.tyres,
    required this.accent,
    required this.numberPlates,
  });

  /// Builds the car. Pure Dart; no GPU needed.
  factory CarMeshes.build() {
    final upper = _PartBuilder();
    final lower = _PartBuilder();
    final nose = _PartBuilder();
    final engineCover = _PartBuilder();
    final wings = _PartBuilder();
    final carbon = _PartBuilder();
    final tyres = _PartBuilder();
    final accent = _PartBuilder();

    // Nose, then the monocoque back to the gearbox, split a little below
    // its middle into upper and lower paint: (z, center height, width,
    // height).
    nose.loft(const [
      (2.62, 0.21, 0.14, 0.10),
      (2.05, 0.29, 0.30, 0.22),
      (1.35, 0.37, 0.46, 0.36),
    ], capBack: false);
    upper.loft(
      const [
        (1.35, 0.37, 0.46, 0.36),
        (0.70, 0.45, 0.62, 0.50),
        (0.00, 0.46, 0.78, 0.56),
        (-0.80, 0.52, 0.66, 0.66),
        (-1.60, 0.42, 0.44, 0.42),
        (-2.15, 0.34, 0.26, 0.24),
      ],
      below: lower,
      split: -0.15,
      capFront: false,
    );
    // Sidepods either side of the cockpit, undercut toward the back.
    upper.loft(
      const [
        (0.45, 0.34, 1.30, 0.30),
        (-0.20, 0.35, 1.44, 0.40),
        (-1.25, 0.28, 0.86, 0.26),
      ],
      below: lower,
      split: 0.1,
    );
    // Airbox and engine-cover fin above and behind the driver.
    engineCover.loft(const [
      (-0.05, 0.86, 0.20, 0.16),
      (-0.45, 0.84, 0.24, 0.26),
      (-1.30, 0.66, 0.06, 0.20),
    ]);

    // Floor, wings and their supports.
    carbon.box(Vector3(0, 0.06, -0.25), Vector3(1.50, 0.04, 3.30));
    carbon.box(Vector3(0, 0.10, 2.45), Vector3(1.80, 0.05, 0.42));
    wings.box(Vector3(0, 0.18, 2.36), Vector3(1.66, 0.04, 0.20), pitch: -0.35);
    for (final side in [-1.0, 1.0]) {
      carbon.box(Vector3(side * 0.91, 0.16, 2.45), Vector3(0.03, 0.22, 0.46));
      carbon.box(
        Vector3(side * _endplateX, 0.70, -2.36),
        Vector3(_endplateThickness, 0.50, 0.56),
      );
    }
    wings.box(Vector3(0, 0.88, -2.40), Vector3(1.00, 0.05, 0.32));
    wings.box(Vector3(0, 0.98, -2.28), Vector3(1.00, 0.04, 0.18), pitch: 0.5);
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
      upper: upper.build(),
      lower: lower.build(),
      nose: nose.build(),
      engineCover: engineCover.build(),
      wings: wings.build(),
      carbon: carbon.build(),
      tyres: tyres.build(),
      accent: accent.build(),
      numberPlates: _numberPlates(),
    );
  }

  static const _endplateX = 0.50, _endplateThickness = 0.03;

  /// Painted bodywork above the livery's dividing line.
  final MeshArrays upper;

  /// Painted bodywork below it.
  final MeshArrays lower;
  final MeshArrays nose;
  final MeshArrays engineCover;

  /// Front wing flap and rear wing planes.
  final MeshArrays wings;

  /// Floor, wing supports, endplates, halo.
  final MeshArrays carbon;
  final MeshArrays tyres;

  /// Helmet and wheel covers.
  final MeshArrays accent;

  /// Where the car number goes: on top of the nose, reading from the front,
  /// and on the outside of both rear wing endplates, reading from beside.
  /// Each plate maps the whole number image (u across, v down).
  final MeshArrays numberPlates;

  List<MeshArrays> get all => [
    upper,
    lower,
    nose,
    engineCover,
    wings,
    carbon,
    tyres,
    accent,
  ];

  /// The painted parts as one mesh, coloured per vertex, so a car draws
  /// its bodywork in one call whatever the livery.
  MeshArrays paint(CarPaint paint) {
    final parts = [
      (upper, paint.upper),
      (lower, paint.lower),
      (nose, paint.nose),
      (engineCover, paint.engineCover),
      (wings, paint.wings),
    ];
    final vertices = parts.fold(0, (n, p) => n + p.$1.vertexCount);
    final triangles = parts.fold(0, (n, p) => n + p.$1.triangleCount);
    final positions = Float32List(vertices * 3);
    final normals = Float32List(vertices * 3);
    final colors = Float32List(vertices * 4);
    final indices = Uint32List(triangles * 3);
    var v = 0, i = 0;
    for (final (mesh, colour) in parts) {
      positions.setAll(v * 3, mesh.positions);
      normals.setAll(v * 3, mesh.normals);
      for (var k = 0; k < mesh.vertexCount; k++) {
        colors.setAll((v + k) * 4, colour.storage);
      }
      for (final index in mesh.indices) {
        indices[i++] = index + v;
      }
      v += mesh.vertexCount;
    }
    return MeshArrays(
      positions: positions,
      normals: normals,
      colors: colors,
      indices: indices,
    );
  }

  static MeshArrays _numberPlates() {
    final mesh = MeshBuilder();
    // Corners listed top left, top right, bottom right, bottom left as the
    // number would read in a right-handed world. flutter_scene's world is
    // left-handed, which shows them mirrored, so the image is mapped right
    // to left to read the right way round.
    final uvs = [Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)];
    void plate(List<Vector3> corners, Vector3 normal) {
      final base = mesh.vertexCount;
      for (var k = 0; k < 4; k++) {
        mesh.vertex(corners[k], normal, uv: uvs[k]);
      }
      mesh.quadFacing(base, base + 1, base + 2, base + 3, normal);
    }

    // On the nose's flat top between the sections at z 2.05 and 1.35, a
    // centimetre proud of it; the number's top points at the cockpit.
    double noseTop(double z) => 0.40 + (2.05 - z) / 0.70 * 0.15 + 0.012;
    const back = 1.70, front = 1.81, half = 0.085;
    final slope = Vector3(0, 0.15, -0.70)..normalize();
    final up = Vector3(0, 1, 0)..sub(slope * slope.y);
    plate([
      Vector3(-half, noseTop(back), back),
      Vector3(half, noseTop(back), back),
      Vector3(half, noseTop(front), front),
      Vector3(-half, noseTop(front), front),
    ], up.normalized());

    // Outside each rear wing endplate, upright, reading front to back from
    // the left and back to front from the right.
    const top = 0.86, bottom = 0.58, fore = -2.14, aft = -2.58;
    for (final side in [-1.0, 1.0]) {
      final x = side * (_endplateX + _endplateThickness / 2 + 0.006);
      final (start, end) = side > 0 ? (fore, aft) : (aft, fore);
      plate([
        Vector3(x, top, start),
        Vector3(x, top, end),
        Vector3(x, bottom, end),
        Vector3(x, bottom, start),
      ], Vector3(side, 0, 0));
    }
    return mesh.build();
  }
}

/// Builds one part of the car as a closed solid.
///
/// Unlike [MeshBuilder], it winds each triangle to face away from a point
/// inside the part, and derives the vertex normals itself, area-weighted:
/// smooth where faces share vertices, flat where they have their own.
class _PartBuilder {
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
  /// `(z, center height, width, height)`, capped at the ends asked for.
  ///
  /// With [below], each section is cut across its sides at [split] (a
  /// fraction of its half-height above its center) and the faces under the
  /// cut go to [below]: two paints meeting along a clean line.
  void loft(
    List<(double, double, double, double)> sections, {
    _PartBuilder? below,
    double split = 0,
    bool capFront = true,
    bool capBack = true,
  }) {
    final rings = <List<Vector3>>[];
    final centers = <Vector3>[];
    // Each outline point's height relative to its section's center, as a
    // fraction of the half-height: the same for every section.
    late List<double> heights;
    for (final (z, y, w, h) in sections) {
      final c = math.min(w, h) * 0.32;
      final hw = w / 2, hh = h / 2;
      final side = 1 - c / hh;
      final outline = [
        (hw - c, 1.0),
        (hw, side),
        if (below != null) (hw, split),
        (hw, -side),
        (hw - c, -1.0),
        (-hw + c, -1.0),
        (-hw, -side),
        if (below != null) (-hw, split),
        (-hw, side),
        (-hw + c, 1.0),
      ];
      heights = [for (final (_, f) in outline) f];
      rings.add([for (final (x, f) in outline) Vector3(x, y + f * hh, z)]);
      centers.add(Vector3(0, y, z));
    }
    // Faces between outline points j and j + 1 go where their middle is.
    final n = heights.length;
    _PartBuilder target(int j) =>
        below != null && heights[j] + heights[(j + 1) % n] < 2 * split
        ? below
        : this;
    // Vertices are shared within each part (smooth shading) but not across
    // the cut (a crisp line between the paints).
    final ids = <_PartBuilder, Map<int, int>>{};
    int vertex(_PartBuilder part, int ring, int j) =>
        ids.putIfAbsent(part, () => {})[ring * n + j] ??= part._vertex(
          rings[ring][j],
        );
    for (var k = 0; k + 1 < rings.length; k++) {
      final interior = (centers[k] + centers[k + 1]) / 2;
      for (var j = 0; j < n; j++) {
        final j1 = (j + 1) % n, part = target(j);
        part._quad(
          vertex(part, k, j),
          vertex(part, k, j1),
          vertex(part, k + 1, j1),
          vertex(part, k + 1, j),
          interior,
        );
      }
    }
    // Fan caps, oriented away from the neighbouring section.
    for (final (ring, inside) in [
      if (capFront) (0, centers[1]),
      if (capBack) (rings.length - 1, centers[centers.length - 2]),
    ]) {
      final hubs = <_PartBuilder, int>{};
      for (var j = 0; j < n; j++) {
        final part = target(j);
        final hub = hubs[part] ??= part._vertex(centers[ring]);
        part._triangle(
          hub,
          vertex(part, ring, j),
          vertex(part, ring, (j + 1) % n),
          inside,
        );
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
    // Vertex k of ring r, from the top pole down.
    int at(int r, int k) {
      final phi = math.pi * r / rings, theta = 2 * math.pi * k / segments;
      final direction = Vector3(
        math.sin(phi) * math.cos(theta),
        math.cos(phi),
        math.sin(phi) * math.sin(theta),
      );
      return _vertex(center + direction * radius);
    }

    final grid = [
      for (var r = 0; r <= rings; r++)
        [for (var k = 0; k < segments; k++) at(r, k)],
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
