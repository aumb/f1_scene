// Measures how smoothly cars move in a replay: poses five minutes of a race
// at 60 fps through the app's own motion code and reports how often a car
// would need more acceleration than an F1 car can produce (6 g), which is
// what shows as stutter.
//
//   dart run tool/check_motion.dart [year] [meeting name filter]
//       [--start] [--raw] [--no-traffic]
//
// It also counts cars overlapping each other. --start measures the first
// five minutes from lights out instead of a mid-race stint; --raw skips the
// stamp jitter correction and --no-traffic the side-by-side separation, to
// see what each contributes.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:f1_scene/src/data/circuit.dart';
import 'package:f1_scene/src/geometry/track_alignment.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';
import 'package:f1_scene/src/race/car_motion.dart';
import 'package:f1_scene/src/race/location_timeline.dart';
import 'package:f1_scene/src/race/pit_lane_tracer.dart';
import 'package:f1_scene/src/race/race_repository.dart';
import 'package:f1_scene/src/race/stamp_jitter.dart';
import 'package:f1_scene/src/race/traffic.dart';
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
  final raw = args.contains('--raw');
  final separate = !args.contains('--no-traffic');
  final rest = args.where((a) => !a.startsWith('--')).toList();
  final year = rest.isEmpty ? 2024 : int.parse(rest.first);
  final filter = rest.length > 1 ? rest[1].toLowerCase() : 'azerbaijan';
  final repository = RaceRepository();
  final race = (await repository.races(year))
      .firstWhere((r) => r.meetingName.toLowerCase().contains(filter));
  final id = circuitIdByOpenF1Key[race.circuitKey]!;

  // Align on a clean lap, as the replay does.
  final laps = (await repository.laps(race.sessionKey))
      .where((l) => l.start != null && l.duration != null && !l.isPitOutLap)
      .where((l) => l.lapNumber > 2)
      .toList();
  final durations = laps.map((l) => l.duration!).toList()..sort();
  final median = durations[durations.length ~/ 2];
  final lap = laps.firstWhere((l) => l.duration! < median * 1.05);
  final stations = TrackStations.sample(_circuit(id));
  final reference = (await repository.locations(
    race.sessionKey,
    epoch: race.start,
    from: lap.start!,
    to: lap.start!.add(Duration(milliseconds: (lap.duration! * 1000).round())),
    driver: lap.driverNumber,
  )).samples[lap.driverNumber]!;
  final transform = alignToPath(
    source: [
      for (var i = 0; i < reference.t.length; i++)
        (reference.x[i], reference.y[i]),
    ],
    target: [for (final c in stations.center) (c.x, c.z)],
  ).transform;
  final track = TrackProjector(stations);
  final pitLane = await tracePitLane(
    repository: repository,
    session: race,
    stops: await repository.pitStops(race.sessionKey),
    transform: transform,
    track: track,
  );

  // Five minutes from the reference lap on (or from lights out), every car.
  final allLaps = await repository.laps(race.sessionKey);
  final begin = args.contains('--start')
      ? allLaps
            .where((l) => l.lapNumber == 1 && l.start != null)
            .map((l) => l.start!)
            .reduce((a, b) => a.isBefore(b) ? a : b)
      : lap.start!;
  final batch = await repository.locations(
    race.sessionKey,
    epoch: race.start,
    from: begin,
    to: begin.add(const Duration(minutes: 5)),
  );
  final from = begin.difference(race.start).inMicroseconds / 1e6;
  final timeline = LocationTimeline(start: from, end: from + 300)
    ..addChunk(0, raw ? batch : await correctStampJitter(batch));
  final motion = CarMotion(
    alignment: transform,
    track: track,
    pitLane: pitLane == null ? null : TrackProjector(pitLane),
  );

  final traffic = TrafficSeparation(track);
  final drivers = timeline.drivers.toList();
  Map<int, CarPose> posesAt(double t) {
    final poses = {
      for (final d in drivers)
        d: ?motion.pose(
          d,
          timeline.windowAt(d, t, reach: CarMotion.smoothing),
          t,
        ),
    };
    return separate ? traffic.separate(poses) : poses;
  }

  const dt = 1 / 60;
  const harshLimit = 60.0; // m/s², about 6 g
  final surges = <double>[], sways = <double>[];
  var harshSurge = 0, harshSway = 0;
  final recent = <Map<int, CarPose>>[];
  for (var t = from + 3; t < from + 297; t += dt) {
    recent.add(posesAt(t));
    if (recent.length > 3) recent.removeAt(0);
    if (recent.length < 3) continue;
    for (final d in drivers) {
      final [a, b, c] = [for (final poses in recent) poses[d]];
      if (a == null || b == null || c == null) continue;
      if (a.inPit || b.inPit || c.inPit) continue;
      final acceleration =
          (a.position + c.position - b.position * 2) / (dt * dt);
      // Split into surge (speed changing, the stutter) and sway (turning
      // or drifting sideways).
      final forward = (c.position - a.position)..normalize();
      final surge = acceleration.dot(forward).abs();
      final sway = (acceleration - forward * acceleration.dot(forward)).length;
      surges.add(surge);
      sways.add(sway);
      if (surge > harshLimit) harshSurge++;
      if (sway > harshLimit) harshSway++;
    }
  }
  // Wobble: how often each car's sideways offset, heading and orbit-view
  // size reverse direction at a visible rate (a clean lane change reverses
  // once or twice, a wobble constantly), and the fastest each changes: a
  // jump shows as a sideways speed no car could have.
  {
    final lateralTurns = <int, int>{},
        yawTurns = <int, int>{},
        scaleTurns = <int, int>{};
    final lastLat = <int, double>{}, lastLatRate = <int, double>{};
    final lastYaw = <int, double>{}, lastYawRate = <int, double>{};
    final lastScale = <int, double>{}, lastScaleRate = <int, double>{};
    var maxLatRate = 0.0, maxYawRate = 0.0, maxScaleRate = 0.0;
    void turn(
      Map<int, int> turns,
      Map<int, double> last,
      Map<int, double> lastRate,
      int d,
      double v,
      double threshold,
      void Function(double) rate, {
      bool wraps = false,
    }) {
      final previous = last[d];
      last[d] = v;
      if (previous == null) return;
      var change = v - previous;
      // Headings wrap at ±π; take the short way round.
      if (wraps) change = (change + math.pi) % (2 * math.pi) - math.pi;
      final r = change / dt;
      rate(r.abs());
      final pr = lastRate[d];
      if (r.abs() < threshold) return;
      if (pr != null && pr.sign != r.sign) turns[d] = (turns[d] ?? 0) + 1;
      lastRate[d] = r;
    }

    for (var t = from + 3; t < from + 123; t += dt) {
      final poses = posesAt(t);
      final scales = readableScales(poses, 4);
      for (final MapEntry(key: d, value: p) in poses.entries) {
        if (p.inPit) continue;
        turn(
          lateralTurns,
          lastLat,
          lastLatRate,
          d,
          p.lateral,
          0.5,
          (r) => maxLatRate = math.max(maxLatRate, r),
        );
        turn(
          yawTurns,
          lastYaw,
          lastYawRate,
          d,
          p.heading,
          0.1,
          (r) => maxYawRate = math.max(maxYawRate, r),
          wraps: true,
        );
        turn(
          scaleTurns,
          lastScale,
          lastScaleRate,
          d,
          scales[d]!,
          0.5,
          (r) => maxScaleRate = math.max(maxScaleRate, r),
        );
      }
    }
    int total(Map<int, int> m) => m.values.fold(0, (a, b) => a + b);
    final perCarMinute = drivers.length * 2;
    stdout.writeln(
      '  reversals per car-minute: lateral ${(total(lateralTurns) / perCarMinute).toStringAsFixed(1)}, '
      'heading ${(total(yawTurns) / perCarMinute).toStringAsFixed(1)}, orbit size ${(total(scaleTurns) / perCarMinute).toStringAsFixed(1)}; '
      'fastest: lateral ${maxLatRate.toStringAsFixed(1)} m/s, heading '
      '${maxYawRate.toStringAsFixed(1)} rad/s, size '
      '${maxScaleRate.toStringAsFixed(1)} x/s',
    );
  }

  String report(String name, List<double> values, int harsh) {
    values.sort();
    double quantile(double q) => values[((values.length - 1) * q).round()];
    return '  $name: over 6 g ${(100 * harsh / values.length).toStringAsFixed(1)}%, '
        'median ${quantile(0.5).toStringAsFixed(1)} '
        'p99 ${quantile(0.99).toStringAsFixed(0)} m/s²';
  }

  // Cars overlapping: pairs closer than a car's footprint (5.2 m by 2.0 m)
  // in track space, sampled at 10 Hz.
  ({double along, double lateral})? trackSpace(CarPose? p) {
    if (p == null || p.inPit) return null;
    final q = track.project(p.position.x, p.position.z);
    return (along: q.along * track.metersPerStation, lateral: q.lateral);
  }

  final lapLength = stations.length * track.metersPerStation;
  double gap(double a, double b) {
    var d = a - b;
    if (d > lapLength / 2) d -= lapLength;
    if (d < -lapLength / 2) d += lapLength;
    return d;
  }

  var overlapping = 0, alongside = 0;
  final separations = <double>[];
  for (var t = from + 3; t < from + 297; t += 0.1) {
    final poses = posesAt(t);
    final at = {for (final d in drivers) d: trackSpace(poses[d])};
    for (var i = 0; i < drivers.length; i++) {
      for (var j = i + 1; j < drivers.length; j++) {
        final a = at[drivers[i]], b = at[drivers[j]];
        if (a == null || b == null) continue;
        final ds = gap(a.along, b.along), dl = a.lateral - b.lateral;
        if (ds.abs() > 5.2) continue;
        alongside++;
        separations.add(dl.abs());
        if (dl.abs() < 2.0) overlapping++;
      }
    }
  }
  separations.sort();
  final overlapReport = alongside == 0
      ? '  no cars alongside'
      : '  alongside (within a car length): $alongside pair samples, '
            'lateral gap median '
            '${separations[separations.length ~/ 2].toStringAsFixed(1)} m; '
            'overlapping $overlapping '
            '(${(100 * overlapping / alongside).toStringAsFixed(0)}%)';

  stdout
    ..writeln(
      '${race.meetingName} $year${raw ? ' (raw stamps)' : ''}'
      '${separate ? '' : ' (no traffic separation)'}: '
      '${timeline.drivers.length} cars, ${surges.length} frames',
    )
    ..writeln(report('surge (speed changes)', surges, harshSurge))
    ..writeln(report('sway (turning, sideways)', sways, harshSway))
    ..writeln(overlapReport);
  exit(0);
}
