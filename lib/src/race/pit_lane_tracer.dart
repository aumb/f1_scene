import '../geometry/pit_lane.dart';
import '../geometry/track_alignment.dart';
import '../geometry/track_mesh.dart';
import '../geometry/track_projector.dart';
import 'race_models.dart';
import 'race_repository.dart';

/// Traces the pit lane of [session] from the positions of one typical stop.
///
/// Returns null when the race had no usable stop or its path could not be
/// traced.
Future<TrackStations?> tracePitLane({
  required RaceRepository repository,
  required RaceSession session,
  required List<RacePitStop> stops,
  required SimilarityTransform2D transform,
  required TrackProjector track,
}) async {
  // A stop with a typical lane time: no drive-through or long repair.
  final timed =
      stops.where((s) => s.laneDuration != null && s.lapNumber > 1).toList()
        ..sort((a, b) => a.laneDuration!.compareTo(b.laneDuration!));
  if (timed.isEmpty) return null;
  final stop = timed[timed.length ~/ 2];

  // OpenF1's pit `date` is not the pit entry: at Baku 2026 the car sits in
  // its box ~10 s before it and rejoins ~5 s after. Take a full lane time
  // either side; the tracer keeps only the stretch beside the track.
  final lane = Duration(milliseconds: (stop.laneDuration! * 1000).round());
  final batch = await repository.locations(
    session.sessionKey,
    epoch: session.start,
    from: stop.date.subtract(lane + const Duration(seconds: 15)),
    to: stop.date.add(lane + const Duration(seconds: 5)),
    driver: stop.driverNumber,
  );
  final samples = batch.samples[stop.driverNumber];
  if (samples == null) return null;
  return pitLaneFromPath([
    for (var i = 0; i < samples.t.length; i++)
      transform.apply(samples.x[i], samples.y[i]),
  ], track);
}
