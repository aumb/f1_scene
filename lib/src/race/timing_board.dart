import 'dart:math' as math;

import 'race_models.dart';

/// One line of the timing tower.
class TowerRow {
  const TowerRow({
    required this.driver,
    required this.position,
    required this.lap,
    this.gap,
    this.interval,
    this.compound,
    this.tyreAge,
    this.inPit = false,
    this.retired = false,
  });

  final int driver;
  final int position;

  /// The lap the driver is on; 0 before the start.
  final int lap;
  final Gap? gap;
  final Gap? interval;
  final String? compound;
  final int? tyreAge;
  final bool inPit;
  final bool retired;

  @override
  bool operator ==(Object other) =>
      other is TowerRow &&
      other.driver == driver &&
      other.position == position &&
      other.lap == lap &&
      other.gap == gap &&
      other.interval == interval &&
      other.compound == compound &&
      other.tyreAge == tyreAge &&
      other.inPit == inPit &&
      other.retired == retired;

  @override
  int get hashCode => Object.hash(
    driver,
    position,
    lap,
    gap,
    interval,
    compound,
    tyreAge,
    inPit,
    retired,
  );
}

/// How a sector time compares with the bests set so far.
enum SectorRating { none, slower, personalBest, overallBest }

/// The followed driver's timing at a moment.
class DriverTiming {
  const DriverTiming({
    required this.lap,
    this.lapElapsed,
    this.lastLap,
    this.bestLap,
    this.lastSectors = const [],
  });

  /// The lap being driven; 0 before the start.
  final int lap;

  /// Seconds into the current lap.
  final double? lapElapsed;

  /// The most recent completed lap.
  final RaceLap? lastLap;

  /// Personal best lap time so far.
  final double? bestLap;

  /// [lastLap]'s sectors rated against the bests set up to its end.
  final List<SectorRating> lastSectors;
}

/// Answers "what did the timing screens say at time t" from a race's
/// OpenF1 timing data. Times are seconds since the session start.
class TimingBoard {
  TimingBoard({
    required DateTime epoch,
    required List<RaceDriver> drivers,
    required List<RaceLap> laps,
    required List<({int driver, DateTime date, int position})> positions,
    required List<({int driver, DateTime date, Gap? gap, Gap? interval})>
    intervals,
    required List<RaceStint> stints,
  }) : _drivers = [for (final d in drivers) d.number] {
    double since(DateTime t) => t.difference(epoch).inMicroseconds / 1e6;

    for (final p in positions) {
      _positions
          .putIfAbsent(p.driver, _Series.new)
          .add(since(p.date), p.position);
    }
    for (final i in intervals) {
      _intervals.putIfAbsent(i.driver, _Series.new).add(since(i.date), (
        i.gap,
        i.interval,
      ));
    }
    for (final series in [..._positions.values, ..._intervals.values]) {
      series.sort();
    }
    for (final lap in laps) {
      final start = lap.start;
      if (start == null) continue;
      _laps
          .putIfAbsent(lap.driverNumber, () => [])
          .add(_TimedLap(lap, since(start)));
    }
    for (final list in _laps.values) {
      list.sort((a, b) => a.lap.lapNumber.compareTo(b.lap.lapNumber));
    }
    _allLaps = [for (final list in _laps.values) ...list]
      ..sort((a, b) => a.end.compareTo(b.end));
    for (final stint in stints) {
      _stints.putIfAbsent(stint.driverNumber, () => []).add(stint);
    }
    final durations = [
      for (final l in _allLaps)
        if (l.lap.duration != null) l.lap.duration!,
    ]..sort();
    _medianLap = durations.isEmpty ? 90 : durations[durations.length ~/ 2];
    final lapCount = laps.fold(0, (m, l) => math.max(m, l.lapNumber));
    _finish = _allLaps
        .where((l) => l.lap.lapNumber == lapCount)
        .fold(double.infinity, (m, l) => math.min(m, l.end));
  }

  final List<int> _drivers;
  final _positions = <int, _Series<int>>{};
  final _intervals = <int, _Series<(Gap?, Gap?)>>{};
  final _laps = <int, List<_TimedLap>>{};
  late final List<_TimedLap> _allLaps;
  final _stints = <int, List<RaceStint>>{};
  late final double _medianLap;

  /// When the leader took the chequered flag.
  late final double _finish;

  /// The running order at [t]. Drivers in [inPit] are flagged as such.
  List<TowerRow> standingsAt(double t, {Set<int> inPit = const {}}) {
    final started = _drivers.any((d) => _lapOf(d, t) > 0);
    final rows = [
      for (final driver in _drivers)
        () {
          final lap = _lapOf(driver, t);
          // Gaps mean nothing on the grid or the formation lap.
          final (gap, interval) = started
              ? _intervals[driver]?.at(t) ?? (null, null)
              : (null, null);
          final stint = _stintOf(driver, math.max(lap, 1));
          return TowerRow(
            driver: driver,
            position: _positions[driver]?.at(t) ?? 99,
            lap: lap,
            gap: gap,
            interval: interval,
            compound: stint?.compound,
            tyreAge: stint == null
                ? null
                : stint.tyreAgeAtStart + math.max(0, lap - stint.lapStart),
            inPit: inPit.contains(driver),
            retired: started && _retiredAt(driver, t),
          );
        }(),
    ];
    rows.sort((a, b) {
      if (a.retired != b.retired) return a.retired ? 1 : -1;
      final byPosition = a.position.compareTo(b.position);
      return byPosition != 0 ? byPosition : a.driver.compareTo(b.driver);
    });
    return rows;
  }

  DriverTiming driverAt(int driver, double t) {
    final laps = _laps[driver] ?? const [];
    final lap = _lapOf(driver, t);
    _TimedLap? current;
    _TimedLap? last;
    double? best;
    for (final l in laps) {
      if (l.start <= t && l.lap.lapNumber == lap) current = l;
      if (l.end <= t) {
        last = l;
        final d = l.lap.duration;
        if (d != null) best = best == null ? d : math.min(best, d);
      }
    }
    return DriverTiming(
      lap: lap,
      lapElapsed: current == null ? null : t - current.start,
      lastLap: last?.lap,
      bestLap: best,
      lastSectors: last == null ? const [] : _rateSectors(last),
    );
  }

  /// Rates each sector of [lap] against the bests set by its end: purple
  /// for the fastest of anyone, green for the driver's own best.
  List<SectorRating> _rateSectors(_TimedLap lap) {
    final overall = List<double>.filled(3, double.infinity);
    final personal = List<double>.filled(3, double.infinity);
    for (final l in _allLaps) {
      if (l.end > lap.end) break;
      for (var s = 0; s < 3; s++) {
        final time = l.lap.sectors[s];
        if (time == null) continue;
        overall[s] = math.min(overall[s], time);
        if (l.lap.driverNumber == lap.lap.driverNumber) {
          personal[s] = math.min(personal[s], time);
        }
      }
    }
    return [
      for (var s = 0; s < 3; s++)
        switch (lap.lap.sectors[s]) {
          null => SectorRating.none,
          final time when time <= overall[s] => SectorRating.overallBest,
          final time when time <= personal[s] => SectorRating.personalBest,
          _ => SectorRating.slower,
        },
    ];
  }

  int _lapOf(int driver, double t) {
    var lap = 0;
    for (final l in _laps[driver] ?? const <_TimedLap>[]) {
      if (l.start > t) break;
      lap = l.lap.lapNumber;
    }
    return lap;
  }

  RaceStint? _stintOf(int driver, int lap) {
    for (final s in _stints[driver] ?? const <RaceStint>[]) {
      if (lap >= s.lapStart && (s.lapEnd == null || lap <= s.lapEnd!)) {
        return s;
      }
    }
    return null;
  }

  /// Out of the race: no lap started for well over a lap before the leader
  /// finished.
  bool _retiredAt(int driver, double t) {
    if (t >= _finish) return false;
    final laps = _laps[driver];
    if (laps == null || laps.isEmpty) return true;
    return t - laps.last.start > 2.5 * _medianLap;
  }
}

class _TimedLap {
  _TimedLap(this.lap, this.start)
    : end = start + (lap.duration ?? double.infinity);

  final RaceLap lap;
  final double start;
  final double end;
}

/// Values that change at given times; [at] reads the latest by then.
class _Series<T> {
  final _times = <double>[];
  final _values = <T>[];

  void add(double t, T value) {
    _times.add(t);
    _values.add(value);
  }

  void sort() {
    final order = List.generate(_times.length, (i) => i)
      ..sort((a, b) => _times[a].compareTo(_times[b]));
    final times = [for (final i in order) _times[i]];
    final values = [for (final i in order) _values[i]];
    _times
      ..clear()
      ..addAll(times);
    _values
      ..clear()
      ..addAll(values);
  }

  /// The value set most recently at or before [t]; before the first, the
  /// first (e.g. the starting grid). Null when empty.
  T? at(double t) {
    if (_times.isEmpty) return null;
    var lo = 0, hi = _times.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_times[mid] <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return _values[math.max(0, lo - 1)];
  }
}
