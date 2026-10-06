import '../geometry/track_alignment.dart';
import '../geometry/track_mesh.dart';
import 'race_models.dart';
import 'race_repository.dart';

/// A representative lap to align with: early in the race, not out of the
/// pits, and near the median lap time (no safety car or incident).
RaceLap referenceLap(List<RaceLap> laps) {
  final timed = [
    for (final l in laps)
      if (l.start != null &&
          l.duration != null &&
          !l.isPitOutLap &&
          l.lapNumber > 2)
        l,
  ];
  if (timed.isEmpty) throw StateError('No timed laps to align with');
  final durations = [for (final l in timed) l.duration!]..sort();
  final median = durations[durations.length ~/ 2];
  return timed.firstWhere(
    (l) => l.duration! < median * 1.05,
    orElse: () => timed.first,
  );
}

/// Fits OpenF1's circuit frame onto the circuit sampled as [stations], from
/// the positions [lap]'s driver logged through it.
///
/// OpenF1 reports positions in its own frame (decimetres, rotated, mirrored
/// relative to a map); this finds the similarity transform onto the scene.
Future<AlignmentResult> alignToLap({
  required RaceRepository repository,
  required RaceSession session,
  required RaceLap lap,
  required TrackStations stations,
}) async {
  final batch = await repository.locations(
    session.sessionKey,
    epoch: session.start,
    from: lap.start!,
    // A little past the lap, so its end overlaps its start.
    to: lap.start!.add(
      Duration(milliseconds: (lap.duration! * 1000).round() + 500),
    ),
    driver: lap.driverNumber,
  );
  final samples = batch.samples[lap.driverNumber];
  if (samples == null || samples.t.length < _minSamples) {
    throw StateError('Not enough position data to align the circuit');
  }
  return alignToPath(
    source: [
      for (var i = 0; i < samples.t.length; i++) (samples.x[i], samples.y[i]),
    ],
    target: [for (final c in stations.center) (c.x, c.z)],
  );
}

/// Positions a lap must have for the fit to be trusted (~13 s at 3.85 Hz).
const _minSamples = 50;
