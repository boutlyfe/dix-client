import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dix/model/archive.dart';
import 'package:dix/model/controller.dart';
import 'package:dix/model/rules.dart';

void main() {
  test('reading settings during assignment does not discard the write', () {
    final archive = DixArchive({
      'settings': {
        'subs': [
          {'id': 'one', 'name': 'keep'},
        ],
      },
      'profiles': {},
    });
    archive.settings['subs'] = [
      for (final sub in archive.subscriptions) {...sub, 'updatedAt': 42},
    ];
    expect(archive.subscriptions.single['updatedAt'], 42);
    archive.settings['selected'] = {
      ...jsonMap(archive.settings['selected']),
      'GLOBAL': 'chosen',
    };
    expect(archive.settings['selected']['GLOBAL'], 'chosen');
  });

  test(
    'legacy archive preserves profiles, unknown fields and original layout',
    () {
      final original = <String, dynamic>{
        'settings': {
          'activeSub': 'one',
          'theme': 'light',
          'appearance': 'classic',
          'advancedRules': {
            'enabled': true,
            'text': r'PROCESS-NAME-REGEX,(?i)(a{1,3}|steam),DIRECT',
            'groups': [
              {'name': 'Alias', 'target': '@VPN'},
            ],
          },
          'futureOption': {
            'nested': [1, true, 'keep'],
          },
          'layout': [
            {'id': 'server', 'on': true},
            {'id': 'fidget', 'on': true},
          ],
        },
        'profiles': {'one': 'proxies: []\nrules:\n  - MATCH,DIRECT\n'},
        'futureEnvelope': 'keep',
      };
      final archive = DixArchive.decode(jsonEncode(original));
      expect(jsonDecode(archive.encode()), original);
      expect(archive.activeWidgetIds, ['server']);
      expect(archive.settings['layout'], original['settings']!['layout']);
    },
  );
  test('source maps are not changed when settings are edited', () {
    final source = <String, dynamic>{
      'settings': {'theme': 'dark'},
      'profiles': <String, dynamic>{},
    };
    final archive = DixArchive(source);
    archive.settings['theme'] = 'light';
    expect(source['settings']!['theme'], 'dark');
  });
  test('YAML and JSON profiles have identical usable server data', () {
    final yaml =
        'proxies:\n - name: Finland\n   type: vless\nproxy-groups:\n - name: VPN\n   proxies: [Finland]\n';
    final profile = parseProfile(yaml);
    final servers = DixServer.fromProfile(profile);
    expect(servers.single.name, 'Finland');
    expect(servers.single.group, 'VPN');
    expect(
      DixServer.fromProfile(parseProfile(jsonEncode(profile))).single.type,
      'vless',
    );
  });
  test('rules preserve regex commas, exact DOMAIN and MATCH order', () {
    const regex = r'PROCESS-NAME-REGEX,(?i)(csgo|steam|a{1,3}|[a,b]),DIRECT';
    expect(ruleFields(regex), [
      'PROCESS-NAME-REGEX',
      r'(?i)(csgo|steam|a{1,3}|[a,b])',
      'DIRECT',
    ]);
    expect(
      validateRules('DOMAIN,example.com,DIRECT\n$regex\nMATCH,@VPN'),
      isEmpty,
    );
    expect(validateRules('MATCH,@VPN\nDOMAIN,example.com,DIRECT'), isNotEmpty);
    expect(validateRules('DOMAIN,https://example.com/page,DIRECT'), isNotEmpty);
    expect(
      validateRules('DOMAIN,example.com,Unknown', targets: {'DIRECT'}),
      isNotEmpty,
    );
  });
  test(
    'effective profile compiles imported advanced rules and keeps source untouched',
    () {
      final controller = DixController.fixture();
      final archive = controller.archive;
      final before = archive.encode();
      final configured = configuredProfile(
        archive,
        selected: controller.selected!.name,
      );
      expect(configured['rule'], [
        'DOMAIN,dubapparels.com,DIRECT',
        'GEOSITE,discord,Зарубежные сайты',
        'MATCH,Зарубежные сайты',
      ]);
      expect(configured['find-process-mode'], 'always');
      expect(archive.encode(), before);
      controller.dispose();
    },
  );
  test(
    'invalid imports are rejected before replacing the current archive',
    () async {
      final controller = DixController.fixture();
      final before = controller.archive.encode();
      await expectLater(
        controller.importBackup('[1,2]'),
        throwsFormatException,
      );
      expect(controller.archive.encode(), before);
      controller.dispose();
    },
  );
}
