import 'package:f1_scene/src/race/race_models.dart';
import 'package:f1_scene/src/race/timing_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final epoch = DateTime.utc(2024, 3, 2, 15);
  DateTime at(double seconds) =>
      epoch.add(Duration(milliseconds: (seconds * 1000).round()));

  const drivers = [
    RaceDriver(
      number: 1,
      acronym: 'VER',
      fullName: '',
      teamName: '',
      teamColour: 0,
    ),
    RaceDriver(
      number: 16,
      acronym: 'LEC',
      fullName: '',
      teamName: '',
      teamColour: 0,
    ),
    RaceDriver(
      number: 44,
      acronym: 'HAM',
      fullName: '',
      teamName: '',
      teamColour: 0,
    ),
  ];

  /// Three laps each of 90 s from t = 100; HAM stops after lap 1.
  List<RaceLap> laps() => [
    for (final d in [1, 16])
      for (var n = 1; n <= 3; n++)
        RaceLap(
          driverNumber: d,
          lapNumber: n,
          start: at(100 + (n - 1) * 90 + (d == 16 ? 1.5 : 0)),
          duration: 90,
          isPitOutLap: false,
        ),
    RaceLap(
      driverNumber: 44,
      lapNumber: 1,
      start: at(103),
      duration: 91,
      isPitOutLap: false,
    ),
  ];

  final board = TimingBoard(
    epoch: epoch,
    drivers: drivers,
    laps: laps(),
    positions: [
      (driver: 1, date: at(0), position: 1),
      (driver: 16, date: at(0), position: 2),
      (driver: 44, date: at(0), position: 3),
      (driver: 16, date: at(150), position: 1),
      (driver: 1, date: at(150), position: 2),
    ],
    intervals: [
      (
        driver: 16,
        date: at(120),
        gap: const Gap.seconds(1.5),
        interval: const Gap.seconds(1.5),
      ),
      (driver: 44, date: at(120), gap: const Gap.laps(1), interval: null),
    ],
    stints: const [
      RaceStint(
        driverNumber: 1,
        lapStart: 1,
        lapEnd: 2,
        compound: 'SOFT',
        tyreAgeAtStart: 3,
      ),
      RaceStint(
        driverNumber: 1,
        lapStart: 3,
        lapEnd: null,
        compound: 'HARD',
        tyreAgeAtStart: 0,
      ),
    ],
  );

  test('orders by the latest position change', () {
    expect(board.standingsAt(140).map((r) => r.driver), [1, 16, 44]);
    expect(board.standingsAt(160).map((r) => r.driver), [16, 1, 44]);
  });

  test('shows no gaps before the start', () {
    expect(board.standingsAt(90).every((r) => r.gap == null), isTrue);
  });

  test('carries gaps, laps, tyres and pit flags', () {
    final rows = {
      for (final r in board.standingsAt(285, inPit: {16})) r.driver: r,
    };
    expect(rows[16]!.interval, const Gap.seconds(1.5));
    expect(rows[16]!.inPit, isTrue);
    expect(rows[44]!.gap!.label, '+1 LAP');
    expect(rows[1]!.lap, 3);
    expect(rows[1]!.compound, 'HARD');
    expect(rows[1]!.tyreAge, 0);
  });

  test('marks a car out once it stops starting laps', () {
    // HAM's only lap began at 103; by 360 that is well over 2.5 laps ago.
    final rows = board.standingsAt(360);
    expect(rows.last.driver, 44);
    expect(rows.last.retired, isTrue);
    // After the chequered flag (VER finishes lap 3 at 370) nobody is "out".
    expect(board.standingsAt(400).any((r) => r.retired), isFalse);
  });

  test('knows the lap, the last lap and the best so far', () {
    // VER's lap 2 ended at 280.
    final timing = board.driverAt(1, 285);
    expect(timing.lap, 3);
    expect(timing.lastLap!.lapNumber, 2);
    expect(board.driverAt(16, 285).bestLap, 90);
  });

  test('parses OpenF1 gaps', () {
    expect(Gap.parse(1.234)!.label, '+1.234');
    expect(Gap.parse('+2 LAPS')!.label, '+2 LAPS');
    expect(Gap.parse(null), isNull);
  });
}
