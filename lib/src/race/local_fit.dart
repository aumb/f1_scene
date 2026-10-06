/// Weighted least-squares fits through nearby samples: the smoothing both
/// the stamp jitter correction and the car motion rest on.
library;

/// The tricube kernel: 1 at [u] = 0, falling smoothly to 0 at |u| = 1. As a
/// window slides along a series, each sample's weight fades in and out
/// rather than switching, so whatever is fitted moves continuously.
double tricube(double u) {
  final a = u.abs();
  if (a >= 1) return 0;
  final b = 1 - a * a * a;
  return b * b * b;
}

/// A weighted least-squares polynomial through (u, y) points, evaluated at
/// u = 0: its level and slope there. Centre u on the point of interest.
///
/// Accumulates the sums the normal equations need, so points cost a few
/// multiplications each and nothing is stored. [clear] reuses it.
class LocalFit {
  int _count = 0;
  double _s0 = 0, _s1 = 0, _s2 = 0, _s3 = 0, _s4 = 0;
  double _t0 = 0, _t1 = 0, _t2 = 0;

  void clear() {
    _count = 0;
    _s0 = _s1 = _s2 = _s3 = _s4 = 0;
    _t0 = _t1 = _t2 = 0;
  }

  /// Adds the point ([u], [y]) with weight [w].
  void add(double u, double y, double w) {
    final u2 = u * u;
    _count++;
    _s0 += w;
    _s1 += w * u;
    _s2 += w * u2;
    _s3 += w * u2 * u;
    _s4 += w * u2 * u2;
    _t0 += w * y;
    _t1 += w * u * y;
    _t2 += w * u2 * y;
  }

  /// A straight line's level and slope, or null when the points can't
  /// define one (fewer than two, or all at the same u).
  (double, double)? lineOrNull() {
    final det = _s0 * _s2 - _s1 * _s1;
    if (_count < 2 || det.abs() < 1e-12) return null;
    final slope = (_s0 * _t1 - _s1 * _t0) / det;
    return ((_t0 - slope * _s1) / _s0, slope);
  }

  /// A straight line, or the weighted mean with no slope when the points
  /// can't define one.
  (double, double) linear() => lineOrNull() ?? (_t0 / _s0, 0);

  /// A parabola, which follows braking and acceleration without the lag a
  /// line would add. It wants four points (one more than it has terms, so
  /// it still averages rather than passing through each); fewer get a line.
  (double, double) quadratic() {
    if (_count < 4) return linear();
    // Cramer's rule on the 3x3 normal equations.
    double det3(
      double a,
      double b,
      double c,
      double d,
      double e,
      double f,
      double g,
      double h,
      double i,
    ) => a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    final det = det3(_s0, _s1, _s2, _s1, _s2, _s3, _s2, _s3, _s4);
    if (det.abs() < 1e-12) return linear();
    final level = det3(_t0, _s1, _s2, _t1, _s2, _s3, _t2, _s3, _s4) / det;
    final slope = det3(_s0, _t0, _s2, _s1, _t1, _s3, _s2, _t2, _s4) / det;
    return (level, slope);
  }
}
