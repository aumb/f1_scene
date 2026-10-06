import 'dart:convert';
import 'dart:io';

import 'circuit.dart';

// The vendored circuit data read straight from disk, for tools and tests
// run from the repository root. The app loads the same files through the
// asset bundle (CircuitRepository); this file is never imported by it, so
// dart:io stays out of the web build.

const _root = 'assets/circuits';

Map<String, dynamic> _read(String path) =>
    jsonDecode(File('$_root/$path').readAsStringSync()) as Map<String, dynamic>;

/// Every vendored circuit, as listed in `index.json`.
List<CircuitSummary> loadSummaries() => [
  for (final c
      in (_read('index.json')['circuits'] as List).cast<Map<String, dynamic>>())
    CircuitSummary.fromJson(c),
];

/// The vendored circuit [id].
Circuit loadCircuit(String id) {
  final summary = loadSummaries().firstWhere((s) => s.id == id);
  return Circuit.fromJson(
    summary: summary,
    layout: _read('layouts/$id.geojson'),
    elevation: _read('elevations/$id.json'),
    markers: _read('markers/$id.json'),
    width: summary.hasMeasuredWidth ? _read('widths/$id.json') : null,
  );
}
