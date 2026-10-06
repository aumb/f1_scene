import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../data/circuit.dart';
import '../data/circuit_repository.dart';
import '../geometry/track_mesh.dart';
import '../race/race_models.dart';
import '../race/race_replay.dart';
import '../race/race_repository.dart';
import '../race/venues.dart';
import '../scene/track_scene.dart';
import 'camera_bar.dart';
import 'driver_card.dart';
import 'hud.dart';
import 'race_picker.dart';
import 'timing_tower.dart';
import 'timeline_bar.dart';

/// Full-screen race replay on a circuit diorama, with a heads-up overlay.
class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  /// Shown when OpenF1 cannot be reached at startup.
  static const _fallbackCircuitId = 'bh-2002';

  final _circuits = CircuitRepository();
  final _races = RaceRepository();
  final _trackScene = TrackScene();

  /// Newest first; OpenF1 has position data from 2023.
  final _seasons = [for (var y = DateTime.now().year; y >= 2023; y--) y];

  List<CircuitSummary> _circuitIndex = const [];
  int? _season;
  List<RaceSession> _seasonRaces = const [];
  RaceSession? _race;
  Circuit? _circuit;
  RaceReplay? _replay;
  TrackColorMode _colorMode = TrackColorMode.sectors;
  CameraMode _cameraMode = CameraMode.orbit;
  bool _sceneReady = false;
  bool _loadingRace = false;
  String? _raceError;
  Object? _fatalError;

  /// Bumped on every race selection, so a slow load for an earlier pick
  /// cannot overwrite a newer one.
  int _selection = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _replay?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final (_, index) = await (
        _trackScene.initialize(),
        _circuits.loadIndex(),
      ).wait;
      _circuitIndex = index;
      final race = await _latestRace();
      final circuit = await _loadCircuit(
        race == null
            ? _fallbackCircuitId
            : circuitIdByOpenF1Key[race.circuitKey]!,
      );
      if (!mounted) return;
      // Populate the scene before SceneView mounts so its warm-up compiles
      // every pipeline up front. CameraControls is not laid out yet, so seed
      // the viewport size used for framing; it keeps it current from here.
      _trackScene.orbit.viewportSize = MediaQuery.sizeOf(context);
      _trackScene.showCircuit(circuit, _colorMode);
      setState(() {
        _circuit = circuit;
        _sceneReady = true;
        if (race == null) _raceError = "Couldn't reach OpenF1.";
      });
      if (race != null) await _selectRace(race);
    } catch (e) {
      if (mounted) setState(() => _fatalError = e);
    }
  }

  /// The most recent completed race at a venue with a vendored layout,
  /// selecting its season. Null when OpenF1 is unreachable.
  Future<RaceSession?> _latestRace() async {
    for (final season in _seasons) {
      try {
        final races = await _races.races(season);
        final supported = races.where(
          (r) => circuitIdByOpenF1Key.containsKey(r.circuitKey),
        );
        if (supported.isEmpty) continue;
        _season = season;
        _seasonRaces = races;
        return supported.last;
      } catch (e) {
        debugPrint('Season $season unavailable: $e');
        return null;
      }
    }
    return null;
  }

  Future<Circuit> _loadCircuit(String id) =>
      _circuits.load(_circuitIndex.firstWhere((c) => c.id == id));

  Future<void> _selectSeason(int season) async {
    setState(() {
      _season = season;
      _seasonRaces = const [];
    });
    try {
      final races = await _races.races(season);
      if (!mounted || _season != season) return;
      setState(() => _seasonRaces = races);
      final first = races
          .where((r) => circuitIdByOpenF1Key.containsKey(r.circuitKey))
          .firstOrNull;
      if (first != null) await _selectRace(first);
    } catch (e) {
      if (!mounted) return;
      setState(() => _raceError = "Couldn't load the $season season.");
    }
  }

  Future<void> _selectRace(RaceSession race) async {
    final selection = ++_selection;
    bool stale() => !mounted || selection != _selection;

    // Detach the old replay from the scene and the overlay before disposing
    // it, so nothing ticks or listens to it afterwards.
    final previous = _replay;
    _trackScene
      ..showRace(null)
      ..cameraMode = CameraMode.orbit;
    setState(() {
      _cameraMode = CameraMode.orbit;
      _race = race;
      _replay = null;
      _loadingRace = true;
      _raceError = null;
    });
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }

    try {
      final id = circuitIdByOpenF1Key[race.circuitKey]!;
      if (_circuit?.summary.id != id) {
        final circuit = await _loadCircuit(id);
        if (stale()) return;
        _trackScene.showCircuit(circuit, _colorMode);
        setState(() => _circuit = circuit);
      }
      final replay = await RaceReplay.load(
        repository: _races,
        session: race,
        stations: _trackScene.stations!,
      );
      if (stale()) {
        replay.dispose();
        return;
      }
      _trackScene.showRace(replay);
      setState(() {
        _replay = replay;
        _loadingRace = false;
      });
      // Debug builds: report any surfaces that trade pixels (z-fighting).
      assert(() {
        _trackScene.scene.probeDepthConflicts().then(
          (r) => debugPrint('Depth conflicts: ${r.describe()}'),
        );
        return true;
      }());
    } catch (e) {
      debugPrint('Race load failed: $e');
      if (stale()) return;
      setState(() {
        _loadingRace = false;
        _raceError = "Couldn't load race data.";
      });
    }
  }

  void _retry() {
    final race = _race;
    if (race != null) {
      _selectRace(race);
    } else {
      setState(() => _raceError = null);
      _latestRace().then((race) {
        if (!mounted) return;
        if (race == null) {
          setState(() => _raceError = "Couldn't reach OpenF1.");
        } else {
          _selectRace(race);
        }
      });
    }
  }

  void _setColorMode(TrackColorMode mode) {
    _trackScene.setColorMode(mode);
    setState(() => _colorMode = mode);
  }

  void _setCameraMode(CameraMode mode) {
    _trackScene.cameraMode = mode;
    setState(() => _cameraMode = mode);
  }

  void _follow(int driver) {
    _trackScene.followedDriver = driver;
    setState(() {});
  }

  void _resetView() {
    switch (_cameraMode) {
      case CameraMode.orbit:
        _trackScene.resetView();
      case CameraMode.chase:
        _trackScene.chase.resetView();
      case CameraMode.tv:
        _setCameraMode(CameraMode.orbit);
        _trackScene.resetView();
    }
  }

  /// The race picker, and either the circuit card or, during a race, the
  /// timing tower and the followed driver's card.
  Widget _topOverlay(Circuit? circuit) {
    final replay = _replay;
    final followed = _trackScene.followedDriver;
    final picker = RacePicker(
      seasons: _seasons,
      season: _season,
      races: _seasonRaces,
      race: _race,
      onSeason: _selectSeason,
      onRace: _selectRace,
    );
    final Widget primary;
    if (replay != null) {
      primary = TimingTower(
        replay: replay,
        followed: followed,
        onSelect: _follow,
      );
    } else if (circuit != null) {
      primary = CircuitCard(circuit: circuit, race: _race);
    } else {
      primary = const SizedBox.shrink();
    }
    final card = replay != null && followed != null
        ? DriverCard(replay: replay, driver: followed)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The tower scrolls when the window is too short for every row.
        final scrolling = SingleChildScrollView(child: primary);
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              picker,
              const SizedBox(height: 12),
              Flexible(child: scrolling),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            scrolling,
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                picker,
                if (card != null) ...[const SizedBox(height: 12), card],
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final circuit = _circuit;
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
              controller: _trackScene.activeController,
              enabled: _cameraMode != CameraMode.tv,
              child: SceneView(
                _trackScene.scene,
                warmUp: true,
                onTick: (_, dt) => _trackScene.tick(dt),
              ),
            ),
          if (_fatalError != null)
            Center(child: Text('Failed to start: $_fatalError'))
          else if (circuit == null)
            const Center(child: CircularProgressIndicator()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _topOverlay(circuit)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ColorModeMenu(mode: _colorMode, onChanged: _setColorMode),
                      IconButton.filledTonal(
                        tooltip: 'Reset view',
                        onPressed: _resetView,
                        icon: const Icon(Icons.center_focus_strong),
                      ),
                      const SizedBox(width: 4),
                      CameraBar(
                        mode: _cameraMode,
                        drivers: _replay?.drivers ?? const [],
                        followed: _trackScene.followedDriver,
                        onMode: _setCameraMode,
                        onFollow: _follow,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_sceneReady)
                    TimelineBar(
                      replay: _replay,
                      loading: _loadingRace,
                      error: _raceError,
                      onRetry: _retry,
                    ),
                  const SizedBox(height: 12),
                  const Attribution(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
