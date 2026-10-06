import '../data/data_cache.dart';
import 'location_batch.dart';
import 'openf1_client.dart';
import 'race_models.dart';

/// Fetches race data from OpenF1 and parses it into the app's models.
///
/// The client caches every response ([DataCache]); this class decides how
/// long each may be kept, and remembers each year's calendar.
class RaceRepository {
  RaceRepository({OpenF1Client? client}) : _client = client ?? OpenF1Client();

  final OpenF1Client _client;
  final _racesByYear = <int, Future<List<RaceSession>>>{};

  /// Every race listed so far, to tell which have settled.
  final _sessions = <int, RaceSession>{};

  /// How long [sessionKey]'s data may be kept: on the device once the race
  /// is a day old (OpenF1 can still be filling in or correcting it before
  /// that), else for this run only.
  Keep _keepFor(int sessionKey) {
    final session = _sessions[sessionKey];
    final settled = DateTime.now().toUtc().subtract(const Duration(days: 1));
    return session != null && session.end.isBefore(settled)
        ? Keep.device
        : Keep.session;
  }

  /// Completed, non-cancelled races of [year], in calendar order.
  Future<List<RaceSession>> races(int year) =>
      _racesByYear[year] ??= _fetchRaces(year)
          .catchError((Object e, StackTrace s) {
            // Forget the failure so the next call retries.
            _racesByYear.remove(year);
            Error.throwWithStackTrace(e, s);
          });

  Future<List<RaceSession>> _fetchRaces(int year) async {
    // Past seasons' calendars are final; this one's grows race by race.
    final keep = year < DateTime.now().year ? Keep.device : Keep.session;
    final (sessions, meetings) = await (
      _client.get('sessions', {
        'year': year,
        'session_name': 'Race',
      }, keep: keep),
      _client.get('meetings', {'year': year}, keep: keep),
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
                  year: s['year'] as int,
                  start: DateTime.parse(s['date_start'] as String),
                  end: DateTime.parse(s['date_end'] as String),
                ),
          ].where((r) => r.end.isBefore(now)).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    for (final race in races) {
      _sessions[race.sessionKey] = race;
    }
    return races;
  }

  Future<List<RaceDriver>> drivers(int sessionKey) async {
    final rows = await _client.get('drivers', {
      'session_key': sessionKey,
    }, keep: _keepFor(sessionKey));
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
    final rows = await _client.get('laps', {
      'session_key': sessionKey,
    }, keep: _keepFor(sessionKey));
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
          sectors: [
            for (final k in [
              'duration_sector_1',
              'duration_sector_2',
              'duration_sector_3',
            ])
              (l[k] as num?)?.toDouble(),
          ],
        ),
    ];
  }

  /// Running-order changes: whenever a driver's position changed.
  Future<List<({int driver, DateTime date, int position})>> positions(
    int sessionKey,
  ) async {
    final rows = await _client.get('position', {
      'session_key': sessionKey,
    }, keep: _keepFor(sessionKey));
    return [
      for (final r in rows)
        (
          driver: r['driver_number'] as int,
          date: DateTime.parse(r['date'] as String),
          position: r['position'] as int,
        ),
    ];
  }

  /// Gap to the leader and to the car ahead, sampled every few seconds.
  Future<List<({int driver, DateTime date, Gap? gap, Gap? interval})>>
  intervals(int sessionKey) async {
    final rows = await _client.get('intervals', {
      'session_key': sessionKey,
    }, keep: _keepFor(sessionKey));
    return [
      for (final r in rows)
        (
          driver: r['driver_number'] as int,
          date: DateTime.parse(r['date'] as String),
          gap: Gap.parse(r['gap_to_leader']),
          interval: Gap.parse(r['interval']),
        ),
    ];
  }

  Future<List<RaceStint>> stints(int sessionKey) async {
    final rows = await _client.get('stints', {
      'session_key': sessionKey,
    }, keep: _keepFor(sessionKey));
    return [
      for (final r in rows)
        if (r['lap_start'] != null)
          RaceStint(
            driverNumber: r['driver_number'] as int,
            lapStart: r['lap_start'] as int,
            lapEnd: r['lap_end'] as int?,
            compound: r['compound'] as String? ?? 'UNKNOWN',
            tyreAgeAtStart: r['tyre_age_at_start'] as int? ?? 0,
          ),
    ];
  }

  /// When each car had DRS open within `[from, to)`, as seconds since
  /// [epoch] per driver. OpenF1 codes an open flap as 10, 12 or 14; seasons
  /// without DRS (2026) report null and yield nothing.
  ///
  /// Only open samples are asked for: the flap is open a few percent of the
  /// time, so that is a few hundred rows a minute rather than thousands.
  Future<Map<int, List<double>>> drsOpen(
    int sessionKey, {
    required DateTime epoch,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client.get('car_data', {
      'session_key': sessionKey,
      'date>=': _timestamp(from),
      'date<': _timestamp(to),
      'drs>=': 10,
    }, keep: _keepFor(sessionKey));
    final open = <int, List<double>>{};
    final origin = epoch.microsecondsSinceEpoch / 1e6;
    for (final r in rows) {
      if (const {10, 12, 14}.contains(r['drs'])) {
        open
            .putIfAbsent(r['driver_number'] as int, () => [])
            .add(isoSeconds(r['date'] as String) - origin);
      }
    }
    return open;
  }

  Future<List<RacePitStop>> pitStops(int sessionKey) async {
    final rows = await _client.get('pit', {
      'session_key': sessionKey,
    }, keep: _keepFor(sessionKey));
    return [
      for (final p in rows)
        if (p['date'] != null)
          RacePitStop(
            driverNumber: p['driver_number'] as int,
            lapNumber: p['lap_number'] as int? ?? 0,
            date: DateTime.parse(p['date'] as String),
            // pit_duration is the older name for the same value.
            laneDuration: ((p['lane_duration'] ?? p['pit_duration']) as num?)
                ?.toDouble(),
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
    final filters = <String, Object>{
      'session_key': sessionKey,
      'driver_number': ?driver,
      'date>=': _timestamp(from),
      'date<': _timestamp(to),
    };
    // Kept in binary rather than as OpenF1's JSON: a race's worth is ~8 MB
    // instead of ~80.
    final key = '${_client.uriFor('location', filters)}#binary';
    final cached = await _client.cache.read(key);
    if (cached != null) {
      final batch = LocationBatch.fromBytes(cached, epoch);
      if (batch != null) return batch;
    }
    final rows = await _client.get('location', filters, keep: Keep.nothing);
    final batch = LocationBatch(epoch);
    final origin = epoch.microsecondsSinceEpoch / 1e6;
    for (var i = 0; i < rows.length; i++) {
      // A chunk is ~25k rows, converted on the thread that draws frames; let
      // a frame through every few thousand rather than stall playback. (The
      // JSON was decoded in one go by the client.)
      if (i > 0 && i % _rowsPerSlice == 0) await yieldToFrames();
      final r = rows[i];
      batch.add(
        r['driver_number'] as int,
        isoSeconds(r['date'] as String) - origin,
        (r['x'] as num).toDouble(),
        (r['y'] as num).toDouble(),
      );
    }
    await _client.cache.write(key, batch.toBytes(), _keepFor(sessionKey));
    return batch;
  }

  static const _rowsPerSlice = 4000;

  /// OpenF1 treats offset-free timestamps as UTC.
  static String _timestamp(DateTime t) =>
      t.toUtc().toIso8601String().replaceFirst('Z', '');
}
