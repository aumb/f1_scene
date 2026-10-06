// Fits OpenF1's circuit frame onto every vendored layout raced in a season,
// the way a replay does, and reports how well each lines up and whether a
// pit lane could be traced.
//
//   dart run tool/check_alignment.dart [year]     (default 2024)
//
// Run it from the repository root (it reads assets/circuits/). A large
// error means the vendored layout differs from the circuit raced that year:
// a reprofiled corner, a new chicane.
import 'dart:io';
import 'dart:math' as math;

import 'package:f1_scene/src/data/circuit_files.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';
import 'package:f1_scene/src/race/pit_lane_tracer.dart';
import 'package:f1_scene/src/race/race_repository.dart';
import 'package:f1_scene/src/race/session_alignment.dart';
import 'package:f1_scene/src/race/venues.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? 2024 : int.parse(args.first);
  final repository = RaceRepository();
  for (final race in await repository.races(year)) {
    final name = race.meetingName.padRight(28);
    final id = circuitIdByOpenF1Key[race.circuitKey];
    if (id == null) {
      stdout.writeln('$name no layout');
      continue;
    }
    final stations = TrackStations.sample(loadCircuit(id));
    final laps = await repository.laps(race.sessionKey);
    final alignment = await alignToLap(
      repository: repository,
      session: race,
      lap: referenceLap(laps),
      stations: stations,
    );
    final t = alignment.transform;
    final pit = await tracePitLane(
      repository: repository,
      session: race,
      stops: await repository.pitStops(race.sessionKey),
      transform: t,
      track: TrackProjector(stations),
    );
    final pitText = pit == null
        ? 'no pit lane'
        : 'pit lane ${(TrackProjector(pit).metersPerStation * pit.segmentCount).toStringAsFixed(0)} m';
    stdout.writeln(
      '$name $id  '
      'rms ${alignment.rmsError.toStringAsFixed(1).padLeft(5)} m  '
      'scale ${t.scale.toStringAsFixed(4)}  '
      'rot ${(t.rotation * 180 / math.pi).toStringAsFixed(0).padLeft(4)}°  '
      '${t.mirrored ? 'mirrored ' : ''}$pitText',
    );
  }
  // The HTTP client keeps the process alive; we're done.
  exit(0);
}
