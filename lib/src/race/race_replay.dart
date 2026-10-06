import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../geometry/track_alignment.dart';
import '../geometry/track_mesh.dart';
import '../geometry/track_projector.dart';
import 'car_motion.dart';
import 'drs_zones.dart';
import 'location_timeline.dart';
import 'pit_lane_tracer.dart';
import 'race_models.dart';
import 'race_repository.dart';
import 'session_alignment.dart';
import 'stamp_jitter.dart';
import 'timing_board.dart';
import 'traffic.dart';

/// Plays back one race: owns its data, the alignment from OpenF1's circuit
/// frame onto the scene, and the playback clock.
///
/// Times are seconds since [session] start ([RaceSession.start]).
class RaceReplay extends ChangeNotifier {
  RaceReplay._({
    required this.session,
    required this.drivers,
    required this.alignment,
    required this.pitLane,
    required this.featuredDriver,
    required this.timing,
    required this._repository,
    required this._motion,
    required this._leaderLapStarts,
    required this.raceStart,
    required double end,
  }) : timeline = LocationTimeline(
         // From the session start when that is earlier: after a red flag on
         // lap 1 (Monaco 2024), OpenF1 times lap 1 from the restart, and the
         // original start would otherwise be cut off.
         start: math.min(0.0, raceStart - _preRoll),
         end: end,
       ) {
    time.value = raceStart - _lead;
    _updateStandings();
  }

  /// Loads everything needed to start playback of [session] on a circuit
  /// sampled as [stations].
  static Future<RaceReplay> load({
    required RaceRepository repository,
    required RaceSession session,
    required TrackStations stations,
  }) async {
    final key = session.sessionKey;
    final (drivers, laps, pitStops, positions, intervals, stints) = await (
      repository.drivers(key),
      repository.laps(key),
      repository.pitStops(key),
      repository.positions(key),
      repository.intervals(key),
      repository.stints(key),
    ).wait;
    if (drivers.isEmpty || laps.isEmpty) {
      throw StateError('OpenF1 has no timing for ${session.meetingName}');
    }

    final (leaderLapStarts, lastFinish) = _lapTimeline(session, laps);
    final alignment = await alignToLap(
      repository: repository,
      session: session,
      lap: referenceLap(laps),
      stations: stations,
    );
    debugPrint(
      'Aligned ${session.meetingName} ${session.year}: '
      '${alignment.transform}, rms ${alignment.rmsError.toStringAsFixed(1)} m',
    );
    final track = TrackProjector(stations);
    final pitLane = await _pitLaneOrNull(
      repository,
      session,
      pitStops,
      alignment.transform,
      track,
    );

    final replay = RaceReplay._(
      session: session,
      drivers: drivers,
      alignment: alignment,
      pitLane: pitLane,
      featuredDriver: _featuredDriver(laps, drivers),
      timing: TimingBoard(
        epoch: session.start,
        drivers: drivers,
        laps: laps,
        positions: positions,
        intervals: intervals,
        stints: stints,
      ),
      repository: repository,
      motion: CarMotion(
        alignment: alignment.transform,
        track: track,
        pitLane: pitLane == null ? null : TrackProjector(pitLane),
      ),
      leaderLapStarts: leaderLapStarts,
      raceStart: leaderLapStarts.first,
      end: lastFinish + 60,
    );
    replay._loadDrsZones(track);
    return replay;
  }

  /// When the leader started each lap (lap n at index n - 1), and when the
  /// last car finished, in seconds since the session start.
  static (List<double>, double) _lapTimeline(
    RaceSession session,
    List<RaceLap> laps,
  ) {
    // The earliest start of each lap number is the leader starting it.
    final lapStarts = <int, double>{};
    var lastFinish = 0.0;
    for (final lap in laps) {
      final start = lap.start;
      if (start == null) continue;
      final t = session.secondsAt(start);
      lapStarts.update(lap.lapNumber, (v) => math.min(v, t), ifAbsent: () => t);
      lastFinish = math.max(lastFinish, t + (lap.duration ?? 0));
    }
    if (lapStarts[1] == null) {
      throw StateError('OpenF1 has no start time for lap 1');
    }
    final lapCount = lapStarts.keys.reduce(math.max);
    return (
      [for (var n = 1; n <= lapCount; n++) lapStarts[n] ?? double.infinity],
      lastFinish,
    );
  }

  /// The pit lane traced from a stop, or null when none could be. It is a
  /// nicety; the replay never fails over it.
  static Future<TrackStations?> _pitLaneOrNull(
    RaceRepository repository,
    RaceSession session,
    List<RacePitStop> stops,
    SimilarityTransform2D transform,
    TrackProjector track,
  ) async {
    try {
      return await tracePitLane(
        repository: repository,
        session: session,
        stops: stops,
        transform: transform,
        track: track,
      );
    } catch (e) {
      debugPrint('No pit lane: $e');
      return null;
    }
  }

  /// Whoever led after lap 1, to follow by default.
  static int _featuredDriver(List<RaceLap> laps, List<RaceDriver> drivers) {
    final lap2 = laps.where((l) => l.lapNumber == 2 && l.start != null);
    return lap2.isEmpty
        ? drivers.first.number
        : lap2
              .reduce((a, b) => a.start!.isBefore(b.start!) ? a : b)
              .driverNumber;
  }

  /// Seconds before lights out where playback starts.
  static const double _lead = 15;

  /// Playback speed from which two chunks ahead are fetched rather than
  /// one (a 5-minute chunk lasts under 20 s at 16x).
  static const double _fastSpeed = 16;

  /// How much of the formation lap to show before lights out.
  static const double _preRoll = 300;

  final RaceSession session;
  final List<RaceDriver> drivers;
  final AlignmentResult alignment;

  /// Traced from a pit stop; null when no usable stop could be traced.
  final TrackStations? pitLane;

  /// Who to follow by default: the leader after lap 1.
  final int featuredDriver;

  /// What the timing screens said at any moment.
  final TimingBoard timing;

  /// The running order at the playhead, refreshed a few times a second.
  final standings = ValueNotifier<List<TowerRow>>(const []);

  /// DRS zones, derived from four minutes of mid-race car data fetched in
  /// the background after [load]; empty until then, if that fails, and for
  /// seasons without DRS.
  final drsZones = ValueNotifier<List<TrackSpan>>(const []);

  /// Car poses at the playhead, updated every [tick].
  Map<int, CarPose> get currentPoses => _currentPoses;
  Map<int, CarPose> _currentPoses = const {};
  double _sinceStandings = 0;

  /// Lights out, in seconds since session start.
  final double raceStart;
  final LocationTimeline timeline;

  final RaceRepository _repository;
  final CarMotion _motion;
  late final _traffic = TrafficSeparation(_motion.track);
  final List<double> _leaderLapStarts;
  final _retryAfter = <int, DateTime>{};
  bool _disposed = false;

  /// The playhead. Changes every frame while playing, so it notifies on its
  /// own rather than through this object.
  final time = ValueNotifier<double>(0);

  bool get playing => _playing;
  bool _playing = false;

  double get speed => _speed;
  double _speed = 1;

  /// True while playback waits for position data.
  bool get buffering => _buffering;
  bool _buffering = false;

  int get lapCount => _leaderLapStarts.length;

  /// The leader's lap at [t]; 0 before the start.
  int lapAt(double t) {
    var lap = 0;
    while (lap < _leaderLapStarts.length && _leaderLapStarts[lap] <= t) {
      lap++;
    }
    return lap;
  }

  void play() {
    if (time.value >= timeline.end) time.value = timeline.start;
    _playing = true;
    notifyListeners();
  }

  void pause() {
    _playing = false;
    _setBuffering(false);
    notifyListeners();
  }

  set speed(double value) {
    _speed = value;
    notifyListeners();
  }

  void seek(double t) {
    time.value = t.clamp(timeline.start, timeline.end);
    _requestChunks();
    // Pose first: the standings flag the cars in the pit lane.
    _currentPoses = _computePoses();
    _updateStandings();
  }

  /// Advances playback by [dt] wall-clock seconds and poses the cars.
  void tick(double dt) {
    _advance(dt);
    _currentPoses = _computePoses();
    _sinceStandings += dt;
    if (_sinceStandings >= 0.25) _updateStandings();
  }

  void _advance(double dt) {
    _requestChunks();
    if (!_playing) return;
    if (!timeline.isReady(time.value)) {
      _setBuffering(true);
      return;
    }
    _setBuffering(false);
    final next = time.value + dt * _speed;
    if (next >= timeline.end) {
      time.value = timeline.end;
      pause();
    } else {
      time.value = next;
    }
  }

  void _updateStandings() {
    _sinceStandings = 0;
    final rows = timing.standingsAt(
      time.value,
      inPit: {
        for (final MapEntry(:key, :value) in _currentPoses.entries)
          if (value.inPit) key,
      },
    );
    if (!listEquals(rows, standings.value)) standings.value = rows;
  }

  /// Derives the DRS zones from a few minutes of mid-race car data.
  Future<void> _loadDrsZones(TrackProjector track) async {
    // 15 minutes in: DRS is enabled after two laps, and an early safety car
    // is usually over.
    final from = session.timeAt(raceStart + 900);
    final to = from.add(const Duration(minutes: 4));
    try {
      final (open, locations) = await (
        _repository.drsOpen(
          session.sessionKey,
          epoch: session.start,
          from: from,
          to: to,
        ),
        _repository.locations(
          session.sessionKey,
          epoch: session.start,
          from: from,
          to: to,
        ),
      ).wait;
      if (_disposed) return;
      drsZones.value = drsZonesFrom(
        openTimes: open,
        locations: locations,
        transform: alignment.transform,
        track: track,
      );
      debugPrint('DRS zones: ${drsZones.value}');
    } catch (e) {
      debugPrint('No DRS zones: $e');
    }
  }

  /// Every driver with data at the playhead, in scene space, side by side
  /// where the data has them in the same spot.
  Map<int, CarPose> _computePoses() {
    final t = time.value;
    return _traffic.separate({
      for (final d in drivers) d.number: ?_poseOf(d.number, t),
    });
  }

  /// One car's pose. Release builds hide a car whose data trips the motion
  /// code rather than freezing every car; debug builds surface the error.
  CarPose? _poseOf(int driver, double t) {
    try {
      return _motion.pose(
        driver,
        timeline.windowAt(driver, t, reach: CarMotion.fitHalfWidth),
        t,
      );
    } catch (e) {
      if (kDebugMode) rethrow;
      if (_failedDrivers.add(driver)) debugPrint('Car $driver hidden: $e');
      return null;
    }
  }

  final _failedDrivers = <int>{};

  void _requestChunks() {
    final ahead = _speed >= _fastSpeed ? 2 : 1;
    for (final chunk in timeline.wanted(time.value, ahead: ahead)) {
      final retry = _retryAfter[chunk];
      if (retry != null && DateTime.now().isBefore(retry)) continue;
      _loadChunk(chunk);
    }
  }

  Future<void> _loadChunk(int chunk) async {
    timeline.markLoading(chunk);
    final (from, to) = timeline.chunkRange(chunk);
    try {
      final batch = await _repository.locations(
        session.sessionKey,
        epoch: session.start,
        from: session.timeAt(from),
        to: session.timeAt(to),
      );
      if (_disposed) return;
      final corrected = await correctStampJitter(batch);
      if (_disposed) return;
      timeline.addChunk(chunk, corrected);
    } catch (e) {
      if (_disposed) return;
      debugPrint('Location chunk $chunk failed: $e');
      timeline.markFailed(chunk);
      _retryAfter[chunk] = DateTime.now().add(const Duration(seconds: 5));
    }
  }

  void _setBuffering(bool value) {
    if (_buffering == value) return;
    _buffering = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    time.dispose();
    standings.dispose();
    drsZones.dispose();
    super.dispose();
  }
}
