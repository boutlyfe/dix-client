import 'dart:convert';
import 'package:dix/model/controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'subscription refresh preserves ID, name, metadata and last valid source on error',
    () async {
      var malformed = false;
      var serverName = 'Updated';
      final model = DixController(
        DixController.fixture().archive,
        preview: true,
        createClient: () => MockClient((request) async {
          expect(request.url.scheme, 'https');
          return http.Response(
            malformed
                ? 'not a profile'
                : jsonEncode({
                    'proxies': [
                      {
                        'name': serverName,
                        'type': 'http',
                        'server': '127.0.0.1',
                        'port': 12345,
                      },
                    ],
                    'proxy-groups': [],
                    'rules': ['MATCH,DIRECT'],
                  }),
            200,
            headers: {'profile-update-interval': '6'},
          );
        }),
      );
      model.settings['subs'] = [
        {
          'id': 'preview',
          'name': 'Personal name',
          'url': 'https://provider.invalid/profile',
          'future': {'keep': true},
        },
      ];
      await model.refreshProfile('preview');
      expect(model.servers.single.name, 'Updated');
      expect(model.archive.activeId, 'preview');
      expect(model.archive.subscriptions.single['name'], 'Personal name');
      expect(model.archive.subscriptions.single['future'], {'keep': true});
      expect(model.archive.subscriptions.single['interval'], 6);
      final saved = model.archive.encode();
      malformed = true;
      await expectLater(model.refreshProfile('preview'), throwsFormatException);
      expect(model.archive.encode(), saved);
      malformed = false;
      model.captureRunningArchive();
      model.connected = true;
      serverName = 'Updated while connected';
      await model.refreshProfile('preview');
      expect(model.archive.activeId, 'preview');
      expect(model.selected?.name, 'Updated');
      expect(model.browsingServers.single.name, 'Updated while connected');
      expect(model.servers.single.name, 'Updated');
      model.dispose();
    },
  );
  test('URL import keeps refresh source and rejects plaintext URLs', () async {
    final model = DixController(
      DixController.fixture().archive,
      preview: true,
      createClient: () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'proxies': [
              {
                'name': 'Imported',
                'type': 'http',
                'server': '127.0.0.1',
                'port': 12345,
              },
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(
      model.importUrl('http://provider.invalid/sub'),
      throwsFormatException,
    );
    await model.importUrl('https://provider.invalid/sub');
    expect(
      model.archive.subscriptions.last['url'],
      'https://provider.invalid/sub',
    );
    expect(model.selected!.name, 'Imported');
    model.dispose();
  });
}
