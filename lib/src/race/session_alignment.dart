import '../geometry/track_alignment.dart';
import '../geometry/track_mesh.dart';
import '../geometry/track_projector.dart';
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
/// OpenF1 reports positions in its own frame: decimetres, x east and y
/// north give or take a few degrees, about an arbitrary origin. This finds
/// the similarity transform onto the scene and the direction of racing,
/// which can oppose the stored centerline even when metadata says otherwise.
Future<SessionAlignment> alignToLap({
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
  final order = List.generate(samples.t.length, (i) => i)
    ..sort((a, b) => samples.t[a].compareTo(samples.t[b]));
  final source = [for (final i in order) (samples.x[i], samples.y[i])];
  final alignment = alignToPath(
    source: source,
    target: [for (final c in stations.center) (c.x, c.z)],
  );
  return SessionAlignment(
    alignment.transform,
    alignment.rmsError,
    directionSign: racingDirection([
      for (final (x, y) in source) alignment.transform.apply(x, y),
    ], TrackProjector(stations)),
  );
}

/// The fit and racing direction of a session relative to the stored path.
class SessionAlignment extends AlignmentResult {
  const SessionAlignment(
    super.transform,
    super.rmsError, {
    required this.directionSign,
  });

  final int directionSign;
}

/// Racing direction from time-ordered scene positions of a reference lap.
/// The median step ignores occasional projection errors and stationary noise.
int racingDirection(List<(double, double)> positions, TrackProjector track) {
  final steps = <double>[];
  PathPoint? previous;
  final n = track.stations.length;
  for (final (x, z) in positions) {
    final point = track.project(x, z, hint: previous?.station);
    if (previous != null) {
      var step = point.along - previous.along;
      if (track.stations.closed) {
        if (step > n / 2) step -= n;
        if (step < -n / 2) step += n;
      }
      if (step.abs() * track.metersPerStation > 0.5) steps.add(step);
    }
    previous = point;
  }
  if (steps.isEmpty) throw StateError('No movement in the reference lap');
  steps.sort();
  return steps[steps.length ~/ 2] < 0 ? -1 : 1;
}

/// Positions a lap must have for the fit to be trusted (~13 s at 3.85 Hz).
const _minSamples = 50;
