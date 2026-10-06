import 'dart:math' as math;
import 'dart:typed_data';

import '../data/data_cache.dart';

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
    final series = samples[driver] ??= (
      t: <double>[],
      x: <double>[],
      y: <double>[],
    );
    series.t.add(t);
    series.x.add(x);
    series.y.add(y);
  }

  static const _magic = 0x46314c42; // "F1LB"
  static const _version = 1;

  /// A compact binary form for the cache: ~16 bytes a sample against ~140
  /// as OpenF1's JSON, and far quicker to read back.
  Uint8List toBytes() {
    final drivers = samples.entries.toList();
    final count = drivers.fold(0, (n, d) => n + d.value.t.length);
    final data = ByteData(20 + drivers.length * 8 + count * 16);
    var at = 0;
    void u32(int v) => data.setUint32((at += 4) - 4, v, Endian.little);
    u32(_magic);
    u32(_version);
    data.setFloat64(at, epoch.microsecondsSinceEpoch / 1e6, Endian.little);
    at += 8;
    u32(drivers.length);
    for (final MapEntry(key: driver, value: s) in drivers) {
      u32(driver);
      u32(s.t.length);
    }
    for (final MapEntry(value: s) in drivers) {
      for (var i = 0; i < s.t.length; i++) {
        data
          ..setFloat64(at, s.t[i], Endian.little)
          ..setFloat32(at + 8, s.x[i], Endian.little)
          ..setFloat32(at + 12, s.y[i], Endian.little);
        at += 16;
      }
    }
    return data.buffer.asUint8List();
  }

  /// Reads [toBytes] back with times relative to [epoch], or null when
  /// [bytes] are not in that form.
  static LocationBatch? fromBytes(Uint8List bytes, DateTime epoch) {
    if (bytes.length < 20) return null;
    final data = ByteData.sublistView(bytes);
    var at = 0;
    int u32() => data.getUint32((at += 4) - 4, Endian.little);
    if (u32() != _magic || u32() != _version) return null;
    final shift =
        data.getFloat64(at, Endian.little) - epoch.microsecondsSinceEpoch / 1e6;
    at += 8;
    final drivers = [for (var n = u32(), i = 0; i < n; i++) (u32(), u32())];
    final batch = LocationBatch(epoch);
    for (final (driver, count) in drivers) {
      final t = List<double>.filled(count, 0), x = [...t], y = [...t];
      for (var i = 0; i < count; i++) {
        t[i] = data.getFloat64(at, Endian.little) + shift;
        x[i] = data.getFloat32(at + 8, Endian.little);
        y[i] = data.getFloat32(at + 12, Endian.little);
        at += 16;
      }
      batch.samples[driver] = (t: t, x: x, y: y);
    }
    return batch;
  }
}

/// Lets the event loop run, so a frame can be drawn, before continuing a
/// long piece of work.
Future<void> yieldToFrames() => Future<void>.delayed(Duration.zero);

/// Fetches and parses race data from OpenF1, memoizing per-session lookups.
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
                  circuitShortName: s['circuit_short_name'] as String,
                  location: s['location'] as String,
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
          segments: [
            for (final k in [
              'segments_sector_1',
              'segments_sector_2',
              'segments_sector_3',
            ])
              for (final code in (l[k] as List?) ?? const [])
                MiniSector.fromCode(code as int?),
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
            laneDuration: (p['lane_duration'] ?? p['pit_duration']) == null
                ? null
                : ((p['lane_duration'] ?? p['pit_duration']) as num).toDouble(),
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
      // A chunk is ~25k rows, read on the thread that draws frames; let a
      // frame through every few thousand rather than stall playback.
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

  /// Seconds since the Unix epoch of an OpenF1 timestamp such as
  /// `2024-03-02T15:20:00.138000+00:00`.
  ///
  /// Position chunks carry ~25k of these; reading the fixed layout directly
  /// is several times faster than `DateTime.parse` on the web. Anything not
  /// in that layout (an offset other than UTC) falls back to it.
  static double isoSeconds(String s) {
    final plusZero = s.length >= 25 && s.endsWith('+00:00');
    if (!plusZero && !s.endsWith('Z')) {
      return DateTime.parse(s).microsecondsSinceEpoch / 1e6;
    }
    int digits(int from, int to) {
      var v = 0;
      for (var i = from; i < to; i++) {
        v = v * 10 + s.codeUnitAt(i) - 48;
      }
      return v;
    }

    final year = digits(0, 4), month = digits(5, 7), day = digits(8, 10);
    final seconds =
        digits(11, 13) * 3600 + digits(14, 16) * 60 + digits(17, 19);
    var fraction = 0.0;
    final end = plusZero ? s.length - 6 : s.length - 1;
    if (end > 20 && s.codeUnitAt(19) == 46) {
      fraction = digits(20, end) / math.pow(10, end - 20);
    }
    return _daysFromCivil(year, month, day) * 86400.0 + seconds + fraction;
  }

  /// Days since 1970-01-01 of a proleptic Gregorian date (H. Hinnant).
  static int _daysFromCivil(int y, int m, int d) {
    final yy = m <= 2 ? y - 1 : y;
    final era = (yy >= 0 ? yy : yy - 399) ~/ 400;
    final yoe = yy - era * 400;
    final doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) ~/ 5 + d - 1;
    final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
    return era * 146097 + doe - 719468;
  }

  /// OpenF1 treats offset-free timestamps as UTC.
  static String _timestamp(DateTime t) =>
      t.toUtc().toIso8601String().replaceFirst('Z', '');
}
