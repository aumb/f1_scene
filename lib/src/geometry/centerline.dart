import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// A closed centripetal Catmull-Rom spline parameterized by arc length.
///
/// Positions along the loop are addressed by `s` in `[0, 1)`: the fraction of
/// the lap length measured from the first control point. Values outside that
/// range wrap. This is the same parameterization F1TrackViewer uses for its
/// width profiles, so those samples line up without remapping.
class Centerline {
  Centerline(List<Vector3> controlPoints)
    : assert(controlPoints.length >= 3, 'A closed loop needs 3+ points'),
      _points = List.unmodifiable(controlPoints) {
    _segments = List.generate(_points.length, _segmentAt);
    _buildArcTable();
  }

  /// Arc length table entries per segment.
  static const _samplesPerSegment = 128;

  final List<Vector3> _points;
  late final List<_Segment> _segments;

  /// Cumulative arc length at each table entry, entry `k` being parameter
  /// `k / _samplesPerSegment` in segment units.
  late final Float64List _arc;

  /// Total loop length in meters.
  double get length => _arc.last;

  /// Position at arc fraction [s].
  Vector3 pointAt(double s) {
    final u = _paramAt(wrap01(s) * length);
    final segment = u.floor().clamp(0, _segments.length - 1);
    return _segments[segment].eval(u - segment);
  }

  /// Unit tangent at arc fraction [s], pointing in the direction of
  /// increasing `s`.
  Vector3 tangentAt(double s) {
    final ds = 0.5 / length;
    return (pointAt(s + ds) - pointAt(s - ds))..normalize();
  }

  /// Arc fraction at control point [index], which the curve passes through.
  double sAtControlPoint(int index) =>
      _arc[index * _samplesPerSegment] / length;

  /// [count] points evenly spaced in arc length, point `i` at `s = i / count`.
  List<Vector3> sample(int count) =>
      List.generate(count, (i) => pointAt(i / count));

  void _buildArcTable() {
    final n = _segments.length * _samplesPerSegment;
    _arc = Float64List(n + 1);
    var previous = _segments[0].eval(0);
    for (var k = 1; k <= n; k++) {
      final segment = math.min(
        (k - 1) ~/ _samplesPerSegment,
        _segments.length - 1,
      );
      final t = k / _samplesPerSegment - segment;
      final current = _segments[segment].eval(t);
      _arc[k] = _arc[k - 1] + current.distanceTo(previous);
      previous = current;
    }
  }

  /// Inverts the arc table: segment-space parameter at arc length [target].
  double _paramAt(double target) {
    var lo = 0, hi = _arc.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_arc[mid] <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _arc[hi] - _arc[lo];
    final f = span > 0 ? (target - _arc[lo]) / span : 0.0;
    return (lo + f) / _samplesPerSegment;
  }

  _Segment _segmentAt(int i) {
    final n = _points.length;
    final p0 = _points[(i - 1 + n) % n];
    final p1 = _points[i];
    final p2 = _points[(i + 1) % n];
    final p3 = _points[(i + 2) % n];

    // Centripetal knot spacing (alpha = 0.5), with the same degenerate-span
    // fallbacks as three.js so coincident points do not blow up.
    var dt0 = math.sqrt(p0.distanceTo(p1));
    var dt1 = math.sqrt(p1.distanceTo(p2));
    var dt2 = math.sqrt(p2.distanceTo(p3));
    if (dt1 < 1e-4) dt1 = 1.0;
    if (dt0 < 1e-4) dt0 = dt1;
    if (dt2 < 1e-4) dt2 = dt1;

    Vector3 tangent(Vector3 a, Vector3 b, Vector3 c, double d0, double d1) =>
        (b - a) / d0 - (c - a) / (d0 + d1) + (c - b) / d1;

    // Both tangents rescale by the middle span, mapping p1 -> p2 onto [0, 1].
    final m1 = tangent(p0, p1, p2, dt0, dt1) * dt1;
    final m2 = tangent(p1, p2, p3, dt1, dt2) * dt1;
    return _Segment(p1, p2, m1, m2);
  }
}

/// [v] wrapped into `[0, 1)`.
double wrap01(double v) => v - v.floorToDouble();

/// Cubic Hermite segment from [p1] to [p2] with end tangents [m1], [m2].
class _Segment {
  _Segment(Vector3 p1, Vector3 p2, Vector3 m1, Vector3 m2)
    : c0 = p1.clone(),
      c1 = m1.clone(),
      c2 = p1 * -3 + p2 * 3 - m1 * 2 - m2,
      c3 = p1 * 2 - p2 * 2 + m1 + m2;

  final Vector3 c0, c1, c2, c3;

  Vector3 eval(double t) => c0 + (c1 + (c2 + c3 * t) * t) * t;
}
