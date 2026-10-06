import 'package:flutter/material.dart';

import '../race/race_models.dart';
import '../race/venues.dart';

/// Season and Grand Prix dropdowns.
class RacePicker extends StatelessWidget {
  const RacePicker({
    super.key,
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
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        DropdownMenu<int>(
          key: ValueKey('season $season'),
          initialSelection: season,
          width: 130,
          label: const Text('Season'),
          dropdownMenuEntries: [
            for (final s in seasons) DropdownMenuEntry(value: s, label: '$s'),
          ],
          onSelected: (s) {
            if (s != null && s != season) onSeason(s);
          },
        ),
        DropdownMenu<RaceSession>(
          key: ValueKey('race ${race?.sessionKey} ${races.length}'),
          initialSelection: race,
          enabled: races.isNotEmpty,
          width: 300,
          menuHeight: 420,
          label: const Text('Grand Prix'),
          leadingIcon: const Icon(Icons.flag_outlined),
          dropdownMenuEntries: [
            for (final r in races)
              DropdownMenuEntry(
                value: r,
                label: r.meetingName,
                // Upstream has no start/finish or sector markers yet.
                enabled: circuitIdByOpenF1Key.containsKey(r.circuitKey),
                trailingIcon: circuitIdByOpenF1Key.containsKey(r.circuitKey)
                    ? null
                    : const Tooltip(
                        message: 'No track layout yet',
                        child: Icon(Icons.block, size: 16),
                      ),
              ),
          ],
          onSelected: (r) {
            if (r != null && r.sessionKey != race?.sessionKey) onRace(r);
          },
        ),
      ],
    );
  }
}
