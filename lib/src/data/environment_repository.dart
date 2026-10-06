import 'dart:convert';

import 'package:http/http.dart' as http;

import 'circuit.dart';
import 'circuit_environment.dart';

/// Fetches circuit environments at runtime from F1TrackViewer's repository,
/// pinned to the same commit as the vendored circuit data.
///
/// The environments total ~70 MB across all circuits, too much to vendor,
/// while one circuit is a few hundred KB gzipped. The pinned URL never
/// changes underneath us.
class EnvironmentRepository {
  EnvironmentRepository({http.Client? client})
    : _http = client ?? http.Client();

  static const _base =
      'https://raw.githubusercontent.com/Makakashan/F1TrackViewer/'
      '2bb6c9f7019f63c933bad124705053b7984a4a13/public/environments';

  final http.Client _http;
  final _cache = <String, Future<CircuitEnvironment>>{};

  Future<CircuitEnvironment> load(Circuit circuit) {
    final id = circuit.summary.id;
    return _cache[id] ??= _fetch(circuit).catchError((Object e, StackTrace s) {
      _cache.remove(id);
      Error.throwWithStackTrace(e, s);
    });
  }

  Future<CircuitEnvironment> _fetch(Circuit circuit) async {
    final id = circuit.summary.id;
    Future<Map<String, dynamic>> get(String name) async {
      final response = await _http.get(Uri.parse('$_base/$id/$name.json'));
      if (response.statusCode != 200) {
        throw http.ClientException(
          '${response.statusCode}',
          response.request?.url,
        );
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }

    final (
      manifest,
      terrain,
      surface,
      water,
      landuse,
      roads,
      buildings,
    ) = await (
      get('manifest'),
      get('terrain'),
      get('surface'),
      get('water'),
      get('landuse'),
      get('roads'),
      get('buildings'),
    ).wait;
    return CircuitEnvironment.fromJson(
      circuit: circuit,
      manifest: manifest,
      terrain: terrain,
      surface: surface,
      water: water,
      landuse: landuse,
      roads: roads,
      buildings: buildings,
    );
  }
}
