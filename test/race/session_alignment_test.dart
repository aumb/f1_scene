import 'dart:convert';

import 'package:f1_scene/src/data/data_cache.dart';
import 'package:f1_scene/src/race/openf1_client.dart';
import 'package:f1_scene/src/race/race_models.dart';
import 'package:f1_scene/src/race/race_repository.dart';
import 'package:f1_scene/src/race/session_alignment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/circuits.dart';

void main() {
  final (:stations, :track) = bahrain();

  for (final direction in [-1, 1]) {
    test(
      'aligns a lap and detects direction $direction in timestamp order',
      () async {
        final start = DateTime.utc(2024, 3, 2, 15);
        final rows = [
          for (var i = 0; i < stations.length; i += 8)
            {
              'driver_number': 1,
              'date': start
                  .add(Duration(milliseconds: i * 33))
                  .toIso8601String(),
              'x':
                  track.place((i * direction).toDouble(), 0).position.x * 10 +
                  5000,
              'y':
                  track.place((i * direction).toDouble(), 0).position.z * 10 -
                  8000,
            },
        ];
        final repository = RaceRepository(
          client: OpenF1Client(
            cache: DataCache(),
            rateLimits: [],
            httpClient: MockClient(
              (_) async =>
                  http.Response(jsonEncode(rows.reversed.toList()), 200),
            ),
          ),
        );
        final result = await alignToLap(
          repository: repository,
          session: RaceSession(
            sessionKey: 9,
            meetingName: 'Bahrain',
            circuitKey: 3,
            year: 2024,
            start: start,
            end: start.add(const Duration(hours: 2)),
          ),
          lap: RaceLap(
            driverNumber: 1,
            lapNumber: 4,
            start: start,
            duration: 100,
            isPitOutLap: false,
          ),
          stations: stations,
        );
        expect(result.directionSign, direction);
        expect(result.rmsError, lessThan(0.1));
      },
    );

    test('detects direction $direction across the start/finish seam', () {
      final positions = [
        for (var i = -80; i <= 80; i += 8)
          track.place((i * direction).toDouble(), 2).position,
      ];
      expect(
        racingDirection([for (final p in positions) (p.x, p.z)], track),
        direction,
      );
    });

    test('detects direction $direction despite stops and an outlier', () {
      final positions = [
        for (var i = 0; i < 60; i++)
          track
              .place(500.0 + direction * (i < 30 ? 0 : (i - 30) * 8), 0)
              .position,
      ];
      positions[40] = stations.center[1500];
      expect(
        racingDirection([for (final p in positions) (p.x, p.z)], track),
        direction,
      );
    });
  }

  test('does not guess a direction from a stationary reference lap', () {
    final p = stations.center[500];
    expect(
      () => racingDirection(List.filled(60, (p.x, p.z)), track),
      throwsStateError,
    );
  });
}
