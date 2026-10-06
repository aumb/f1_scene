import 'package:flutter/material.dart';

import '../race/race_models.dart';
import '../race/race_replay.dart';
import '../race/timing_board.dart';
import '../race/venues.dart';
import 'hud_style.dart';

/// The docked rail (beside the map, or under it on a phone): which race,
/// the running order, and the followed driver. The map gets everything
/// else.
class RaceRail extends StatelessWidget {
  const RaceRail({
    super.key,
    required this.seasons,
    required this.season,
    required this.races,
    required this.race,
    required this.onSeason,
    required this.onRace,
    required this.replay,
    required this.followed,
    required this.onFollow,
    required this.loading,
    required this.error,
    required this.onRetry,
    this.compact = false,
  });

  final List<int> seasons;
  final int? season;
  final List<RaceSession> races;
  final RaceSession? race;
  final ValueChanged<int> onSeason;
  final ValueChanged<RaceSession> onRace;
  final RaceReplay? replay;
  final int? followed;
  final ValueChanged<int> onFollow;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  /// Short of room (a phone): the driver card keeps to one row of figures.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final replay = this.replay, followed = this.followed;
    return ColoredBox(
      color: Hud.rail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RacePicker(
            seasons: seasons,
            season: season,
            races: races,
            race: race,
            onSeason: onSeason,
            onRace: onRace,
          ),
          const Divider(height: 1, color: Hud.line),
          Expanded(
            child: replay == null
                ? _Status(loading: loading, error: error, onRetry: onRetry)
                : _Tower(replay: replay, followed: followed, onTap: onFollow),
          ),
          if (replay != null && followed != null) ...[
            const Divider(height: 1, color: Hud.line),
            _DriverCard(replay: replay, driver: followed, compact: compact),
          ],
        ],
      ),
    );
  }
}

/// The season over the Grand Prix name, each opening a menu.
class _RacePicker extends StatelessWidget {
  const _RacePicker({
    required this.seasons,
    required this.season,
    required this.races,
    required this.race,
    required this.onSeason,
    required this.onRace,
  });

  final List<int> seasons;
  final int? season;
  final List<RaceSession> races;
  final RaceSession? race;
  final ValueChanged<int> onSeason;
  final ValueChanged<RaceSession> onRace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PopupMenuButton<int>(
            tooltip: 'Season',
            initialValue: season,
            onSelected: (s) {
              if (s != season) onSeason(s);
            },
            itemBuilder: (_) => [
              for (final s in seasons)
                PopupMenuItem(value: s, height: 36, child: Text('$s')),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  season == null ? Hud.unknown : '$season',
                  style: Hud.figures(12, color: Hud.muted),
                ),
                const Icon(Icons.arrow_drop_down, size: 16, color: Hud.muted),
              ],
            ),
          ),
          const SizedBox(height: 2),
          PopupMenuButton<RaceSession>(
            tooltip: 'Grand Prix',
            enabled: races.isNotEmpty,
            initialValue: race,
            onSelected: (r) {
              if (r.sessionKey != race?.sessionKey) onRace(r);
            },
            constraints: const BoxConstraints(maxHeight: 460, minWidth: 260),
            itemBuilder: (_) => [
              for (final r in races)
                PopupMenuItem(
                  value: r,
                  height: 36,
                  // Upstream has no track layout for a few venues yet.
                  enabled: circuitIdByOpenF1Key.containsKey(r.circuitKey),
                  child: Text(r.meetingName),
                ),
            ],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    race?.meetingName ?? 'Loading…',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Hud.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20, color: Hud.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Before the race has loaded: what is happening, or what went wrong.
class _Status extends StatelessWidget {
  const _Status({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Hud.muted),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              )
            : loading
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Loading race data…',
                    style: TextStyle(color: Hud.muted, fontSize: 13),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// The running order at the playhead. Tapping a row follows that driver;
/// tapping the interval heading switches to the gap to the leader.
class _Tower extends StatefulWidget {
  const _Tower({
    required this.replay,
    required this.followed,
    required this.onTap,
  });

  final RaceReplay replay;
  final int? followed;
  final ValueChanged<int> onTap;

  @override
  State<_Tower> createState() => _TowerState();
}

class _TowerState extends State<_Tower> {
  bool _showGap = false;

  @override
  Widget build(BuildContext context) {
    final drivers = {for (final d in widget.replay.drivers) d.number: d};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              const SizedBox(
                width: _Column.position,
                child: Text('POS', style: Hud.label),
              ),
              const SizedBox(
                width: _Column.barBefore + _Column.bar + _Column.barAfter,
              ),
              const Expanded(child: Text('DRIVER', style: Hud.label)),
              GestureDetector(
                onTap: () => setState(() => _showGap = !_showGap),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(_showGap ? 'GAP' : 'INT', style: Hud.label),
                ),
              ),
              const SizedBox(width: _Column.gap),
              const SizedBox(
                width: _Column.compound + _Column.tyreAge,
                child: Text('TYRE', style: Hud.label),
              ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<List<TowerRow>>(
            valueListenable: widget.replay.standings,
            builder: (context, rows, _) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: rows.length,
              itemExtent: 29,
              itemBuilder: (context, i) {
                final row = rows[i];
                final driver = drivers[row.driver];
                if (driver == null) return const SizedBox.shrink();
                return _TowerRow(
                  row: row,
                  driver: driver,
                  showGap: _showGap,
                  selected: row.driver == widget.followed,
                  onTap: () => widget.onTap(row.driver),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Column widths shared by the tower's heading and its rows, so they line
/// up.
abstract final class _Column {
  static const double position = 26;

  /// The team colour bar, and the space either side of it.
  static const double barBefore = 10, bar = 3, barAfter = 9;

  /// Between the timing and the tyre.
  static const double gap = 12;
  static const double compound = 14, tyreAge = 26;
}

class _TowerRow extends StatelessWidget {
  const _TowerRow({
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
    final String timing;
    if (row.retired) {
      timing = 'OUT';
    } else if (row.inPit) {
      timing = 'PIT';
    } else if (row.position == 1) {
      timing = showGap ? Hud.unknown : 'LEADER';
    } else {
      timing = (showGap ? row.gap : row.interval)?.shortLabel ?? '';
    }
    final dim = row.retired ? Hud.faint : Hud.text;
    return Material(
      color: selected ? Hud.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              SizedBox(
                width: _Column.position,
                child: Text(
                  row.retired ? '' : '${row.position}',
                  textAlign: TextAlign.right,
                  style: Hud.figures(12.5, color: Hud.muted),
                ),
              ),
              const SizedBox(width: _Column.barBefore),
              Container(
                width: _Column.bar,
                height: 15,
                color: Hud.rgb(driver.teamColour),
              ),
              const SizedBox(width: _Column.barAfter),
              Expanded(
                child: Text(
                  driver.acronym,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: dim,
                  ),
                ),
              ),
              Text(
                timing,
                style: Hud.figures(
                  12.5,
                  color: row.inPit
                      ? const Color(0xFF5EA8FF)
                      : timing == 'LEADER'
                      ? Hud.muted
                      : dim,
                ),
              ),
              const SizedBox(width: _Column.gap),
              SizedBox(
                width: _Column.compound,
                child: Text(
                  row.retired || row.compound == null
                      ? ''
                      : row.compound!.substring(0, 1),
                  style: Hud.figures(
                    12,
                    color: Hud.tyre(row.compound),
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: _Column.tyreAge,
                child: Text(
                  row.retired || row.tyreAge == null ? '' : '${row.tyreAge}',
                  style: Hud.figures(12, color: Hud.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The followed driver: who, where, and the numbers that matter now.
class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.replay,
    required this.driver,
    required this.compact,
  });

  final RaceReplay replay;
  final int driver;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final info = replay.drivers.where((d) => d.number == driver).firstOrNull;
    if (info == null) return const SizedBox.shrink();
    // The standings refresh a few times a second; often enough here.
    return ValueListenableBuilder<List<TowerRow>>(
      valueListenable: replay.standings,
      builder: (context, rows, _) {
        final index = rows.indexWhere((r) => r.driver == driver);
        final row = index < 0 ? null : rows[index];
        final behind = index >= 0 && index + 1 < rows.length
            ? rows[index + 1]
            : null;
        final timing = replay.timing.driverAt(driver, replay.time.value);
        final speed = replay.currentPoses[driver]?.speed;
        final ahead = row == null || row.position == 1
            ? Hud.unknown
            : row.interval?.shortLabel ?? Hud.unknown;
        final behindText = behind == null || behind.retired
            ? Hud.unknown
            : behind.interval?.shortLabelBehind ?? Hud.unknown;
        final compound = row?.compound;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    height: 34,
                    margin: const EdgeInsets.only(top: 2),
                    color: Hud.rgb(info.teamColour),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (info.fullName.isEmpty ? info.acronym : info.fullName)
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: Hud.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          info.teamName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Hud.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    row == null || row.retired ? 'OUT' : 'P${row.position}',
                    style: Hud.figures(22, weight: FontWeight.w700),
                  ),
                ],
              ),
              SizedBox(height: compact ? 10 : 14),
              _Stats([
                ('AHEAD', ahead),
                ('BEHIND', behindText),
                (
                  'SPEED',
                  speed == null ? Hud.unknown : '${(speed * 3.6).round()} km/h',
                ),
              ]),
              if (!compact) ...[
                const SizedBox(height: 10),
                _Stats([
                  ('LAST', Hud.lapTime(timing.lastLap?.duration)),
                  ('BEST', Hud.lapTime(timing.bestLap)),
                  (
                    'TYRE',
                    compound == null
                        ? Hud.unknown
                        : '${compound.substring(0, 1)} · ${row!.tyreAge ?? 0}L',
                  ),
                ]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats(this.stats);

  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (label, value) in stats)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Hud.label),
                const SizedBox(height: 3),
                Text(value, style: Hud.figures(14.5)),
              ],
            ),
          ),
      ],
    );
  }
}
