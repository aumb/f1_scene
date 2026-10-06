import 'race_models.dart';

/// A team's colour scheme, as painted on the car's parts (sRGB `0xRRGGBB`).
///
/// Only colours: team liveries' artwork and sponsor logos are trademarks,
/// so they stay off the car. The schemes are approximations of each car's
/// look; fix one by editing [_schemes].
class Livery {
  const Livery({
    required this.upper,
    required this.lower,
    required this.nose,
    required this.engineCover,
    required this.wings,
    required this.number,
  });

  /// Bodywork above and below the dividing line along the car's flanks.
  final int upper;
  final int lower;
  final int nose;
  final int engineCover;
  final int wings;

  /// The car number's fill; it gets a contrasting outline.
  final int number;

  @override
  bool operator ==(Object other) =>
      other is Livery &&
      other.upper == upper &&
      other.lower == lower &&
      other.nose == nose &&
      other.engineCover == engineCover &&
      other.wings == wings &&
      other.number == number;

  @override
  int get hashCode =>
      Object.hash(upper, lower, nose, engineCover, wings, number);

  /// [driver]'s team's scheme in [year], or one built from the team colour
  /// OpenF1 gives when the team isn't listed.
  static Livery of(RaceDriver driver, int year) {
    final team = driver.teamName.toLowerCase();
    for (final (match, years, livery) in _schemes) {
      if (match(team) && years.contains(year)) return livery;
    }
    return Livery.fromColour(driver.teamColour);
  }

  /// A plain scheme in [colour], darker underneath.
  factory Livery.fromColour(int colour) {
    final dark = _scale(colour, 0.35);
    return Livery(
      upper: colour,
      lower: dark,
      nose: colour,
      engineCover: colour,
      wings: dark,
      number: _luminance(colour) > 0.6 ? 0x16181B : 0xFFFFFF,
    );
  }

  static int _scale(int rgb, double f) {
    int c(int shift) => (((rgb >> shift) & 0xff) * f).round();
    return c(16) << 16 | c(8) << 8 | c(0);
  }

  static double _luminance(int rgb) =>
      (0.2126 * ((rgb >> 16) & 0xff) +
          0.7152 * ((rgb >> 8) & 0xff) +
          0.0722 * (rgb & 0xff)) /
      255;
}

const _all = {2023, 2024, 2025, 2026};

bool Function(String) _named(String name) =>
    (team) => team.contains(name);

/// Teams by (name match, seasons, scheme). OpenF1's team names: Red Bull
/// Racing, Ferrari, Mercedes, McLaren, Aston Martin, Alpine, Williams,
/// AlphaTauri (2023), RB (2024), Racing Bulls (2025-), Alfa Romeo (2023),
/// Kick Sauber (2024-25), Audi (2026-), Haas F1 Team, Cadillac (2026-).
final _schemes = <(bool Function(String), Set<int>, Livery)>[
  (
    // Before "red bull": Racing Bulls must not match it.
    (team) => team == 'rb' || team.contains('racing bulls'),
    _all,
    const Livery(
      upper: 0xF2F3F5,
      lower: 0x1634CC,
      nose: 0xF2F3F5,
      engineCover: 0x1634CC,
      wings: 0xE10600,
      number: 0x1634CC,
    ),
  ),
  (
    _named('red bull'),
    _all,
    const Livery(
      upper: 0x1E2B52,
      lower: 0x121A33,
      nose: 0x1E2B52,
      engineCover: 0x1E2B52,
      wings: 0xD8202F,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('ferrari'),
    _all,
    const Livery(
      upper: 0xDC0000,
      lower: 0x1C1C1E,
      nose: 0xDC0000,
      engineCover: 0xDC0000,
      wings: 0xDC0000,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('mercedes'),
    _all,
    const Livery(
      upper: 0x16181C,
      lower: 0x16181C,
      nose: 0xBFC4CA,
      engineCover: 0x16181C,
      wings: 0x00A19C,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('mclaren'),
    _all,
    const Livery(
      upper: 0xFF8000,
      lower: 0x1E2124,
      nose: 0xFF8000,
      engineCover: 0xFF8000,
      wings: 0x1E2124,
      number: 0x16181B,
    ),
  ),
  (
    _named('aston martin'),
    _all,
    const Livery(
      upper: 0x00634F,
      lower: 0x0D1E1B,
      nose: 0x00634F,
      engineCover: 0x00634F,
      wings: 0xCEDC00,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('alpine'),
    _all,
    const Livery(
      upper: 0x0078C1,
      lower: 0x14161A,
      nose: 0xFF87BC,
      engineCover: 0x0078C1,
      wings: 0xFF87BC,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('williams'),
    _all,
    const Livery(
      upper: 0x0A2A66,
      lower: 0x061A40,
      nose: 0x00A3E0,
      engineCover: 0x0A2A66,
      wings: 0x1868DB,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('alphatauri'),
    _all,
    const Livery(
      upper: 0x13294B,
      lower: 0xEDEDED,
      nose: 0xEDEDED,
      engineCover: 0x13294B,
      wings: 0xE10600,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('alfa romeo'),
    _all,
    const Livery(
      upper: 0x8F0B1A,
      lower: 0x16181B,
      nose: 0xEDEDED,
      engineCover: 0x8F0B1A,
      wings: 0x8F0B1A,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('sauber'),
    _all,
    const Livery(
      upper: 0x16181B,
      lower: 0x00D400,
      nose: 0x16181B,
      engineCover: 0x00D400,
      wings: 0x00D400,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('audi'),
    _all,
    const Livery(
      upper: 0xB7BCC2,
      lower: 0x16181B,
      nose: 0xB7BCC2,
      engineCover: 0xF50537,
      wings: 0xF50537,
      number: 0x16181B,
    ),
  ),
  (
    _named('haas'),
    {2023},
    const Livery(
      upper: 0x1B1C1E,
      lower: 0xEDEDED,
      nose: 0xE10600,
      engineCover: 0x1B1C1E,
      wings: 0xE10600,
      number: 0xFFFFFF,
    ),
  ),
  (
    _named('haas'),
    _all,
    const Livery(
      upper: 0xF2F2F2,
      lower: 0x1B1C1E,
      nose: 0xF2F2F2,
      engineCover: 0xF2F2F2,
      wings: 0xE10600,
      number: 0x1B1C1E,
    ),
  ),
  (
    _named('cadillac'),
    _all,
    const Livery(
      upper: 0x16181B,
      lower: 0xEDEDED,
      nose: 0xEDEDED,
      engineCover: 0x16181B,
      wings: 0x16181B,
      number: 0xFFFFFF,
    ),
  ),
];
