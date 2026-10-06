import 'package:f1_scene/src/race/liveries.dart';
import 'package:f1_scene/src/race/race_models.dart';
import 'package:flutter_test/flutter_test.dart';

RaceDriver driver(String team, [int colour = 0x123456]) => RaceDriver(
  number: 1,
  acronym: 'TST',
  fullName: 'Test Driver',
  teamName: team,
  teamColour: colour,
);

void main() {
  test('each team gets its own scheme, by season where it changed', () {
    final redBull = Livery.of(driver('Red Bull Racing'), 2024);
    final juniors = Livery.of(driver('Racing Bulls'), 2025);
    expect(juniors, isNot(redBull));
    expect(Livery.of(driver('RB'), 2024), juniors);
    expect(
      Livery.of(driver('Haas F1 Team'), 2023),
      isNot(Livery.of(driver('Haas F1 Team'), 2024)),
    );
    // A team not listed is painted in OpenF1's team colour.
    final unknown = Livery.of(driver('Andretti', 0x2050A0), 2027);
    expect(unknown.upper, 0x2050A0);
    expect(unknown, Livery.fromColour(0x2050A0));
  });
}
