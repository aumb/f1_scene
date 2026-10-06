import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../geometry/centerline.dart';
import '../geometry/geo.dart';

/// One entry of `assets/circuits/index.json`: what is known about a circuit
/// before loading it.
class CircuitSummary {
  const CircuitSummary({required this.id, required this.hasMeasuredWidth});

  factory CircuitSummary.fromJson(Map<String, dynamic> json) => CircuitSummary(
    id: json['id'] as String,
    hasMeasuredWidth: json['hasWidth'] as bool? ?? false,
  );

  /// F1TrackViewer's id, e.g. `bh-2002`: country code and opening year.
  final String id;

  /// Whether the circuit has a measured width profile (`widths/<id>.json`);
  /// without one it is [Circuit.defaultWidth] wide all round.
  final bool hasMeasuredWidth;
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
    required this.sectorStarts,
    required this._widthSamples,
    required this.lowestElevation,
    required this.meanElevation,
  });

  /// Builds a circuit from the vendored JSON documents of one circuit folder.
  /// Heights are relative to the circuit's mean elevation, in true scale.
  factory Circuit.fromJson({
    required CircuitSummary summary,
    required Map<String, dynamic> layout,
    required Map<String, dynamic> elevation,
    required Map<String, dynamic> markers,
    Map<String, dynamic>? width,
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
        projection.project(lonLat[i].$1, lonLat[i].$2, heights[i] - mean),
    ];

    return Circuit._(
      summary: summary,
      projection: projection,
      centerline: Centerline(points),
      lapLength: (markers['lapLengthMeters'] as num).toDouble(),
      startFinishS: (markers['startFinish']['s'] as num).toDouble(),
      directionSign: (markers['directionSign'] as num).toInt() >= 0 ? 1 : -1,
      sectorStarts: [
        for (final s in markers['sectors'] as List)
          (s['fromDistance'] as num).toDouble(),
      ],
      widthSamples: width == null
          ? null
          : [for (final w in width['samples'] as List) (w as num).toDouble()],
      lowestElevation: points.map((p) => p.y).reduce(math.min),
      meanElevation: mean,
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

  /// Where each timing sector starts, in meters of lap distance from the
  /// start/finish line (the first at 0).
  final List<double> sectorStarts;

  final List<double>? _widthSamples;

  /// Lowest centerline height in scene meters.
  final double lowestElevation;

  /// Mean centerline elevation above sea level; scene height 0.
  final double meanElevation;

  /// Full track width in meters at arc fraction [s].
  double widthAt(double s) {
    final samples = _widthSamples;
    if (samples == null) return defaultWidth;
    final n = samples.length;
    final pos = wrap01(s) * n;
    final i0 = pos.floor() % n;
    final f = pos - pos.floorToDouble();
    return samples[i0] + (samples[(i0 + 1) % n] - samples[i0]) * f;
  }

  /// Arc fraction at [meters] of lap distance from the start/finish line.
  double sAtLapDistance(double meters) =>
      wrap01(startFinishS + directionSign * meters / lapLength);

  /// Axis-aligned bounds of the centerline in scene space.
  Aabb3 get bounds {
    final points = centerline.sample(512);
    final box = Aabb3.minMax(points.first.clone(), points.first.clone());
    for (final p in points) {
      box.hullPoint(p);
    }
    return box;
  }
}
