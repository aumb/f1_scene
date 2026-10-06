import 'dart:convert';
import 'dart:io';

import 'package:f1_scene/src/data/circuit.dart';

Map<String, dynamic> _read(String path) =>
    jsonDecode(File('assets/circuits/$path').readAsStringSync())
        as Map<String, dynamic>;

List<CircuitSummary> loadSummaries() => [
  for (final c
      in (_read('index.json')['circuits'] as List).cast<Map<String, dynamic>>())
    CircuitSummary.fromJson(c),
];

/// Loads a vendored circuit straight from disk, bypassing the asset bundle.
Circuit loadCircuit(String id, {double elevationScale = 1.0}) {
  final summary = loadSummaries().firstWhere((s) => s.id == id);
  return Circuit.fromJson(
    summary: summary,
    layout: _read('layouts/$id.geojson'),
    elevation: _read('elevations/$id.json'),
    markers: _read('markers/$id.json'),
    width: summary.hasWidthProfile ? _read('widths/$id.json') : null,
    elevationScale: elevationScale,
  );
}
