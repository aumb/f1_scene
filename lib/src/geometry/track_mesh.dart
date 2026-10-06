import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../data/circuit.dart';
import 'mesh_arrays.dart';

/// The level direction to the left of [forward].
///
/// That is forward × up: flutter_scene's world is left-handed (+X lies to
/// the right of +Z seen from above), so it is the reverse of the up ×
/// forward a right-handed engine would use.
Vector3 leftOf(Vector3 forward) =>
    Vector3(-forward.z, 0, forward.x)..normalize();

/// The angle, radians, from level direction [a] round to [b]: positive
/// when [b] lies to the left of [a].
double leftTurn(Vector3 a, Vector3 b) => math.atan2(b.cross(a).y, a.dot(b));

/// Cross-sections sampled evenly along a path (a circuit loop, or the open
/// pit lane), shared by every mesh and lookup that follows it.
class TrackStations {
  TrackStations._(
    this.center,
    this.forward,
    this.left,
    this.halfWidth,
    this.leftOffset,
    this.rightOffset,
    this.closed,
    this.spacing,
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
    );
  }

  /// Cross-sections through evenly spaced [center] points.
  factory TrackStations.fromPath(
    List<Vector3> center,
    List<double> halfWidth, {
    required bool closed,
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
      // Kept level: the surface has no banking, which matches the data.
      left.add(leftOf(t));
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
      final turn = leftTurn(a, b);
      if (turn.abs() < 1e-9) continue;
      // Two spans between the neighbours, one at the ends of an open path.
      final spans = closed ? 2 : at(i + 1) - at(i - 1);
      final radius = spans * step / turn.abs();
      // The inside of a left-hander is the left.
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
      center,
      forward,
      left,
      halfWidth,
      offsets(leftLimit),
      offsets(rightLimit),
      closed,
      step,
    );
  }

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

  /// Average distance between neighbouring stations, meters.
  final double spacing;

  int get length => center.length;

  /// Number of spans between stations.
  int get segmentCount => closed ? length : length - 1;

  /// The surface normal at station [i]: up, tilted with the slope.
  Vector3 up(int i) => left[i].cross(forward[i])..normalize();

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

/// A flat ribbon across [stations] between their edges, in one linear RGBA
/// [color].
MeshArrays ribbonSurface(TrackStations stations, Vector4 color) {
  final mesh = MeshBuilder();
  for (var i = 0; i < stations.length; i++) {
    final up = stations.up(i);
    mesh
      ..vertex(stations.leftEdge(i), up, color: color)
      ..vertex(stations.rightEdge(i), up, color: color);
  }
  for (var i = 0; i < stations.segmentCount; i++) {
    final l0 = i * 2, r0 = l0 + 1;
    final l1 = ((i + 1) % stations.length) * 2, r1 = l1 + 1;
    mesh.quadFacing(l0, r0, r1, l1, stations.up(i));
  }
  return mesh.build();
}

/// Vertical skirts from both edges of [stations] down to [baseY], so a
/// ribbon reads as a solid extrusion sitting on the diorama base.
MeshArrays ribbonSkirts(TrackStations stations, double baseY) {
  final mesh = MeshBuilder();
  // Per station: the left edge's top and bottom, then the right's.
  for (var i = 0; i < stations.length; i++) {
    final left = stations.left[i];
    final l = stations.leftEdge(i), r = stations.rightEdge(i);
    mesh
      ..vertex(l, left)
      ..vertex(Vector3(l.x, baseY, l.z), left)
      ..vertex(r, -left)
      ..vertex(Vector3(r.x, baseY, r.z), -left);
  }
  for (var i = 0; i < stations.segmentCount; i++) {
    final a = i * 4, b = ((i + 1) % stations.length) * 4;
    final left = stations.left[i];
    mesh
      ..quadFacing(a, a + 1, b + 1, b, left)
      ..quadFacing(a + 2, a + 3, b + 3, b + 2, -left);
  }
  return mesh.build();
}

/// Builds the meshes that make up a circuit diorama.
class TrackMeshBuilder {
  TrackMeshBuilder(this.circuit, this.stations);

  final Circuit circuit;
  final TrackStations stations;

  /// The driving surface's one colour: light, so the circuit stands out
  /// against the scenery and the cars on it, a shade under white so white
  /// cars still show.
  static const surfaceColor = 0xC8CDD5;

  /// The driving surface across the full track width.
  MeshArrays surface() => ribbonSurface(stations, linearColor(surfaceColor));

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
    final quads = MeshBuilder();
    for (final start in circuit.sectorStarts.skip(1)) {
      _crossLine(
        circuit.sAtLapDistance(start),
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
    final step = stations.spacing;
    int at(int i) => (i % n + n) % n;
    int stationsIn(double meters) => math.max(1, (meters / step).round());

    // Signed curvature (positive turns left): the turn between directions
    // 4 m either side, averaged over ~14 m.
    final reach = stationsIn(4), blur = stationsIn(6);
    final raw = [
      for (var i = 0; i < n; i++)
        leftTurn(stations.left[at(i - reach)], stations.left[at(i + reach)]) /
            (2 * reach * step),
    ];
    final curvature = [
      for (var i = 0; i < n; i++)
        [for (var k = -blur; k <= blur; k++) raw[at(i + k)]]
                .reduce((x, y) => x + y) /
            (2 * blur + 1),
    ];

    // Corners shorter than this get no kerbs. Kerbs start and end a little
    // either side of their corner, and an exit kerb runs on past it.
    final minCorner = stationsIn(8);
    final lead = stationsIn(4), runout = stationsIn(16);

    // Start scanning on a straight so no corner straddles index 0.
    var origin = 0;
    while (origin < n && curvature[origin].abs() > 1 / cornerRadius) {
      origin++;
    }
    final quads = MeshBuilder();
    final red = linearColor(0xD7262E), white = linearColor(0xEDEDED);
    void kerb(int from, int to, double side) {
      for (var k = from; k < to; k++) {
        final i = at(k), j = at(k + 1);
        Vector3 edge(int s) =>
            side > 0 ? stations.leftEdge(s) : stations.rightEdge(s);
        double offset(int s) =>
            side > 0 ? stations.leftOffset[s] : stations.rightOffset[s];
        // Narrow tracks get narrower kerbs, so some asphalt shows.
        Vector3 inner(int s) =>
            edge(s) -
            stations.left[s] * (side * math.min(width, offset(s) * 0.4));
        quads.flatQuad(
          edge(i),
          inner(i),
          inner(j),
          edge(j),
          stations.up(i),
          color: k.isEven ? red : white,
        );
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
      if (end - k >= minCorner) {
        // Inside of the corner.
        kerb(k - lead, end + lead, sign);
        if (curvature[at(apex)].abs() > 1 / exitRadius) {
          // Outside of the exit, from the apex out.
          kerb(apex, end + runout, -sign);
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
    final quads = MeshBuilder();
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
        quads.flatQuad(
          side(i, 1),
          side(i, -1),
          side(j, -1),
          side(j, 1),
          stations.up(i),
          color: color,
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
    MeshBuilder? into,
  }) {
    final quads = into ?? MeshBuilder();
    final center = circuit.centerline.pointAt(s);
    final forward = circuit.centerline.tangentAt(s);
    final left = leftOf(forward);
    final normal = left.cross(forward)..normalize();
    final halfWidth = circuit.widthAt(s) / 2;
    final cellWidth = halfWidth * 2 / columns;
    final cellLength = length / rows;
    Vector3 corner(double along, double across) =>
        center + forward * along + left * across;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final along0 = -length / 2 + r * cellLength;
        final across0 = halfWidth - c * cellWidth;
        quads.flatQuad(
          corner(along0, across0),
          corner(along0, across0 - cellWidth),
          corner(along0 + cellLength, across0 - cellWidth),
          corner(along0 + cellLength, across0),
          normal,
          color: colorAt(r, c),
        );
      }
    }
    return quads.build();
  }
}
