import 'dart:convert';

import 'package:http/http.dart' as http;

import 'circuit.dart';
import 'circuit_environment.dart';
import 'data_cache.dart';

/// Fetches circuit environments at runtime from F1TrackViewer's repository,
/// pinned to the same commit as the vendored circuit data.
///
/// The environments total ~70 MB across all circuits, too much to vendor,
/// while one circuit is a few hundred KB gzipped. The pinned URL never
/// changes underneath us.
class EnvironmentRepository {
  EnvironmentRepository({http.Client? client, DataCache? cache})
    : _http = client ?? http.Client(),
      _dataCache = cache ?? DataCache.instance;

  static const _base =
      'https://raw.githubusercontent.com/Makakashan/F1TrackViewer/'
      '2bb6c9f7019f63c933bad124705053b7984a4a13/public/environments';

  final http.Client _http;

  /// Where downloaded files are kept, on the device: at a pinned commit
  /// they never change.
  final DataCache _dataCache;

  /// Each circuit's environment, loaded or on its way.
  final _loading = <String, Future<CircuitEnvironment>>{};

  Future<CircuitEnvironment> load(Circuit circuit) {
    final id = circuit.summary.id;
    return _loading[id] ??= _fetch(circuit)
        .catchError((Object e, StackTrace s) {
          // Forget the failure so the next call retries.
          _loading.remove(id);
          Error.throwWithStackTrace(e, s);
        });
  }

  Future<CircuitEnvironment> _fetch(Circuit circuit) async {
    final id = circuit.summary.id;
    // [ifMissing] stands in for a file that isn't there.
    Future<Map<String, dynamic>> get(
      String name, {
      Map<String, dynamic>? ifMissing,
    }) async {
      final url = '$_base/$id/$name.json';
      var body = await _dataCache.read(url);
      if (body == null) {
        final response = await _http.get(Uri.parse(url));
        if (response.statusCode == 404 && ifMissing != null) return ifMissing;
        if (response.statusCode != 200) {
          throw http.ClientException(
            '${response.statusCode}',
            response.request?.url,
          );
        }
        body = response.bodyBytes;
        await _dataCache.write(url, body, Keep.device);
      }
      return jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
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
      // The sea mask is a nicety; the scene builds without it.
      get('surface', ifMissing: const {}),
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
