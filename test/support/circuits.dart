import 'package:f1_scene/src/data/circuit_files.dart';
import 'package:f1_scene/src/geometry/track_mesh.dart';
import 'package:f1_scene/src/geometry/track_projector.dart';

export 'package:f1_scene/src/data/circuit_files.dart';

/// Bahrain, the circuit most tests drive on: its stations and a projector.
({TrackStations stations, TrackProjector track}) bahrain() {
  final stations = TrackStations.sample(loadCircuit('bh-2002'));
  return (stations: stations, track: TrackProjector(stations));
}
