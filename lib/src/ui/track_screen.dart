import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';

import '../data/circuit.dart';
import '../data/circuit_repository.dart';
import '../data/environment_repository.dart';
import '../race/race_models.dart';
import '../race/race_replay.dart';
import '../race/race_repository.dart';
import '../race/venues.dart';
import '../scene/adaptive_resolution.dart';
import '../scene/track_scene.dart';
import 'frame_stats.dart';
import 'hud_style.dart';
import 'map_controls.dart';
import 'playback_bar.dart';
import 'race_rail.dart';
import 'scene_gestures.dart';

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
  final _environments = EnvironmentRepository();
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
  CameraMode _cameraMode = CameraMode.orbit;
  bool _sceneReady = false;

  /// Frame timing readout, on with `?stats` in the URL or the F key.
  final _frameStats = FrameStats();
  bool _showStats = Uri.base.queryParameters.containsKey('stats');
  final _tickWatch = Stopwatch();

  /// Render resolution, adapted to what the GPU sustains unless `?scale=`
  /// in the URL fixes it.
  final _resolution = AdaptiveResolution();
  final double? _fixedScale = double.tryParse(
    Uri.base.queryParameters['scale'] ?? '',
  );
  bool _resolutionStarted = false;
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
      _trackScene.showCircuit(circuit);
      _loadEnvironment(circuit);
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
        _trackScene.showCircuit(circuit);
        _loadEnvironment(circuit);
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

  /// Fetches the scenery around [circuit] and shows it if that circuit is
  /// still on screen. The plain slab stays when it cannot be fetched.
  Future<void> _loadEnvironment(Circuit circuit) async {
    try {
      final environment = await _environments.load(circuit);
      if (!mounted || _trackScene.circuit != circuit) return;
      _trackScene.showEnvironment(environment);
    } catch (e) {
      debugPrint('No scenery for ${circuit.summary.id}: $e');
    }
  }

  void _onTick(Duration elapsed, double dt) {
    _tickWatch
      ..reset()
      ..start();
    _trackScene.tick(dt);
    _tickWatch.stop();
    _frameStats.record(dt, _tickWatch.elapsedMicroseconds / 1e6);
    _adaptResolution(dt);
  }

  void _adaptResolution(double dt) {
    final scene = _trackScene.scene;
    final fixed = _fixedScale;
    if (fixed != null) {
      scene.renderScale = fixed.clamp(0.25, 1.0);
    } else if (!_resolutionStarted) {
      // Start within a pixel budget for this viewport, then adapt.
      final size = _trackScene.orbit.viewportSize;
      if (size.width <= 1) return;
      final ratio = View.of(context).devicePixelRatio;
      _resolution.start(size.width * size.height * ratio * ratio);
      scene.renderScale = _resolution.scale;
      _resolutionStarted = true;
    } else if (_resolution.record(dt)) {
      scene.renderScale = _resolution.scale;
    }
    _frameStats.renderScale = scene.renderScale;
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
      case CameraMode.onboard:
        _trackScene.onboard.lookYaw = 0;
      case CameraMode.tv:
        _setCameraMode(CameraMode.orbit);
        _trackScene.resetView();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF): () =>
            setState(() => _showStats = !_showStats),
      },
      child: Scaffold(
        backgroundColor: Hud.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Hud.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Docked rail beside the map; under it on a phone.
                    if (constraints.maxWidth >= 760) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 290, child: _rail()),
                          const VerticalDivider(width: 1, color: Hud.line),
                          Expanded(child: _map()),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: _map()),
                        const Divider(height: 1, color: Hud.line),
                        Expanded(flex: 4, child: _rail(compact: true)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rail({bool compact = false}) => RaceRail(
    seasons: _seasons,
    season: _season,
    races: _seasonRaces,
    race: _race,
    onSeason: _selectSeason,
    onRace: _selectRace,
    replay: _replay,
    followed: _trackScene.followedDriver,
    onFollow: _follow,
    loading: _loadingRace,
    error: _raceError,
    onRetry: _retry,
    compact: compact,
  );

  Widget _map() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The scene has no skybox, so it composites over this backdrop.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 1.2,
              colors: [Color(0xFF16181D), Hud.map],
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_sceneReady)
                    SceneGestures(
                      input: _trackScene,
                      enabled: _cameraMode != CameraMode.tv,
                      child: SceneView(
                        _trackScene.scene,
                        warmUp: true,
                        onTick: _onTick,
                      ),
                    ),
                  if (_fatalError != null)
                    Center(
                      child: Text(
                        'Failed to start: $_fatalError',
                        style: const TextStyle(color: Hud.muted),
                      ),
                    )
                  else if (_circuit == null)
                    const Center(child: CircularProgressIndicator()),
                  Positioned(
                    top: 14,
                    right: 14,
                    left: 14,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: MapControls(
                        mode: _cameraMode,
                        hasRace: _replay != null,
                        onMode: _setCameraMode,
                        scenery: _trackScene.sceneryVisible,
                        onScenery: () => setState(
                          () => _trackScene.sceneryVisible =
                              !_trackScene.sceneryVisible,
                        ),
                        onRecenter: _resetView,
                      ),
                    ),
                  ),
                  if (_showStats)
                    Positioned(
                      top: 14,
                      left: 14,
                      child: FrameStatsView(stats: _frameStats),
                    ),
                  const Positioned(
                    left: 16,
                    right: 16,
                    bottom: 10,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Attribution(),
                    ),
                  ),
                ],
              ),
            ),
            PlaybackBar(replay: _replay),
          ],
        ),
      ],
    );
  }
}
