import 'package:flutter/material.dart';

import '../data/circuit.dart';
import '../geometry/track_mesh.dart';
import '../race/race_models.dart';

/// Translucent card the overlay widgets sit on.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = 16});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC111318),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
  }
}

/// The race (or, before one loads, the circuit) being shown.
class CircuitCard extends StatelessWidget {
  const CircuitCard({super.key, required this.circuit, this.race});

  final Circuit circuit;
  final RaceSession? race;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = circuit.summary;
    final race = this.race;
    final (lo, hi) = circuit.elevationRange;
    return Panel(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (race == null
                      ? summary.country
                      : '${race.year} · ${summary.country}')
                  .toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              race?.meetingName ?? summary.name,
              style: theme.textTheme.titleLarge,
            ),
            if (race != null)
              Text(
                summary.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _Stat(
                  label: 'Length',
                  value: '${(circuit.lapLength / 1000).toStringAsFixed(3)} km',
                ),
                _Stat(
                  label: 'Elevation range',
                  value: '${(hi - lo).toStringAsFixed(0)} m',
                ),
                _Stat(
                  label: 'Width',
                  value: circuit.hasMeasuredWidth
                      ? 'measured'
                      : '${Circuit.defaultWidth.toStringAsFixed(0)} m (est.)',
                ),
              ],
            ),
            if (circuit.sectors.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectorLegend(circuit: circuit),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectorLegend extends StatelessWidget {
  const _SectorLegend({required this.circuit});

  final Circuit circuit;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 14,
      children: [
        for (final sector in circuit.sectors)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(
                    0xFF000000 |
                        TrackMeshBuilder.sectorColors[(sector.number - 1) %
                            TrackMeshBuilder.sectorColors.length],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'S${sector.number} '
                '${((sector.toDistance - sector.fromDistance) / 1000).toStringAsFixed(2)} km',
                style: style,
              ),
            ],
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

/// Picks how the driving surface is tinted.
class ColorModeMenu extends StatelessWidget {
  const ColorModeMenu({super.key, required this.mode, required this.onChanged});

  final TrackColorMode mode;
  final ValueChanged<TrackColorMode> onChanged;

  static const _labels = {
    TrackColorMode.sectors: 'Sectors',
    TrackColorMode.elevation: 'Elevation',
    TrackColorMode.asphalt: 'Asphalt',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TrackColorMode>(
      tooltip: 'Track colors',
      initialValue: mode,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final MapEntry(key: value, value: label) in _labels.entries)
          CheckedPopupMenuItem(
            value: value,
            checked: value == mode,
            child: Text(label),
          ),
      ],
      child: IgnorePointer(
        child: IconButton.filledTonal(
          onPressed: () {},
          icon: const Icon(Icons.palette_outlined),
        ),
      ),
    );
  }
}

class Attribution extends StatelessWidget {
  const Attribution({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Unofficial fan project, not affiliated with Formula 1. '
      'Race data: OpenF1 (CC BY-NC-SA 4.0). '
      'Track data: bacinger/f1-circuits (MIT), F1TrackViewer (MIT), '
      'TUMFTM racetrack-database (LGPL-3.0), OpenTopoData (CC-BY 4.0).',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }
}
