/// A race session from OpenF1, joined with its meeting name.
class RaceSession {
  const RaceSession({
    required this.sessionKey,
    required this.meetingName,
    required this.circuitKey,
    required this.year,
    required this.start,
    required this.end,
  });

  final int sessionKey;

  /// e.g. "Bahrain Grand Prix".
  final String meetingName;

  /// OpenF1's stable circuit id, mapped to vendored layouts in `venues.dart`.
  final int circuitKey;
  final int year;

  /// Scheduled session window (UTC). Replay times are seconds from [start].
  final DateTime start;
  final DateTime end;

  /// Seconds from [start] to [t].
  double secondsAt(DateTime t) => t.difference(start).inMicroseconds / 1e6;

  /// The moment [seconds] after [start].
  DateTime timeAt(double seconds) =>
      start.add(Duration(microseconds: (seconds * 1e6).round()));
}

/// A driver in one session, with the team they drove for in it.
class RaceDriver {
  const RaceDriver({
    required this.number,
    required this.acronym,
    required this.fullName,
    required this.teamName,
    required this.teamColour,
  });

  final int number;

  /// Three-letter code, e.g. "VER".
  final String acronym;
  final String fullName;
  final String teamName;

  /// sRGB `0xRRGGBB`.
  final int teamColour;
}

/// One driver's lap as the timing recorded it.
class RaceLap {
  const RaceLap({
    required this.driverNumber,
    required this.lapNumber,
    required this.start,
    required this.duration,
    required this.isPitOutLap,
    this.sectors = const [null, null, null],
  });

  final int driverNumber;
  final int lapNumber;

  /// When the lap began, if timing recorded it.
  final DateTime? start;

  /// Lap time in seconds, if timing recorded it.
  final double? duration;
  final bool isPitOutLap;

  /// Sector times in seconds; null where timing missed one.
  final List<double?> sectors;
}

/// A time gap that may be measured in laps instead of seconds.
class Gap {
  const Gap.seconds(double this.seconds) : laps = null;
  const Gap.laps(int this.laps) : seconds = null;

  final double? seconds;
  final int? laps;

  /// Parses OpenF1's `gap_to_leader` / `interval`: a number of seconds, or
  /// text like "+1 LAP". Null when unknown.
  static Gap? parse(Object? value) {
    if (value is num) return Gap.seconds(value.toDouble());
    if (value is String) {
      final laps = int.tryParse(
        RegExp(r'\d+').firstMatch(value)?.group(0) ?? '',
      );
      if (laps != null) return Gap.laps(laps);
    }
    return null;
  }

  /// "+1.2", "+1L": for narrow columns.
  String get shortLabel => '+$_short';

  /// "−1.2", "−1L": the same gap seen from the car ahead.
  String get shortLabelBehind => '−$_short';

  String get _short {
    final laps = this.laps;
    return laps != null ? '${laps}L' : seconds!.toStringAsFixed(1);
  }

  /// "+1.234", "+1 LAP", "+2 LAPS".
  String get label {
    final laps = this.laps;
    if (laps != null) return '+$laps LAP${laps == 1 ? '' : 'S'}';
    return '+${seconds!.toStringAsFixed(3)}';
  }

  @override
  bool operator ==(Object other) =>
      other is Gap && other.seconds == seconds && other.laps == laps;

  @override
  int get hashCode => Object.hash(seconds, laps);
}

class RaceStint {
  const RaceStint({
    required this.driverNumber,
    required this.lapStart,
    required this.lapEnd,
    required this.compound,
    required this.tyreAgeAtStart,
  });

  final int driverNumber;
  final int lapStart;

  /// Null while the stint was still running when data ended.
  final int? lapEnd;

  /// "SOFT", "MEDIUM", "HARD", "INTERMEDIATE", "WET" or "UNKNOWN".
  final String compound;
  final int tyreAgeAtStart;
}

/// A pit stop: when, on which lap, and how long the car spent in the lane.
class RacePitStop {
  const RacePitStop({
    required this.driverNumber,
    required this.lapNumber,
    required this.date,
    required this.laneDuration,
  });

  final int driverNumber;
  final int lapNumber;

  /// OpenF1's timestamp for the stop. Not pit entry: the car can already
  /// be in its box ~10 s before it (see `tracePitLane`).
  final DateTime date;

  /// Seconds from pit entry to pit exit, if timing recorded it.
  final double? laneDuration;
}
