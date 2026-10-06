import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../data/circuit.dart';

/// Raw triangle-list mesh arrays, independent of any renderer.
class MeshArrays {
  MeshArrays({
    required this.positions,
    required this.normals,
    required this.indices,
    this.colors,
  });

  final Float32List positions;
  final Float32List normals;
  final Float32List? colors;
  final Uint32List indices;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}

/// How the driving surface is tinted.
enum TrackColorMode { sectors, elevation, asphalt }

/// Linear-space RGBA from an sRGB `0xRRGGBB` value.
Vector4 linearColor(int rgb, [double alpha = 1]) {
  double channel(int shift) {
    final c = ((rgb >> shift) & 0xff) / 255;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return Vector4(channel(16), channel(8), channel(0), alpha);
}

/// Cross-sections sampled evenly along a path (a circuit loop, or the open
/// pit lane), shared by every mesh and lookup that follows it.
class TrackStations {
  TrackStations._(
    this.s,
    this.center,
    this.forward,
    this.left,
    this.halfWidth,
    this.leftOffset,
    this.rightOffset,
    this.closed,
  );

  /// Samples [circuit] about every [spacing] meters.
  factory TrackStations.sample(Circuit circuit, {double spacing = 2.0}) {
    final line = circuit.centerline;
    final count = math.max(64, (line.length / spacing).ceil());
    final s = List.generate(count, (i) => i / count);
    return TrackStations.fromPath(
      [for (final v in s) line.pointAt(v)],
      [for (final v in s) circuit.widthAt(v) / 2],
      closed: true,
      s: s,
    );
  }

  /// Cross-sections through evenly spaced [center] points. [s] defaults to
  /// each station's fraction of the path.
  factory TrackStations.fromPath(
    List<Vector3> center,
    List<double> halfWidth, {
    required bool closed,
    List<double>? s,
  }) {
    final count = center.length;
    int at(int i) => closed ? (i + count) % count : i.clamp(0, count - 1);
    final forward = <Vector3>[];
    final left = <Vector3>[];
    for (var i = 0; i < count; i++) {
      // Central difference over neighbouring stations: smooth, and exact
      // enough at 2 m spacing.
      final t = (center[at(i + 1)] - center[at(i - 1)])..normalize();
      forward.add(t);
      // Horizontal left of travel: up x forward. Keeping it level means the
      // surface has no banking, which matches the source data.
      left.add(Vector3(t.z, 0, -t.x)..normalize());
    }
    final step = _pathLength(center, closed) / (closed ? count : count - 1);

    // The source centerlines are coarse, so the spline over-tightens some
    // hairpins (Bahrain T1 comes out at a 6.5 m radius against a 9 m half
    // width). An edge offset beyond the local radius folds back on itself,
    // so cap the inner side of each corner just inside that radius.
    final leftLimit = List.filled(count, double.infinity);
    final rightLimit = List.filled(count, double.infinity);
    for (var i = 0; i < count; i++) {
      final a = left[at(i - 1)], b = left[at(i + 1)];
      final turn = math.atan2(a.cross(b).y, a.dot(b));
      if (turn.abs() < 1e-9) continue;
      // Two spans between the neighbours, one at the ends of an open path.
      final spans = closed ? 2 : at(i + 1) - at(i - 1);
      final radius = spans * step / turn.abs();
      // A positive turn about +Y is a left-hander, whose inside is the left.
      if (turn > 0) {
        leftLimit[i] = 0.85 * radius;
      } else {
        rightLimit[i] = 0.85 * radius;
      }
    }
    List<double> offsets(List<double> limit) {
      final pullIn = _smoothBump([
        for (var i = 0; i < count; i++) math.max(0.0, halfWidth[i] - limit[i]),
      ], at);
      return [for (var i = 0; i < count; i++) halfWidth[i] - pullIn[i]];
    }

    return TrackStations._(
      s ?? [for (var i = 0; i < count; i++) i / (closed ? count : count - 1)],
      center,
      forward,
      left,
      halfWidth,
      offsets(leftLimit),
      offsets(rightLimit),
      closed,
    );
  }

  final List<double> s;
  final List<Vector3> center;
  final List<Vector3> forward;
  final List<Vector3> left;

  /// Half of the measured track width at each station.
  final List<double> halfWidth;

  /// Distance from the centerline to each edge, [halfWidth] with the inside
  /// of over-tight corners pulled in.
  final List<double> leftOffset;
  final List<double> rightOffset;

  /// Whether the last station connects back to the first.
  final bool closed;

  int get length => s.length;

  /// Number of spans between stations.
  int get segmentCount => closed ? length : length - 1;

  Vector3 leftEdge(int i) => center[i] + left[i] * leftOffset[i];
  Vector3 rightEdge(int i) => center[i] - left[i] * rightOffset[i];

  static double _pathLength(List<Vector3> points, bool closed) {
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += points[i].distanceTo(points[i - 1]);
    }
    if (closed) length += points.last.distanceTo(points.first);
    return length;
  }

  /// Smooths a list into gentle bumps that never dip below any input value:
  /// a windowed maximum followed by a box blur of the same radius keeps
  /// every output at or above the input it replaces. Zero runs longer than
  /// the window stay exactly zero. [at] maps neighbour indices (wrapping or
  /// clamping).
  static List<double> _smoothBump(
    List<double> values,
    int Function(int) at, {
    int radius = 4,
  }) {
    final n = values.length;
    final dilated = [
      for (var i = 0; i < n; i++)
        [for (var k = -radius; k <= radius; k++) values[at(i + k)]]
            .reduce(math.max),
    ];
    return [
      for (var i = 0; i < n; i++)
        // The max only absorbs float rounding in the average.
        math.max(
          values[i],
          [for (var k = -radius; k <= radius; k++) dilated[at(i + k)]]
                  .reduce((a, b) => a + b) /
              (2 * radius + 1),
        ),
    ];
  }
}

/// A flat ribbon across [stations] between their edges, colored per station
/// by [colors] (linear RGBA, two vertices per station).
MeshArrays ribbonSurface(TrackStations stations, Float32List colors) {
  final n = stations.length;
  final positions = Float32List(n * 2 * 3);
  final normals = Float32List(n * 2 * 3);
  final indices = Uint32List(stations.segmentCount * 6);

  for (var i = 0; i < n; i++) {
    // Surface normal: forward x left, which is +Y on level ground and tilts
    // with the slope.
    final normal = stations.forward[i].cross(stations.left[i])..normalize();
    _put3(positions, i * 2, stations.leftEdge(i));
    _put3(positions, i * 2 + 1, stations.rightEdge(i));
    _put3(normals, i * 2, normal);
    _put3(normals, i * 2 + 1, normal);
  }
  for (var i = 0; i < stations.segmentCount; i++) {
    // Counter-clockwise seen from above (verified in track_mesh_test).
    final l0 = i * 2, r0 = l0 + 1;
    final l1 = ((i + 1) % n) * 2, r1 = l1 + 1;
    indices.setAll(i * 6, [l0, r0, l1, r0, r1, l1]);
  }
  return MeshArrays(
    positions: positions,
    normals: normals,
    colors: colors,
    indices: indices,
  );
}

/// Vertical skirts from both edges of [stations] down to [baseY], so a
/// ribbon reads as a solid extrusion sitting on the diorama base.
MeshArrays ribbonSkirts(TrackStations stations, double baseY) {
  final n = stations.length;
  // Per side and station: a top and a bottom vertex.
  final positions = Float32List(n * 4 * 3);
  final normals = Float32List(n * 4 * 3);
  final indices = Uint32List(stations.segmentCount * 12);

  for (var i = 0; i < n; i++) {
    final left = stations.left[i];
    final right = -left;
    final lTop = stations.leftEdge(i), rTop = stations.rightEdge(i);
    final base = i * 4;
    _put3(positions, base, lTop);
    _put3(positions, base + 1, Vector3(lTop.x, baseY, lTop.z));
    _put3(positions, base + 2, rTop);
    _put3(positions, base + 3, Vector3(rTop.x, baseY, rTop.z));
    _put3(normals, base, left);
    _put3(normals, base + 1, left);
    _put3(normals, base + 2, right);
    _put3(normals, base + 3, right);
  }
  for (var i = 0; i < stations.segmentCount; i++) {
    final base = i * 4, next = ((i + 1) % n) * 4;
    final lt0 = base, lb0 = base + 1, rt0 = base + 2, rb0 = base + 3;
    final lt1 = next, lb1 = next + 1, rt1 = next + 2, rb1 = next + 3;
    indices.setAll(i * 12, [
      // Left skirt faces +left.
      lb0, lt0, lb1, lt0, lt1, lb1,
      // Right skirt faces -left.
      rb0, rb1, rt0, rt0, rb1, rt1,
    ]);
  }
  return MeshArrays(positions: positions, normals: normals, indices: indices);
}

/// Two vertices' worth of [color] per station, for [ribbonSurface].
Float32List uniformRibbonColors(TrackStations stations, Vector4 color) {
  final colors = Float32List(stations.length * 2 * 4);
  for (var v = 0; v < stations.length * 2; v++) {
    _put4(colors, v, color);
  }
  return colors;
}

/// Collects flat coloured quads, each with its own vertices so colours stay
/// crisp. Corners come left, right, next-left, next-right (relative to the
/// direction of travel), which winds them to face up.
class _Quads {
  final _positions = <double>[];
  final _normals = <double>[];
  final _colors = <double>[];
  final _indices = <int>[];

  void add(
    Vector3 left,
    Vector3 right,
    Vector3 nextLeft,
    Vector3 nextRight,
    Vector3 normal,
    Vector4 color,
  ) {
    final v = _positions.length ~/ 3;
    for (final p in [left, right, nextLeft, nextRight]) {
      _positions.addAll([p.x, p.y, p.z]);
      _normals.addAll([normal.x, normal.y, normal.z]);
      _colors.addAll([color.x, color.y, color.z, color.w]);
    }
    _indices.addAll([v, v + 1, v + 2, v + 1, v + 3, v + 2]);
  }

  MeshArrays build() => MeshArrays(
    positions: Float32List.fromList(_positions),
    normals: Float32List.fromList(_normals),
    colors: Float32List.fromList(_colors),
    indices: Uint32List.fromList(_indices),
  );
}

void _put3(Float32List list, int vertex, Vector3 v) {
  list[vertex * 3] = v.x;
  list[vertex * 3 + 1] = v.y;
  list[vertex * 3 + 2] = v.z;
}

void _put4(Float32List list, int vertex, Vector4 v) {
  list[vertex * 4] = v.x;
  list[vertex * 4 + 1] = v.y;
  list[vertex * 4 + 2] = v.z;
  list[vertex * 4 + 3] = v.w;
}

/// Builds the meshes that make up a circuit diorama.
class TrackMeshBuilder {
  TrackMeshBuilder(this.circuit, this.stations);

  final Circuit circuit;
  final TrackStations stations;

  static const sectorColors = [0x00A3FF, 0xB66DFF, 0x00D084];
  static const elevationRamp = [0x2EC4B6, 0xF4D35E, 0xFF6B35];
  static const asphaltColor = 0x5A5F6B;

  /// The driving surface across the full track width, tinted per [mode].
  MeshArrays surface(TrackColorMode mode) =>
      ribbonSurface(stations, surfaceColors(mode));

  /// Vertex colors for [surface], so a tint change can update colors alone.
  Float32List surfaceColors(TrackColorMode mode) {
    final colors = Float32List(stations.length * 2 * 4);
    for (var i = 0; i < stations.length; i++) {
      final color = _surfaceColor(mode, i);
      _put4(colors, i * 2, color);
      _put4(colors, i * 2 + 1, color);
    }
    return colors;
  }

  /// Skirts under both track edges down to [baseY].
  MeshArrays skirts(double baseY) => ribbonSkirts(stations, baseY);

  /// A checkered start/finish strip across the track, [length] meters long,
  /// lying on the surface.
  MeshArrays startFinishLine({double length = 4.0, int columns = 8}) =>
      _crossLine(
        circuit.startFinishS,
        length: length,
        rows: 2,
        columns: columns,
        colorAt: (r, c) =>
            (r + c).isEven ? linearColor(0xF5F5F5) : linearColor(0x111111),
      );

  /// Thin lines across the track where each sector after the first starts.
  MeshArrays sectorLines() {
    final quads = _Quads();
    for (final sector in circuit.sectors.skip(1)) {
      _crossLine(
        circuit.sAtLapDistance(sector.fromDistance),
        length: 1.0,
        rows: 1,
        columns: 1,
        colorAt: (_, _) => linearColor(0xFFD400),
        into: quads,
      );
    }
    return quads.build();
  }

  /// Red and white kerbs, derived from curvature: on the inside of every
  /// corner tighter than [cornerRadius], and on the outside of the exit of
  /// corners tighter than [exitRadius]. They lie on the surface along its
  /// edges, [width] meters wide.
  MeshArrays kerbs({
    double width = 1.4,
    double cornerRadius = 140,
    double exitRadius = 70,
  }) {
    final n = stations.length;
    final step = circuit.centerline.length / n;
    int at(int i) => (i % n + n) % n;

    // Signed curvature (positive turns left), smoothed over ~14 m.
    final raw = [
      for (var i = 0; i < n; i++)
        () {
          final a = stations.left[at(i - 2)], b = stations.left[at(i + 2)];
          return math.atan2(a.cross(b).y, a.dot(b)) / (4 * step);
        }(),
    ];
    final curvature = [
      for (var i = 0; i < n; i++)
        [for (var k = -3; k <= 3; k++) raw[at(i + k)]].reduce((x, y) => x + y) /
            7,
    ];

    // Start scanning on a straight so no corner straddles index 0.
    var origin = 0;
    while (origin < n && curvature[origin].abs() > 1 / cornerRadius) {
      origin++;
    }
    final quads = _Quads();
    final red = linearColor(0xD7262E), white = linearColor(0xEDEDED);
    void kerb(int from, int to, double side) {
      for (var k = from; k < to; k++) {
        final i = at(k), j = at(k + 1);
        Vector3 edge(int s) =>
            side > 0 ? stations.leftEdge(s) : stations.rightEdge(s);
        double offset(int s) =>
            side > 0 ? stations.leftOffset[s] : stations.rightOffset[s];
        Vector3 inner(int s) =>
            edge(s) -
            stations.left[s] * (side * math.min(width, offset(s) * 0.4));
        final normal = stations.forward[i].cross(stations.left[i])..normalize();
        final color = k.isEven ? red : white;
        // Corners ordered left, right, next-left, next-right.
        if (side > 0) {
          quads.add(edge(i), inner(i), edge(j), inner(j), normal, color);
        } else {
          quads.add(inner(i), edge(i), inner(j), edge(j), normal, color);
        }
      }
    }

    var k = origin;
    while (k < origin + n) {
      final c = curvature[at(k)];
      if (c.abs() <= 1 / cornerRadius) {
        k++;
        continue;
      }
      final sign = c.sign;
      var end = k, apex = k;
      while (end < origin + n &&
          curvature[at(end)].sign == sign &&
          curvature[at(end)].abs() > 1 / cornerRadius) {
        if (curvature[at(end)].abs() > curvature[at(apex)].abs()) apex = end;
        end++;
      }
      if (end - k >= 4) {
        // Inside of the corner, a little either side of it.
        kerb(k - 2, end + 2, sign);
        if (curvature[at(apex)].abs() > 1 / exitRadius) {
          // Outside of the exit, from the apex out.
          kerb(apex, end + 8, -sign);
        }
      }
      k = end;
    }
    return quads.build();
  }

  /// Bands down the middle of the track over each span `(start, end)` of
  /// stations, wrapping past the seam when start > end.
  MeshArrays drsBands(List<(double, double)> spans, {double fraction = 0.35}) {
    final n = stations.length;
    final quads = _Quads();
    final color = linearColor(0x2BD96A);
    for (final (start, end) in spans) {
      final length = (end - start) % n;
      for (var k = 0; k < length.ceil(); k++) {
        final i = (start.floor() + k) % n, j = (i + 1) % n;
        Vector3 side(int s, double sign) =>
            stations.center[s] +
            stations.left[s] *
                (sign *
                    fraction *
                    (stations.leftOffset[s] + stations.rightOffset[s]) /
                    2);
        final normal = stations.forward[i].cross(stations.left[i])..normalize();
        quads.add(
          side(i, 1),
          side(i, -1),
          side(j, 1),
          side(j, -1),
          normal,
          color,
        );
      }
    }
    return quads.build();
  }

  /// A [rows] x [columns] grid across the track at [s], [length] meters long.
  MeshArrays _crossLine(
    double s, {
    required double length,
    required int rows,
    required int columns,
    required Vector4 Function(int row, int column) colorAt,
    _Quads? into,
  }) {
    final quads = into ?? _Quads();
    final center = circuit.centerline.pointAt(s);
    final forward = circuit.centerline.tangentAt(s);
    final left = Vector3(forward.z, 0, -forward.x)..normalize();
    final normal = forward.cross(left)..normalize();
    final halfWidth = circuit.widthAt(s) / 2;
    final cellWidth = halfWidth * 2 / columns;
    final cellLength = length / rows;
    Vector3 corner(double along, double across) =>
        center + forward * along + left * across;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final along0 = -length / 2 + r * cellLength;
        final across0 = halfWidth - c * cellWidth;
        quads.add(
          corner(along0, across0),
          corner(along0, across0 - cellWidth),
          corner(along0 + cellLength, across0),
          corner(along0 + cellLength, across0 - cellWidth),
          normal,
          colorAt(r, c),
        );
      }
    }
    return quads.build();
  }

  Vector4 _surfaceColor(TrackColorMode mode, int i) {
    switch (mode) {
      case TrackColorMode.sectors:
        final sector = circuit.sectorAt(stations.s[i]).number;
        return linearColor(sectorColors[(sector - 1) % sectorColors.length]);
      case TrackColorMode.elevation:
        final (lo, hi) = circuit.elevationRange;
        final t = hi > lo ? (stations.center[i].y - lo) / (hi - lo) : 0.5;
        return _ramp(elevationRamp, t);
      case TrackColorMode.asphalt:
        return linearColor(asphaltColor);
    }
  }

  static Vector4 _ramp(List<int> stops, double t) {
    final x = t.clamp(0.0, 1.0) * (stops.length - 1);
    final i = math.min(x.floor(), stops.length - 2);
    final a = linearColor(stops[i]), b = linearColor(stops[i + 1]);
    final out = Vector4.zero();
    Vector4.mix(a, b, x - i, out);
    return out;
  }
}
