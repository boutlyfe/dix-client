import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dix/model/app_updates.dart';
import 'package:dix/model/startup_actions.dart';

void main() {
  test(
    'startup runs enabled actions once and isolates tests and preview',
    () async {
      var connections = 0, checks = 0;
      final startup = StartupActions();
      Future<void> run({bool isolated = false, bool preview = false}) =>
          startup.run(
            {'flutterAutoConnect': true},
            isolated: isolated,
            preview: preview,
            connect: () async {
              connections++;
            },
            checkUpdates: () async {
              checks++;
            },
          );
      await run(isolated: true);
      await run(preview: true);
      expect(connections, 0);
      expect(checks, 0);
      await run();
      await run();
      expect(connections, 1);
      expect(checks, 1);
    },
  );
  test(
    'startup disabled actions cause no connection or update request',
    () async {
      await StartupActions().run(
        {'flutterCheckUpdates': false},
        connect: () async => fail('Unexpected automatic connection'),
        checkUpdates: () async => fail('Unexpected update request'),
      );
    },
  );
  test(
    'GitHub check accepts newer matching Windows release and uses fixed API host',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/owner/dix/releases/latest',
        );
        return http.Response(
          jsonEncode({
            'tag_name': 'v0.3.0',
            'assets': [
              {'name': 'Dix-Windows-0.3.0.zip'},
            ],
          }),
          200,
        );
      });
      final release = await checkGitHubRelease(client, 'owner/dix');
      expect(release.available, isTrue);
      expect(
        release.pageUrl,
        'https://github.com/owner/dix/releases/tag/v0.3.0',
      );
      expect(compareReleaseVersions('0.10.0', '0.9.0'), greaterThan(0));
      expect(compareReleaseVersions('v$dixVersion', dixVersion), 0);
    },
  );
  test(
    'missing, incompatible and private releases are surfaced as failures',
    () async {
      for (final response in [
        http.Response('{}', 404),
        http.Response(
          jsonEncode({
            'tag_name': 'v9.0.0',
            'assets': [
              {'name': 'Electron.exe'},
            ],
          }),
          200,
        ),
      ]) {
        await expectLater(
          checkGitHubRelease(MockClient((_) async => response), 'owner/dix'),
          throwsFormatException,
        );
      }
      await expectLater(
        checkGitHubRelease(
          MockClient((_) async => fail('Invalid source reached network')),
          'https://evil.invalid/owner/repo',
        ),
        throwsFormatException,
      );
    },
  );
  test('older release is never offered as update', () async {
    final release = await checkGitHubRelease(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v0.2.0',
            'assets': [
              {'name': 'Dix-Windows-0.2.0.zip'},
            ],
          }),
          200,
        ),
      ),
      'owner/dix',
    );
    expect(release.available, isFalse);
  });
}
