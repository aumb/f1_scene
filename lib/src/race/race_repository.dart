import 'openf1_client.dart';
import 'race_models.dart';

/// Raw position samples for one time window, all drivers, as parallel lists.
///
/// Coordinates are in OpenF1's circuit frame (decimeters, arbitrary rotation),
/// times in seconds since [epoch].
class LocationBatch {
  LocationBatch(this.epoch);

  final DateTime epoch;
  final samples = <int, ({List<double> t, List<double> x, List<double> y})>{};

  void add(int driver, double t, double x, double y) {
    final series = samples.putIfAbsent(
      driver,
      () => (t: <double>[], x: <double>[], y: <double>[]),
    );
    series.t.add(t);
    series.x.add(x);
    series.y.add(y);
  }
}

/// Fetches and parses race data from OpenF1, memoizing per-session lookups.
class RaceRepository {
  RaceRepository({OpenF1Client? client}) : _client = client ?? OpenF1Client();

  final OpenF1Client _client;
  final _racesByYear = <int, Future<List<RaceSession>>>{};

  /// Completed, non-cancelled races of [year], in calendar order.
  Future<List<RaceSession>> races(int year) =>
      _racesByYear[year] ??= _fetchRaces(year)
          .catchError((Object e, StackTrace s) {
            // Forget the failure so the next call retries.
            _racesByYear.remove(year);
            Error.throwWithStackTrace(e, s);
          });

  Future<List<RaceSession>> _fetchRaces(int year) async {
    final (sessions, meetings) = await (
      _client.get('sessions', {'year': year, 'session_name': 'Race'}),
      _client.get('meetings', {'year': year}),
    ).wait;
    final names = {
      for (final m in meetings)
        m['meeting_key'] as int: m['meeting_name'] as String,
    };
    final now = DateTime.now().toUtc();
    final races =
        [
            for (final s in sessions)
              if (s['is_cancelled'] != true)
                RaceSession(
                  sessionKey: s['session_key'] as int,
                  meetingName:
                      names[s['meeting_key']] ??
                      '${s['country_name']} Grand Prix',
                  circuitKey: s['circuit_key'] as int,
                  circuitShortName: s['circuit_short_name'] as String,
                  location: s['location'] as String,
                  year: s['year'] as int,
                  start: DateTime.parse(s['date_start'] as String),
                  end: DateTime.parse(s['date_end'] as String),
                ),
          ].where((r) => r.end.isBefore(now)).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return races;
  }

  Future<List<RaceDriver>> drivers(int sessionKey) async {
    final rows = await _client.get('drivers', {'session_key': sessionKey});
    return [
      for (final d in rows)
        RaceDriver(
          number: d['driver_number'] as int,
          acronym: d['name_acronym'] as String? ?? '${d['driver_number']}',
          fullName: d['full_name'] as String? ?? '',
          teamName: d['team_name'] as String? ?? '',
          teamColour:
              int.tryParse(d['team_colour'] as String? ?? '', radix: 16) ??
              0x9AA0A6,
        ),
    ]..sort((a, b) => a.number.compareTo(b.number));
  }

  Future<List<RaceLap>> laps(int sessionKey) async {
    final rows = await _client.get('laps', {'session_key': sessionKey});
    return [
      for (final l in rows)
        RaceLap(
          driverNumber: l['driver_number'] as int,
          lapNumber: l['lap_number'] as int,
          start: l['date_start'] == null
              ? null
              : DateTime.parse(l['date_start'] as String),
          duration: (l['lap_duration'] as num?)?.toDouble(),
          isPitOutLap: l['is_pit_out_lap'] as bool? ?? false,
        ),
    ];
  }

  /// Car positions in `[from, to)`, optionally for one [driver].
  Future<LocationBatch> locations(
    int sessionKey, {
    required DateTime epoch,
    required DateTime from,
    required DateTime to,
    int? driver,
  }) async {
    final rows = await _client.get('location', {
      'session_key': sessionKey,
      'driver_number': ?driver,
      'date>=': _timestamp(from),
      'date<': _timestamp(to),
    });
    final batch = LocationBatch(epoch);
    for (final r in rows) {
      final t = DateTime.parse(r['date'] as String).difference(epoch);
      batch.add(
        r['driver_number'] as int,
        t.inMicroseconds / 1e6,
        (r['x'] as num).toDouble(),
        (r['y'] as num).toDouble(),
      );
    }
    return batch;
  }

  /// OpenF1 treats offset-free timestamps as UTC.
  static String _timestamp(DateTime t) =>
      t.toUtc().toIso8601String().replaceFirst('Z', '');
}
