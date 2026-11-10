import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dix/platform/core_latency.dart';

void main() {
  test(
    'blocked first endpoint retries independently and accepts numeric strings',
    () async {
      final urls = <String>[];
      final result = await measureProxyLatency(
        (_, data) async {
          final request = jsonDecode(data as String) as Map;
          urls.add(request['test-url'] as String);
          expect(request['proxy-name'], 'Node');
          expect(request['timeout'], 15000);
          return urls.length == 1 ? {'value': -1} : jsonEncode({'value': '81'});
        },
        'Node',
        timeoutMs: 15000,
      );
      expect(result, 81);
      expect(urls, latencyEndpoints);
    },
  );
  test(
    'transport errors retry and unreachable servers stay unavailable',
    () async {
      var calls = 0;
      final result = await measureProxyLatency((_, _) async {
        calls++;
        throw StateError('timeout');
      }, 'Node');
      expect(calls, 2);
      expect(result, isNull);
    },
  );
  test(
    'success avoids retry and cancellation prevents more requests',
    () async {
      var calls = 0;
      expect(
        await measureProxyLatency((_, _) async {
          calls++;
          return {'value': 24};
        }, 'Node'),
        24,
      );
      expect(calls, 1);
      expect(
        await measureProxyLatency(
          (_, _) async {
            calls++;
            return {'value': 24};
          },
          'Node',
          cancelled: () => true,
        ),
        isNull,
      );
      expect(calls, 1);
    },
  );
}
