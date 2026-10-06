import 'package:flutter/material.dart';

import '../race/race_models.dart';
import '../race/race_replay.dart';
import '../race/timing_board.dart';
import 'hud.dart';

/// The running order at the playhead, broadcast style. Tapping a row
/// follows that driver.
class TimingTower extends StatefulWidget {
  const TimingTower({
    super.key,
    required this.replay,
    required this.followed,
    required this.onSelect,
  });

  final RaceReplay replay;
  final int? followed;
  final ValueChanged<int> onSelect;

  @override
  State<TimingTower> createState() => _TimingTowerState();
}

class _TimingTowerState extends State<TimingTower> {
  /// Gap to the leader instead of the interval to the car ahead.
  bool _showGap = false;

  /// Only the top of the order and the followed driver.
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drivers = {for (final d in widget.replay.drivers) d.number: d};
    return ValueListenableBuilder<List<TowerRow>>(
      valueListenable: widget.replay.standings,
      builder: (context, rows, _) {
        final lap = rows.fold(0, (m, r) => r.lap > m ? r.lap : m);
        return Panel(
          padding: 8,
          child: SizedBox(
            width: 214,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _collapsed = !_collapsed),
                      borderRadius: BorderRadius.circular(4),
                      child: Icon(
                        _collapsed ? Icons.expand_more : Icons.expand_less,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      lap == 0
                          ? 'FORMATION'
                          : 'LAP $lap/${widget.replay.lapCount}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    _HeaderToggle(
                      label: _showGap ? 'GAP' : 'INTERVAL',
                      onTap: () => setState(() => _showGap = !_showGap),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final (i, row) in rows.indexed)
                  if (!_collapsed || i < 5 || row.driver == widget.followed)
                    if (drivers[row.driver] case final driver?)
                      _TowerLine(
                        row: row,
                        driver: driver,
                        showGap: _showGap,
                        selected: row.driver == widget.followed,
                        onTap: () => widget.onSelect(row.driver),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderToggle extends StatelessWidget {
  const _HeaderToggle({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

class _TowerLine extends StatelessWidget {
  const _TowerLine({
    required this.row,
    required this.driver,
    required this.showGap,
    required this.selected,
    required this.onTap,
  });

  final TowerRow row;
  final RaceDriver driver;
  final bool showGap;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: row.retired ? theme.colorScheme.onSurfaceVariant : null,
    );
    final String timing;
    if (row.retired) {
      timing = 'OUT';
    } else if (row.inPit) {
      timing = 'PIT';
    } else if (row.position == 1) {
      timing = 'Leader';
    } else {
      timing = (showGap ? row.gap : row.interval)?.label ?? '';
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0x33FFFFFF) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                row.retired ? '' : '${row.position}',
                textAlign: TextAlign.right,
                style: style?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 3,
              height: 14,
              color: Color(0xFF000000 | driver.teamColour),
            ),
            const SizedBox(width: 6),
            Text(
              driver.acronym,
              style: style?.copyWith(fontWeight: FontWeight.w700),
            ),
            Expanded(
              child: Text(
                timing,
                textAlign: TextAlign.right,
                style: style?.copyWith(
                  color: row.inPit ? theme.colorScheme.primary : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TyreBadge(compound: row.retired ? null : row.compound),
          ],
        ),
      ),
    );
  }
}

/// A tyre compound as a coloured initial, the way broadcasts show it.
class TyreBadge extends StatelessWidget {
  const TyreBadge({super.key, required this.compound, this.size = 16});

  final String? compound;
  final double size;

  static const _colours = {
    'SOFT': Color(0xFFE8002D),
    'MEDIUM': Color(0xFFFFD12E),
    'HARD': Color(0xFFF0F0EC),
    'INTERMEDIATE': Color(0xFF43B02A),
    'WET': Color(0xFF0067AD),
  };

  @override
  Widget build(BuildContext context) {
    final compound = this.compound;
    if (compound == null) return SizedBox(width: size);
    final colour = _colours[compound] ?? Colors.grey;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colour, width: 2),
      ),
      child: Text(
        _colours.containsKey(compound) ? compound[0] : '?',
        style: TextStyle(
          color: colour,
          fontSize: size * 0.55,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
