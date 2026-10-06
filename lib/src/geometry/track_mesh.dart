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
  MeshArrays startFinishLine({double length = 4.0, int columns = 8}) {
    const rows = 2;
    final s = circuit.startFinishS;
    final center = circuit.centerline.pointAt(s);
    final forward = circuit.centerline.tangentAt(s);
    final left = Vector3(forward.z, 0, -forward.x)..normalize();
    final normal = forward.cross(left)..normalize();
    final halfWidth = circuit.widthAt(s) / 2;
    final cellWidth = halfWidth * 2 / columns;
    final cellLength = length / rows;

    final cells = rows * columns;
    final positions = Float32List(cells * 4 * 3);
    final normals = Float32List(cells * 4 * 3);
    final colors = Float32List(cells * 4 * 4);
    final indices = Uint32List(cells * 6);
    final white = linearColor(0xF5F5F5), black = linearColor(0x111111);

    var cell = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final along0 = -length / 2 + r * cellLength;
        final across0 = halfWidth - c * cellWidth;
        Vector3 corner(double along, double across) =>
            center + forward * along + left * across;
        final v = cell * 4;
        _put3(positions, v, corner(along0, across0));
        _put3(positions, v + 1, corner(along0, across0 - cellWidth));
        _put3(positions, v + 2, corner(along0 + cellLength, across0));
        _put3(
          positions,
          v + 3,
          corner(along0 + cellLength, across0 - cellWidth),
        );
        final color = (r + c).isEven ? white : black;
        for (var k = 0; k < 4; k++) {
          _put3(normals, v + k, normal);
          _put4(colors, v + k, color);
        }
        // Same corner order as the surface strip: left, right, next-left,
        // next-right, so the same winding faces up.
        indices.setAll(cell * 6, [v, v + 1, v + 2, v + 1, v + 3, v + 2]);
        cell++;
      }
    }
    return MeshArrays(
      positions: positions,
      normals: normals,
      colors: colors,
      indices: indices,
    );
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
