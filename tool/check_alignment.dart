// Fits OpenF1's circuit frame onto every vendored layout raced in a season
// and reports how well each lines up.
//
//   dart run tool/check_alignment.dart [year]
//
// A large error means the vendored layout differs from the circuit raced
// that year (a reprofiled corner, a new chicane).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:f1_scene/src/data/circuit.dart';
import 'package:f1_scene/src/geometry/track_alignment.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/race/race_repository.dart';
import 'package:f1_scene/src/race/venues.dart';

Map<String, dynamic> _read(String path) =>
    jsonDecode(File('assets/circuits/$path').readAsStringSync())
        as Map<String, dynamic>;

Circuit _circuit(String id) {
  final summary = [
    for (final c
        in (_read('index.json')['circuits'] as List)
            .cast<Map<String, dynamic>>())
      CircuitSummary.fromJson(c),
  ].firstWhere((s) => s.id == id);
  return Circuit.fromJson(
    summary: summary,
    layout: _read('layouts/$id.geojson'),
    elevation: _read('elevations/$id.json'),
    markers: _read('markers/$id.json'),
    width: summary.hasWidthProfile ? _read('widths/$id.json') : null,
  );
}

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? 2024 : int.parse(args.first);
  final repository = RaceRepository();
  for (final race in await repository.races(year)) {
    final id = circuitIdByOpenF1Key[race.circuitKey];
    if (id == null) {
      stdout.writeln('${race.meetingName.padRight(28)} no layout');
      continue;
    }
    final laps = (await repository.laps(race.sessionKey))
        .where((l) => l.start != null && l.duration != null && !l.isPitOutLap)
        .where((l) => l.lapNumber > 2)
        .toList();
    final durations = laps.map((l) => l.duration!).toList()..sort();
    final median = durations[durations.length ~/ 2];
    final lap = laps.firstWhere((l) => l.duration! < median * 1.05);
    final batch = await repository.locations(
      race.sessionKey,
      epoch: race.start,
      from: lap.start!,
      to: lap.start!.add(
        Duration(milliseconds: (lap.duration! * 1000).round()),
      ),
      driver: lap.driverNumber,
    );
    final s = batch.samples[lap.driverNumber]!;
    final stations = TrackStations.sample(_circuit(id));
    final result = alignToPath(
      source: [for (var i = 0; i < s.t.length; i++) (s.x[i], s.y[i])],
      target: [for (final c in stations.center) (c.x, c.z)],
    );
    final t = result.transform;
    stdout.writeln(
      '${race.meetingName.padRight(28)} $id  '
      'rms ${result.rmsError.toStringAsFixed(1).padLeft(5)} m  '
      'scale ${t.scale.toStringAsFixed(4)}  '
      'rot ${(t.rotation * 180 / math.pi).toStringAsFixed(0).padLeft(4)}°  '
      '${t.mirrored ? 'mirrored' : ''}',
    );
  }
  exit(0);
}
