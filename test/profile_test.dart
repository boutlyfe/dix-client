import 'package:flutter_test/flutter_test.dart';
import 'package:dix/model/archive.dart';
import 'package:dix/model/controller.dart';

void main() {
  test(
    'profile operations preserve source and subscription metadata',
    () async {
      final model = DixController(
        DixArchive({
          'settings': {
            'activeSub': 'one',
            'currentServer': 'Old',
            'subs': [
              {
                'id': 'one',
                'name': 'First',
                'url': 'https://example.org/profile',
                'custom': 42,
              },
              {'id': 'two', 'name': 'Second'},
            ],
          },
          'profiles': {
            'one': {
              'proxies': [
                {'name': 'Old', 'type': 'vless'},
              ],
            },
            'two': {
              'proxies': [
                {'name': 'New', 'type': 'vless'},
              ],
            },
          },
          'future': {'preserved': true},
        }),
        preview: true,
      );
      await model.renameProfile('one', '  Renamed  ');
      expect(model.archive.subscriptions.first, {
        'id': 'one',
        'name': 'Renamed',
        'url': 'https://example.org/profile',
        'custom': 42,
      });
      await model.activateProfile('two');
      expect(model.selected?.name, 'New');
      await model.removeProfile('two');
      expect(model.archive.activeId, 'one');
      expect(model.selected?.name, 'Old');
      expect(model.archive.subscriptions.length, 1);
      expect(model.archive.document['future'], {'preserved': true});
      model.dispose();
    },
  );

  test(
    'malformed profile activation and connected removal leave data intact',
    () async {
      final model = DixController.fixture();
      model.archive.profiles['bad'] = 'proxies: [';
      final source = model.archive.encode();
      await expectLater(model.activateProfile('bad'), throwsA(anything));
      expect(model.archive.encode(), source);
      model.connected = true;
      await expectLater(model.removeProfile('preview'), throwsStateError);
      expect(model.archive.encode(), source);
      model.dispose();
    },
  );

  test(
    'connected browsing and adding subscriptions preserves live selection',
    () async {
      final model = DixController.fixture();
      model.archive.profiles['other'] = {
        'proxies': [
          {'name': 'Other server', 'type': 'http'},
        ],
      };
      model.captureRunningArchive();
      model.connected = true;
      await model.browseProfile('other');
      expect(model.browsedProfileId, 'other');
      expect(model.browsingServers.single.name, 'Other server');
      expect(model.archive.activeId, 'preview');
      expect(model.selected?.name, '🇫🇮 Финляндия');
      await model.addProfile(
        'New subscription',
        '{"proxies":[{"name":"Imported","type":"http"}]}',
      );
      expect(model.browsingServers.single.name, 'Imported');
      expect(model.archive.activeId, 'preview');
      expect(model.selected?.name, '🇫🇮 Финляндия');
      await model.removeProfile('other');
      expect(model.archive.profiles.containsKey('other'), false);
      expect(model.selected?.name, '🇫🇮 Финляндия');
      model.dispose();
    },
  );
}
