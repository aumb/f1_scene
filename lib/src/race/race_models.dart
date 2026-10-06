/// A race session from OpenF1, joined with its meeting name.
class RaceSession {
  const RaceSession({
    required this.sessionKey,
    required this.meetingName,
    required this.circuitKey,
    required this.circuitShortName,
    required this.location,
    required this.year,
    required this.start,
    required this.end,
  });

  final int sessionKey;

  /// e.g. "Bahrain Grand Prix".
  final String meetingName;

  /// OpenF1's stable circuit id, mapped to vendored layouts in `venues.dart`.
  final int circuitKey;
  final String circuitShortName;
  final String location;
  final int year;

  /// Scheduled session window (UTC).
  final DateTime start;
  final DateTime end;
}

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

class RaceLap {
  const RaceLap({
    required this.driverNumber,
    required this.lapNumber,
    required this.start,
    required this.duration,
    required this.isPitOutLap,
    this.sectors = const [null, null, null],
    this.segments = const [],
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

  /// Mini-sector results across the lap, in order (see [MiniSector]).
  final List<MiniSector> segments;
}

/// How a car did through one mini-sector, as F1 timing colours it.
enum MiniSector {
  none,

  /// Slower than the driver's best (yellow).
  slower,

  /// The driver's personal best (green).
  personalBest,

  /// The fastest of anyone (purple).
  overallBest,

  /// Driving through the pit lane.
  pitLane;

  /// Decodes OpenF1's segment status codes.
  static MiniSector fromCode(int? code) => switch (code) {
    2048 => slower,
    2049 => personalBest,
    2051 => overallBest,
    2064 => pitLane,
    _ => none,
  };
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

class RacePitStop {
  const RacePitStop({
    required this.driverNumber,
    required this.lapNumber,
    required this.date,
    required this.laneDuration,
  });

  final int driverNumber;
  final int lapNumber;

  /// When the car entered the pit lane.
  final DateTime date;

  /// Seconds from pit entry to pit exit, if timing recorded it.
  final double? laneDuration;
}
