import 'package:flutter/material.dart';

import '../race/race_models.dart';
import '../race/race_replay.dart';
import '../race/timing_board.dart';
import 'hud.dart';
import 'timing_tower.dart';

/// Timing for the followed driver: position, laps, sectors, tyres.
class DriverCard extends StatelessWidget {
  const DriverCard({super.key, required this.replay, required this.driver});

  final RaceReplay replay;
  final int driver;

  static const _ratingColours = {
    SectorRating.overallBest: Color(0xFFB36BFF),
    SectorRating.personalBest: Color(0xFF2BD96A),
    SectorRating.slower: Color(0xFFFFD12E),
    SectorRating.none: Color(0xFF5A5F6B),
  };

  static const _miniColours = {
    MiniSector.overallBest: Color(0xFFB36BFF),
    MiniSector.personalBest: Color(0xFF2BD96A),
    MiniSector.slower: Color(0xFFFFD12E),
    MiniSector.pitLane: Color(0xFF3B82F6),
    MiniSector.none: Color(0xFF3A3E46),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = replay.drivers.where((d) => d.number == driver).firstOrNull;
    if (info == null) return const SizedBox.shrink();
    // The standings refresh a few times a second; that is often enough.
    return ValueListenableBuilder<List<TowerRow>>(
      valueListenable: replay.standings,
      builder: (context, rows, _) {
        final row = rows.where((r) => r.driver == driver).firstOrNull;
        final timing = replay.timing.driverAt(driver, replay.time.value);
        final last = timing.lastLap;
        final labelStyle = theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        final valueStyle = theme.textTheme.titleSmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return Panel(
          padding: 12,
          child: SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 36,
                      color: Color(0xFF000000 | info.teamColour),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.fullName.isEmpty
                                ? info.acronym
                                : info.fullName,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(info.teamName, style: labelStyle),
                        ],
                      ),
                    ),
                    Text(
                      row == null || row.retired ? 'OUT' : 'P${row.position}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: timing.lap == 0
                            ? 'Grid'
                            : 'Lap ${timing.lap}/${replay.lapCount}',
                        value: _lapTime(timing.lapElapsed),
                        style: valueStyle,
                        labelStyle: labelStyle,
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Last',
                        value: _lapTime(last?.duration),
                        style: valueStyle,
                        labelStyle: labelStyle,
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Best',
                        value: _lapTime(timing.bestLap),
                        style: valueStyle,
                        labelStyle: labelStyle,
                      ),
                    ),
                  ],
                ),
                if (last != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var s = 0; s < 3; s++) ...[
                        if (s > 0) const SizedBox(width: 6),
                        Expanded(
                          child: _SectorChip(
                            label: 'S${s + 1}',
                            time: last.sectors[s],
                            colour:
                                _ratingColours[s < timing.lastSectors.length
                                    ? timing.lastSectors[s]
                                    : SectorRating.none]!,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (last.segments.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final m in last.segments)
                          Expanded(
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              color: _miniColours[m],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
                if (row?.compound != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TyreBadge(compound: row!.compound, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${_titleCase(row.compound!)} · '
                        '${row.tyreAge} lap${row.tyreAge == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (row.inPit) ...[
                        const Spacer(),
                        Text(
                          'IN PIT',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// `1:32.456`, or a dash when unknown.
  static String _lapTime(double? seconds) {
    if (seconds == null || seconds.isInfinite) return '–';
    final m = seconds ~/ 60;
    final s = seconds - m * 60;
    return '$m:${s.toStringAsFixed(3).padLeft(6, '0')}';
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.style,
    required this.labelStyle,
  });

  final String label;
  final String value;
  final TextStyle? style;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        Text(value, style: style),
      ],
    );
  }
}

class _SectorChip extends StatelessWidget {
  const _SectorChip({
    required this.label,
    required this.time,
    required this.colour,
  });

  final String label;
  final double? time;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colour, width: 3)),
        color: const Color(0x14FFFFFF),
      ),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const Spacer(),
          Text(
            time == null ? '–' : time!.toStringAsFixed(3),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colour,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
