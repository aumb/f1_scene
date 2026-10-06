import 'dart:math' as math;

import 'point_grid.dart';

/// `p -> scale * R(rotation) * M * p + (tx, ty)`, where `M` optionally
/// mirrors the y axis.
class SimilarityTransform2D {
  const SimilarityTransform2D({
    required this.scale,
    required this.rotation,
    required this.tx,
    required this.ty,
    this.mirrored = false,
  });

  final double scale;
  final double rotation;
  final double tx;
  final double ty;
  final bool mirrored;

  (double, double) apply(double x, double y) {
    final my = mirrored ? -y : y;
    final c = math.cos(rotation) * scale, s = math.sin(rotation) * scale;
    return (c * x - s * my + tx, s * x + c * my + ty);
  }

  @override
  String toString() =>
      'SimilarityTransform2D(scale: ${scale.toStringAsFixed(4)}, '
      'rotation: ${(rotation * 180 / math.pi).toStringAsFixed(1)}°, '
      'mirrored: $mirrored)';
}

class AlignmentResult {
  const AlignmentResult(this.transform, this.rmsError);

  final SimilarityTransform2D transform;

  /// Root-mean-square distance from the aligned source points to the target,
  /// over the best-matching 90%, in target units.
  final double rmsError;
}

/// Fits the similarity transform that lays [source] points (one lap of car
/// positions in OpenF1's circuit frame) onto the closed [target] path (the
/// circuit centerline in scene meters).
///
/// Trimmed iterative-closest-point with scale, matching each point to its
/// projection on the path's segments. Rotation and mirroring are unknown,
/// so a coarse sweep over both picks the starting point, then the best
/// candidate is refined against the full-resolution path.
AlignmentResult alignToPath({
  required List<(double, double)> source,
  required List<(double, double)> target,
}) {
  assert(source.length >= 10 && target.length >= 10);
  final fine = PointGrid(
    [for (final p in target) p.$1],
    [for (final p in target) p.$2],
  );
  final coarseTarget = [for (var i = 0; i < target.length; i += 5) target[i]];
  final coarse = PointGrid(
    [for (final p in coarseTarget) p.$1],
    [for (final p in coarseTarget) p.$2],
    cellSize: 40,
  );
  final step = math.max(1, source.length ~/ 120);
  final coarseSource = [
    for (var i = 0; i < source.length; i += step) source[i],
  ];

  final (sx, sy) = _centroid(source);
  final (tx, ty) = _centroid(target);
  final scale0 = _rmsRadius(target, tx, ty) / _rmsRadius(source, sx, sy);

  // OpenF1's frame is the scene's, give or take a few degrees (checked on
  // every venue raced 2023-2025), so try that first and only sweep every
  // orientation when it does not fit.
  final candidates = [
    (mirrored: false, degrees: 0),
    for (final mirrored in [false, true])
      for (var degrees = 0; degrees < 360; degrees += 15)
        (mirrored: mirrored, degrees: degrees),
  ];
  AlignmentResult? best;
  for (final (:mirrored, :degrees) in candidates) {
    final rotation = degrees * math.pi / 180;
    // Start with the centroids on top of each other.
    final seed = SimilarityTransform2D(
      scale: scale0,
      rotation: rotation,
      tx: 0,
      ty: 0,
      mirrored: mirrored,
    );
    final (ax, ay) = seed.apply(sx, sy);
    final start = SimilarityTransform2D(
      scale: scale0,
      rotation: rotation,
      tx: tx - ax,
      ty: ty - ay,
      mirrored: mirrored,
    );
    final result = _icp(coarseSource, coarse, start, iterations: 8);
    if (best == null || result.rmsError < best.rmsError) best = result;
    // A whole lap within a few meters of the path cannot be a wrong fit.
    if (best.rmsError < _goodFit) break;
  }
  // A full lap's extent pins the scale to a few percent. Letting it float
  // freely invites the classic collapse: shrinking the lap onto one short
  // stretch of track also scores a small error.
  return _icp(
    source,
    fine,
    best!.transform,
    iterations: 60,
    scaleRange: (scale0 * 0.9, scale0 * 1.1),
  );
}

/// Coarse-fit error, in target units, accepted without trying other
/// orientations. The coarse path is sampled every ~10 m, which alone adds
/// a few meters.
const double _goodFit = 8;

/// Refines [transform]. The scale stays fixed unless [scaleRange] allows it
/// to move.
AlignmentResult _icp(
  List<(double, double)> source,
  PointGrid target,
  SimilarityTransform2D transform, {
  required int iterations,
  (double, double)? scaleRange,
}) {
  var current = transform;
  var rms = double.infinity;
  for (var iteration = 0; iteration < iterations; iteration++) {
    // Pair each source point with its nearest target point.
    final pairs = <({double px, double py, double qx, double qy, double d2})>[];
    for (final (x, y) in source) {
      final (ax, ay) = current.apply(x, y);
      final (qx, qy, d2) = _closestOnPath(target, ax, ay);
      pairs.add((px: x, py: current.mirrored ? -y : y, qx: qx, qy: qy, d2: d2));
    }
    // Drop the worst 10%: pit entries, off-track moments, layout changes.
    pairs.sort((a, b) => a.d2.compareTo(b.d2));
    final kept = pairs.sublist(0, (pairs.length * 0.9).ceil());
    final newRms = math.sqrt(
      kept.fold(0.0, (sum, p) => sum + p.d2) / kept.length,
    );

    // Closed-form 2D similarity (Umeyama) for the kept pairs.
    var mpx = 0.0, mpy = 0.0, mqx = 0.0, mqy = 0.0;
    for (final p in kept) {
      mpx += p.px;
      mpy += p.py;
      mqx += p.qx;
      mqy += p.qy;
    }
    final n = kept.length;
    mpx /= n;
    mpy /= n;
    mqx /= n;
    mqy /= n;
    var a = 0.0, b = 0.0, norm = 0.0;
    for (final p in kept) {
      final px = p.px - mpx, py = p.py - mpy;
      final qx = p.qx - mqx, qy = p.qy - mqy;
      a += px * qx + py * qy;
      b += px * qy - py * qx;
      norm += px * px + py * py;
    }
    final rotation = math.atan2(b, a);
    final scale = scaleRange == null
        ? current.scale
        : (math.sqrt(a * a + b * b) / norm).clamp(scaleRange.$1, scaleRange.$2);
    final c = math.cos(rotation) * scale, s = math.sin(rotation) * scale;
    current = SimilarityTransform2D(
      scale: scale,
      rotation: rotation,
      tx: mqx - (c * mpx - s * mpy),
      ty: mqy - (s * mpx + c * mpy),
      mirrored: current.mirrored,
    );

    final converged = (rms - newRms).abs() < 1e-6 * math.max(1, newRms);
    rms = newRms;
    if (converged) break;
  }
  return AlignmentResult(current, rms);
}

/// The closest point to ([x], [y]) on the closed polyline through the grid's
/// points, in order, with its squared distance.
(double, double, double) _closestOnPath(PointGrid path, double x, double y) {
  final n = path.xs.length;
  final i = path.nearest(x, y).index;
  var best = (path.xs[i], path.ys[i], double.infinity);
  // The closest point lies on one of the two segments touching vertex i.
  for (final (a, b) in [((i - 1 + n) % n, i), (i, (i + 1) % n)]) {
    final ax = path.xs[a], ay = path.ys[a];
    final dx = path.xs[b] - ax, dy = path.ys[b] - ay;
    final length2 = dx * dx + dy * dy;
    final t = length2 == 0
        ? 0.0
        : (((x - ax) * dx + (y - ay) * dy) / length2).clamp(0.0, 1.0);
    final px = ax + dx * t, py = ay + dy * t;
    final d2 = (px - x) * (px - x) + (py - y) * (py - y);
    if (d2 < best.$3) best = (px, py, d2);
  }
  return best;
}

(double, double) _centroid(List<(double, double)> points) {
  var x = 0.0, y = 0.0;
  for (final p in points) {
    x += p.$1;
    y += p.$2;
  }
  return (x / points.length, y / points.length);
}

double _rmsRadius(List<(double, double)> points, double cx, double cy) {
  var sum = 0.0;
  for (final p in points) {
    final dx = p.$1 - cx, dy = p.$2 - cy;
    sum += dx * dx + dy * dy;
  }
  return math.sqrt(sum / points.length);
}
