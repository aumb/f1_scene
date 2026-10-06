import 'package:flutter/material.dart';

/// Colours and type for the heads-up display: a dark, quiet frame that
/// leaves the colour to the cars and the track.
abstract final class Hud {
  static const background = Color(0xFF0A0B0D);
  static const rail = Color(0xFF111215);
  static const map = Color(0xFF0D0E11);
  static const bar = Color(0xFF0F1013);
  static const line = Color(0xFF1F2126);
  static const control = Color(0xE6131417);
  static const selected = Color(0xFF26272C);
  static const text = Color(0xFFE6E7EA);
  static const muted = Color(0xFF80858E);
  static const faint = Color(0xFF4E525A);

  /// Opaque [Color] from an sRGB `0xRRGGBB` value, such as a team colour.
  static Color rgb(int rgb) => Color(0xFF000000 | rgb);

  /// Shown for a value that isn't known (yet).
  static const unknown = '—';

  /// Small spaced capitals over a column or a value.
  static const label = TextStyle(
    fontSize: 10.5,
    letterSpacing: 1.3,
    color: muted,
    fontWeight: FontWeight.w500,
  );

  /// Figures that line up in columns.
  static TextStyle figures(
    double size, {
    Color color = text,
    FontWeight weight = FontWeight.w500,
  }) => TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: 0.3,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// A tyre compound's broadcast colour.
  static Color tyre(String? compound) => switch (compound) {
    'SOFT' => const Color(0xFFFF3B4A),
    'MEDIUM' => const Color(0xFFFFD12E),
    'HARD' => const Color(0xFFD9DBDF),
    'INTERMEDIATE' => const Color(0xFF43B02A),
    'WET' => const Color(0xFF2D8CFF),
    _ => muted,
  };

  /// `1:15.305`, or [unknown].
  static String lapTime(double? seconds) {
    if (seconds == null || seconds.isInfinite) return unknown;
    final m = seconds ~/ 60;
    final s = seconds - m * 60;
    return '$m:${s.toStringAsFixed(3).padLeft(6, '0')}';
  }
}

/// Credit for the data on screen, with every source and licence a click
/// away.
class Attribution extends StatelessWidget {
  const Attribution({super.key});

  static const _sources =
      'Unofficial fan project, not affiliated with Formula 1.\n\n'
      'Race data: OpenF1 (CC BY-NC-SA 4.0).\n'
      'Track data: bacinger/f1-circuits (MIT), F1TrackViewer (MIT), '
      'TUMFTM racetrack-database (LGPL-3.0), OpenTopoData (CC-BY 4.0).\n'
      'Scenery: © OpenStreetMap contributors (ODbL), Open-Meteo.';

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 10.5, color: Hud.muted, height: 1.4);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(
            text: 'Unofficial fan project · © OpenStreetMap contributors · OpenF1 · ',
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: Hud.rail,
                  title: const Text('Sources', style: TextStyle(fontSize: 16)),
                  content: const Text(
                    _sources,
                    style: TextStyle(fontSize: 13, color: Hud.muted),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              child: const MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  'Sources',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Hud.text,
                    decoration: TextDecoration.underline,
                    decorationColor: Hud.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
