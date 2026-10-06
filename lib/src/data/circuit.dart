import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../geometry/centerline.dart';
import '../geometry/geo.dart';

/// One entry of `assets/circuits/index.json`.
class CircuitSummary {
  const CircuitSummary({
    required this.id,
    required this.name,
    required this.shortName,
    required this.country,
    required this.hasWidthProfile,
  });

  factory CircuitSummary.fromJson(Map<String, dynamic> json) => CircuitSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    shortName: json['shortName'] as String,
    country: json['country'] as String,
    hasWidthProfile: json['hasWidth'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String shortName;
  final String country;
  final bool hasWidthProfile;
}

/// A timing sector, as a lap-distance range from the start/finish line.
class Sector {
  const Sector(this.number, this.fromDistance, this.toDistance);

  final int number;
  final double fromDistance;
  final double toDistance;
}

/// A circuit layout in scene space, ready for mesh building.
///
/// Everything along the track is addressed by arc fraction `s` of the
/// [centerline] (see [Centerline]). Lap distance, which is what timing data
/// uses, maps onto `s` through [sAtLapDistance].
class Circuit {
  Circuit._({
    required this.summary,
    required this.projection,
    required this.centerline,
    required this.lapLength,
    required this.startFinishS,
    required this.directionSign,
    required this.sectors,
    required this._widthSamples,
    required this.elevationRange,
  });

  /// Builds a circuit from the vendored JSON documents of one circuit folder.
  ///
  /// [elevationScale] multiplies heights relative to the mean elevation, so
  /// gentle circuits can be exaggerated for a diorama look.
  factory Circuit.fromJson({
    required CircuitSummary summary,
    required Map<String, dynamic> layout,
    required Map<String, dynamic> elevation,
    required Map<String, dynamic> markers,
    Map<String, dynamic>? width,
    double elevationScale = 1.0,
  }) {
    final feature = (layout['features'] as List).first as Map<String, dynamic>;
    final lonLat = [
      for (final c in (feature['geometry']['coordinates'] as List).cast<List>())
        ((c[0] as num).toDouble(), (c[1] as num).toDouble()),
    ];
    final heights = [
      for (final e in elevation['elevations'] as List) (e as num).toDouble(),
    ];
    if (heights.length != lonLat.length) {
      throw FormatException(
        '${summary.id}: ${heights.length} elevations for ${lonLat.length} points',
      );
    }

    // The GeoJSON ring repeats its first point at the end; the spline closes
    // itself, so drop the duplicate.
    final count = lonLat.first == lonLat.last
        ? lonLat.length - 1
        : lonLat.length;

    final projection = LocalProjection.centeredOn(lonLat.take(count));
    final mean = heights.take(count).reduce((a, b) => a + b) / count;
    final points = [
      for (var i = 0; i < count; i++)
        projection.project(
          lonLat[i].$1,
          lonLat[i].$2,
          (heights[i] - mean) * elevationScale,
        ),
    ];
    final ys = points.map((p) => p.y);

    final sectors = [
      for (final s in markers['sectors'] as List)
        Sector(
          (s['id'] as num).toInt(),
          (s['fromDistance'] as num).toDouble(),
          (s['toDistance'] as num).toDouble(),
        ),
    ];

    return Circuit._(
      summary: summary,
      projection: projection,
      centerline: Centerline(points),
      lapLength: (markers['lapLengthMeters'] as num).toDouble(),
      startFinishS: (markers['startFinish']['s'] as num).toDouble(),
      directionSign: (markers['directionSign'] as num).toInt() >= 0 ? 1 : -1,
      sectors: sectors,
      widthSamples: width == null
          ? null
          : [for (final w in width['samples'] as List) (w as num).toDouble()],
      elevationRange: (ys.reduce(math.min), ys.reduce(math.max)),
    );
  }

  /// Full track width where no measured profile exists. The FIA minimum for
  /// new permanent circuits is 12 m.
  static const double defaultWidth = 12.0;

  final CircuitSummary summary;
  final LocalProjection projection;
  final Centerline centerline;

  /// Official lap length in meters.
  final double lapLength;

  /// Arc fraction of the start/finish line.
  final double startFinishS;

  /// +1 when racing runs toward increasing `s`, -1 otherwise.
  final int directionSign;

  final List<Sector> sectors;
  final List<double>? _widthSamples;

  /// Lowest and highest centerline heights in scene meters.
  final (double, double) elevationRange;

  bool get hasMeasuredWidth => _widthSamples != null;

  /// Full track width in meters at arc fraction [s].
  double widthAt(double s) {
    final samples = _widthSamples;
    if (samples == null) return defaultWidth;
    final n = samples.length;
    final pos = _wrap01(s) * n;
    final i0 = pos.floor() % n;
    final f = pos - pos.floorToDouble();
    return samples[i0] + (samples[(i0 + 1) % n] - samples[i0]) * f;
  }

  /// Arc fraction at [meters] of lap distance from the start/finish line.
  double sAtLapDistance(double meters) =>
      _wrap01(startFinishS + directionSign * meters / lapLength);

  /// Lap distance in meters from the start/finish line at arc fraction [s].
  double lapDistanceAt(double s) =>
      _wrap01(directionSign * (s - startFinishS)) * lapLength;

  /// The sector containing arc fraction [s].
  Sector sectorAt(double s) {
    final d = lapDistanceAt(s);
    return sectors.firstWhere(
      (sector) => d >= sector.fromDistance && d < sector.toDistance,
      orElse: () => sectors.last,
    );
  }

  /// Axis-aligned bounds of the centerline in scene space.
  Aabb3 get bounds {
    final points = centerline.sample(512);
    final box = Aabb3.minMax(points.first.clone(), points.first.clone());
    for (final p in points) {
      box.hullPoint(p);
    }
    return box;
  }

  static double _wrap01(double v) => v - v.floorToDouble();
}
