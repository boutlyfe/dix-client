import 'package:flutter_test/flutter_test.dart';
import 'package:dix/platform/core_status.dart';

void main() {
  test(
    'open mixed port or requested TUN flag cannot imply connected tunnel',
    () async {
      await expectLater(
        requireStartedTun((method, _) async {
          expect(method, 'getTunStatus');
          return {
            'enabled': false,
            'device': '',
            'error': 'Adapter creation failed',
          };
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Adapter creation failed'),
          ),
        ),
      );
    },
  );
  test('actual enabled tunnel is accepted', () async {
    await requireStartedTun(
      (_, _) async => {'enabled': true, 'device': 'Dix', 'error': ''},
    );
  });
  test('missing status never marks VPN connected', () async {
    await expectLater(
      requireStartedTun((_, _) async => null),
      throwsStateError,
    );
  });
}
