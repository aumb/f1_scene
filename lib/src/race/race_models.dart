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
  });

  final int driverNumber;
  final int lapNumber;

  /// When the lap began, if timing recorded it.
  final DateTime? start;

  /// Lap time in seconds, if timing recorded it.
  final double? duration;
  final bool isPitOutLap;
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
