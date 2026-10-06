// Measures how cars move in a replay, posing them at 60 fps through the
// app's own motion code:
//
// - smoothness: how often a car would need more acceleration than an F1 car
//   can produce (6 g), split into surge (speed changing: what reads as
//   stutter) and sway (turning or drifting sideways);
// - wobble: how often each car's sideways offset, heading and orbit-view
//   size reverse direction at a visible rate, and the fastest each changes
//   (a jump shows as a speed no car could have);
// - overlaps: how often two cars within a car length sit less than a car's
//   width apart.
//
//   dart run tool/check_motion.dart [year] [meeting] [--start] [--raw]
//       [--no-traffic]
//
// year defaults to 2024 and meeting (part of its name) to "azerbaijan".
// Five minutes are measured from a clean mid-race lap, or from lights out
// with --start. --raw skips the stamp jitter correction and --no-traffic the
// side-by-side separation, to see what each contributes. Run it from the
// repository root (it reads assets/circuits/).
import 'dart:io';
import 'dart:math' as math;

import 'package:f1_scene/src/data/circuit_files.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';
import 'package:f1_scene/src/race/car_motion.dart';
import 'package:f1_scene/src/race/location_timeline.dart';
import 'package:f1_scene/src/race/pit_lane_tracer.dart';
import 'package:f1_scene/src/race/race_repository.dart';
import 'package:f1_scene/src/race/session_alignment.dart';
import 'package:f1_scene/src/race/stamp_jitter.dart';
import 'package:f1_scene/src/race/traffic.dart';
import 'package:f1_scene/src/race/venues.dart';

/// Seconds of race measured, and the frame step.
const _span = 300;
const _dt = 1 / 60;

/// About 6 g, in m/s²: more than an F1 car brakes or corners at.
const _harsh = 60.0;

/// Seconds the wobble measure covers (it is the slow one).
const _wobbleSpan = 120.0;

/// A car's footprint, in metres.
const _carLength = 5.2, _carWidth = 2.0;

Future<void> main(List<String> args) async {
  final raw = args.contains('--raw');
  final separate = !args.contains('--no-traffic');
  final rest = [
    for (final a in args)
      if (!a.startsWith('--')) a,
  ];
  final year = rest.isEmpty ? 2024 : int.parse(rest.first);
  final filter = rest.length > 1 ? rest[1].toLowerCase() : 'azerbaijan';

  final repository = RaceRepository();
  final race = (await repository.races(year))
      .where((r) => r.meetingName.toLowerCase().contains(filter))
      .firstOrNull;
  final id = race == null ? null : circuitIdByOpenF1Key[race.circuitKey];
  if (race == null || id == null) {
    stderr.writeln('No $year race matching "$filter" with a vendored layout.');
    exit(1);
  }

  // Align and trace the pit lane as the replay does.
  final stations = TrackStations.sample(loadCircuit(id));
  final track = TrackProjector(stations);
  final laps = await repository.laps(race.sessionKey);
  final reference = referenceLap(laps);
  final transform = (await alignToLap(
    repository: repository,
    session: race,
    lap: reference,
    stations: stations,
  )).transform;
  final pitLane = await tracePitLane(
    repository: repository,
    session: race,
    stops: await repository.pitStops(race.sessionKey),
    transform: transform,
    track: track,
  );

  final begin = args.contains('--start')
      ? laps
            .where((l) => l.lapNumber == 1 && l.start != null)
            .map((l) => l.start!)
            .reduce((a, b) => a.isBefore(b) ? a : b)
      : reference.start!;
  final batch = await repository.locations(
    race.sessionKey,
    epoch: race.start,
    from: begin,
    to: begin.add(const Duration(seconds: _span)),
  );
  final from = race.secondsAt(begin);
  final timeline = LocationTimeline(start: from, end: from + _span)
    ..addChunk(0, raw ? batch : await correctStampJitter(batch));
  final motion = CarMotion(
    alignment: transform,
    track: track,
    pitLane: pitLane == null ? null : TrackProjector(pitLane),
  );
  final traffic = TrafficSeparation(track);
  final drivers = timeline.drivers.toList();

  /// Every car's pose at [t], as the replay would show it.
  Map<int, CarPose> posesAt(double t) {
    final poses = {
      for (final d in drivers)
        d: ?motion.pose(
          d,
          timeline.windowAt(d, t, reach: CarMotion.fitHalfWidth),
          t,
        ),
    };
    return separate ? traffic.separate(poses) : poses;
  }

  // Skip the edges, where the window around each pose is one-sided.
  final start = from + 3, end = from + _span - 3;
  stdout
    ..writeln(
      '${race.meetingName} $year'
      '${raw ? ' (raw stamps)' : ''}'
      '${separate ? '' : ' (no traffic separation)'}: '
      '${drivers.length} cars',
    )
    ..writeln(_smoothness(posesAt, drivers, start, end))
    ..writeln(_wobble(posesAt, drivers, start, start + _wobbleSpan))
    ..writeln(_overlaps(posesAt, drivers, track, start, end));
  // The HTTP client keeps the process alive; we're done.
  exit(0);
}

typedef _Poses = Map<int, CarPose> Function(double t);

/// Surge and sway, from second differences of each car's position.
String _smoothness(
  _Poses posesAt,
  List<int> drivers,
  double start,
  double end,
) {
  final surges = <double>[], sways = <double>[];
  final recent = <Map<int, CarPose>>[];
  for (var t = start; t < end; t += _dt) {
    recent.add(posesAt(t));
    if (recent.length > 3) recent.removeAt(0);
    if (recent.length < 3) continue;
    for (final d in drivers) {
      final [a, b, c] = [for (final poses in recent) poses[d]];
      if (a == null || b == null || c == null) continue;
      if (a.inPit || b.inPit || c.inPit) continue;
      final acceleration =
          (a.position + c.position - b.position * 2) / (_dt * _dt);
      final forward = (c.position - a.position)..normalize();
      final surge = acceleration.dot(forward);
      surges.add(surge.abs());
      sways.add((acceleration - forward * surge).length);
    }
  }
  String line(String name, List<double> values) {
    values.sort();
    final over = values.where((v) => v > _harsh).length / values.length;
    double quantile(double q) => values[((values.length - 1) * q).round()];
    return '  $name: over 6 g ${(100 * over).toStringAsFixed(1)}%, '
        'median ${quantile(0.5).toStringAsFixed(1)} '
        'p99 ${quantile(0.99).toStringAsFixed(0)} m/s²';
  }

  return '${line('surge (speed changes)', surges)}\n'
      '${line('sway (turning, sideways)', sways)}';
}

/// How often each car's sideways offset, heading and orbit-view size reverse
/// direction at a visible rate (a clean lane change reverses once or twice, a
/// wobble constantly), and the fastest each changed.
String _wobble(_Poses posesAt, List<int> drivers, double start, double end) {
  final lateral = _Channel(minRate: 0.5);
  final heading = _Channel(minRate: 0.1, wraps: true);
  final size = _Channel(minRate: 0.5);
  for (var t = start; t < end; t += _dt) {
    final poses = posesAt(t);
    final scales = readableScales(poses, 4);
    for (final MapEntry(key: d, value: p) in poses.entries) {
      if (p.inPit) continue;
      lateral.record(d, p.lateral);
      heading.record(d, p.heading);
      size.record(d, scales[d]!);
    }
  }
  final carMinutes = drivers.length * (end - start) / 60;
  String perCarMinute(_Channel c) =>
      (c.reversals / carMinutes).toStringAsFixed(1);
  return '  reversals per car-minute: lateral ${perCarMinute(lateral)}, '
      'heading ${perCarMinute(heading)}, orbit size ${perCarMinute(size)}; '
      'fastest: lateral ${lateral.fastest.toStringAsFixed(1)} m/s, '
      'heading ${heading.fastest.toStringAsFixed(1)} rad/s, '
      'size ${size.fastest.toStringAsFixed(1)} x/s';
}

/// One quantity followed per car, counting how often its rate of change
/// flips sign.
class _Channel {
  _Channel({required this.minRate, this.wraps = false});

  /// Rates slower than this are too slow to see and aren't counted.
  final double minRate;

  /// Angles wrap at ±π; changes take the short way round.
  final bool wraps;

  int reversals = 0;
  double fastest = 0;
  final _last = <int, double>{};
  final _lastRate = <int, double>{};

  void record(int driver, double value) {
    final previous = _last[driver];
    _last[driver] = value;
    if (previous == null) return;
    var change = value - previous;
    if (wraps) change = (change + math.pi) % (2 * math.pi) - math.pi;
    final rate = change / _dt;
    fastest = math.max(fastest, rate.abs());
    if (rate.abs() < minRate) return;
    final before = _lastRate[driver];
    if (before != null && before.sign != rate.sign) reversals++;
    _lastRate[driver] = rate;
  }
}

/// Pairs of cars within a car length along the track, sampled at 10 Hz, and
/// how many of them sit less than a car's width apart.
String _overlaps(
  _Poses posesAt,
  List<int> drivers,
  TrackProjector track,
  double start,
  double end,
) {
  final lap = track.stations.length * track.metersPerStation;
  ({double along, double lateral})? trackSpace(CarPose? p) {
    if (p == null || p.inPit) return null;
    final q = track.project(p.position.x, p.position.z);
    return (along: q.along * track.metersPerStation, lateral: q.lateral);
  }

  var overlapping = 0;
  final gaps = <double>[];
  for (var t = start; t < end; t += 0.1) {
    final poses = posesAt(t);
    final at = [for (final d in drivers) trackSpace(poses[d])];
    for (var i = 0; i < at.length; i++) {
      for (var j = i + 1; j < at.length; j++) {
        final a = at[i], b = at[j];
        if (a == null || b == null) continue;
        // The short way round the lap.
        var along = (a.along - b.along).abs() % lap;
        if (along > lap / 2) along = lap - along;
        if (along > _carLength) continue;
        final apart = (a.lateral - b.lateral).abs();
        gaps.add(apart);
        if (apart < _carWidth) overlapping++;
      }
    }
  }
  if (gaps.isEmpty) return '  no cars alongside';
  gaps.sort();
  return '  alongside (within a car length): ${gaps.length} pair samples, '
      'lateral gap median ${gaps[gaps.length ~/ 2].toStringAsFixed(1)} m; '
      'overlapping $overlapping '
      '(${(100 * overlapping / gaps.length).toStringAsFixed(0)}%)';
}
