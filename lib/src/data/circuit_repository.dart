import 'dart:convert';

import 'package:flutter/services.dart';

import 'circuit.dart';

/// Loads vendored circuit data from `assets/circuits/`.
class CircuitRepository {
  CircuitRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const _root = 'assets/circuits';

  final AssetBundle _bundle;

  Future<List<CircuitSummary>> loadIndex() async {
    final index = await _json('$_root/index.json');
    return [
      for (final c in (index['circuits'] as List).cast<Map<String, dynamic>>())
        CircuitSummary.fromJson(c),
    ];
  }

  Future<Circuit> load(
    CircuitSummary summary, {
    double elevationScale = 1.0,
  }) async {
    final id = summary.id;
    final results = await Future.wait([
      _json('$_root/layouts/$id.geojson'),
      _json('$_root/elevations/$id.json'),
      _json('$_root/markers/$id.json'),
      if (summary.hasWidthProfile) _json('$_root/widths/$id.json'),
    ]);
    return Circuit.fromJson(
      summary: summary,
      layout: results[0],
      elevation: results[1],
      markers: results[2],
      width: summary.hasWidthProfile ? results[3] : null,
      elevationScale: elevationScale,
    );
  }

  Future<Map<String, dynamic>> _json(String path) async =>
      jsonDecode(await _bundle.loadString(path)) as Map<String, dynamic>;
}
