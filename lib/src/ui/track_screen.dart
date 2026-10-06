import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../data/circuit.dart';
import '../data/circuit_repository.dart';
import '../geometry/track_mesh.dart';
import '../scene/track_scene.dart';

/// Full-screen circuit diorama with a heads-up overlay.
class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, this.initialCircuitId = 'bh-2002'});

  final String initialCircuitId;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  final _repository = CircuitRepository();
  final _trackScene = TrackScene();

  List<CircuitSummary> _circuits = const [];
  Circuit? _circuit;
  TrackColorMode _colorMode = TrackColorMode.sectors;
  bool _sceneReady = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final (_, circuits) = await (
        _trackScene.initialize(),
        _repository.loadIndex(),
      ).wait;
      final initial = circuits.firstWhere(
        (c) => c.id == widget.initialCircuitId,
        orElse: () => circuits.first,
      );
      final circuit = await _repository.load(initial);
      if (!mounted) return;
      // Populate the scene before SceneView mounts so its warm-up compiles
      // every pipeline up front. CameraControls is not laid out yet, so seed
      // the viewport size used for framing; it keeps it current from here.
      _trackScene.orbit.viewportSize = MediaQuery.sizeOf(context);
      _trackScene.showCircuit(circuit, _colorMode);
      setState(() {
        _circuits = circuits;
        _circuit = circuit;
        _sceneReady = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _select(CircuitSummary summary) async {
    final circuit = await _repository.load(summary);
    if (!mounted) return;
    _trackScene.showCircuit(circuit, _colorMode);
    setState(() => _circuit = circuit);
  }

  void _setColorMode(TrackColorMode mode) {
    _trackScene.setColorMode(mode);
    setState(() => _colorMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The scene has no skybox, so it composites over this backdrop.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 1.2,
                colors: [Color(0xFF1C2028), Color(0xFF07080A)],
              ),
            ),
          ),
          if (_sceneReady)
            CameraControls(
              controller: _trackScene.orbit,
              child: SceneView(_trackScene.scene, warmUp: true),
            ),
          if (_error != null)
            Center(child: Text('Failed to load: $_error'))
          else if (_circuit == null)
            const Center(child: CircularProgressIndicator()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _Hud(
                circuits: _circuits,
                circuit: _circuit,
                colorMode: _colorMode,
                onSelect: _select,
                onColorMode: _setColorMode,
                onResetView: _trackScene.resetView,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.circuits,
    required this.circuit,
    required this.colorMode,
    required this.onSelect,
    required this.onColorMode,
    required this.onResetView,
  });

  final List<CircuitSummary> circuits;
  final Circuit? circuit;
  final TrackColorMode colorMode;
  final ValueChanged<CircuitSummary> onSelect;
  final ValueChanged<TrackColorMode> onColorMode;
  final VoidCallback onResetView;

  @override
  Widget build(BuildContext context) {
    final circuit = this.circuit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: 16,
          runSpacing: 12,
          children: [
            if (circuit != null) _CircuitCard(circuit: circuit),
            if (circuits.isNotEmpty)
              _CircuitPicker(
                circuits: circuits,
                selected: circuit?.summary,
                onSelect: onSelect,
              ),
          ],
        ),
        const Spacer(),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<TrackColorMode>(
              segments: const [
                ButtonSegment(
                  value: TrackColorMode.sectors,
                  label: Text('Sectors'),
                ),
                ButtonSegment(
                  value: TrackColorMode.elevation,
                  label: Text('Elevation'),
                ),
                ButtonSegment(
                  value: TrackColorMode.asphalt,
                  label: Text('Asphalt'),
                ),
              ],
              selected: {colorMode},
              onSelectionChanged: (s) => onColorMode(s.first),
            ),
            IconButton.filledTonal(
              tooltip: 'Reset view',
              onPressed: onResetView,
              icon: const Icon(Icons.center_focus_strong),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _Footer(),
      ],
    );
  }
}

class _CircuitCard extends StatelessWidget {
  const _CircuitCard({required this.circuit});

  final Circuit circuit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = circuit.summary;
    final (lo, hi) = circuit.elevationRange;
    return _Panel(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              summary.country.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(summary.name, style: theme.textTheme.titleLarge),
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

class _CircuitPicker extends StatelessWidget {
  const _CircuitPicker({
    required this.circuits,
    required this.selected,
    required this.onSelect,
  });

  final List<CircuitSummary> circuits;
  final CircuitSummary? selected;
  final ValueChanged<CircuitSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<CircuitSummary>(
      key: ValueKey(selected?.id),
      initialSelection: selected,
      width: 260,
      menuHeight: 420,
      label: const Text('Circuit'),
      leadingIcon: const Icon(Icons.route),
      dropdownMenuEntries: [
        for (final c in circuits)
          DropdownMenuEntry(value: c, label: c.shortName),
      ],
      onSelected: (c) {
        if (c != null && c.id != selected?.id) onSelect(c);
      },
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

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC111318),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Unofficial fan project, not affiliated with Formula 1. '
      'Track data: bacinger/f1-circuits (MIT), F1TrackViewer (MIT), '
      'TUMFTM racetrack-database (LGPL-3.0), OpenTopoData (CC-BY 4.0).',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }
}
