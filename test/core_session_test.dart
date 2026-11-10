import 'package:dix/platform/core_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'imported profiles cannot open additional listeners or expose control API',
    () {
      final original = <String, dynamic>{
        'mixed-port': 17897,
        'port': 1234,
        'external-controller': '0.0.0.0:9999',
        'external-controller-tls': '0.0.0.0:8888',
        'external-controller-pipe': 'pipe',
        'listeners': [
          {'port': 3333},
        ],
        'dns': {
          'listen': '0.0.0.0:53',
          'nameserver': ['1.1.1.1'],
        },
        'proxies': [
          {'name': 'kept'},
        ],
        'future': {'keep': true},
      };
      final result = ownedCoreConfig(original);
      expect(result['mixed-port'], 17897);
      expect(result['external-controller'], '');
      expect(result['external-controller-tls'], '');
      expect(result['external-controller-pipe'], '');
      expect(result['port'], 0);
      expect(result['listeners'], isEmpty);
      expect(result['dns']['listen'], '');
      expect(result['dns']['nameserver'], ['1.1.1.1']);
      expect(result['future'], {'keep': true});
      expect(original['port'], 1234);
      expect(original['dns']['listen'], '0.0.0.0:53');
    },
  );
}
