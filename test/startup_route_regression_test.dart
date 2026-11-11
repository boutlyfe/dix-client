import 'package:flutter_test/flutter_test.dart';
import 'package:dix/model/archive.dart';
import 'package:dix/model/rules.dart';
import 'package:dix/platform/core_selection.dart';

void main() {
  test(
    'manual selection follows effective advanced fallback instead of first imported group',
    () {
      final archive = DixArchive({
        'settings': {
          'activeSub': 'test',
          'routeMode': 'rule',
          'advancedRules': {
            'enabled': true,
            'text': 'DOMAIN,discord.example,Forced',
            'fallback': 'Auto',
          },
        },
        'profiles': {
          'test': {
            'proxies': [
              {'name': 'FI', 'type': 'vless'},
              {'name': 'PL', 'type': 'hysteria2'},
            ],
            'proxy-groups': [
              {
                'name': 'Main',
                'type': 'select',
                'proxies': ['Auto'],
              },
              {
                'name': 'Forced',
                'type': 'select',
                'proxies': ['PL'],
              },
              {
                'name': 'Auto',
                'type': 'url-test',
                'proxies': ['PL', 'FI'],
              },
            ],
            'rules': ['MATCH,Main'],
          },
        },
      });
      final configured = configuredProfile(archive, selected: 'FI');
      final prepared = prepareManualRoutingProfile(
        configured,
        rootGroup: mainRoutingGroup(configured),
        selectedServer: 'FI',
      );
      expect(prepared.profile['rule'], contains('MATCH,${prepared.rootGroup}'));
      expect(
        prepared.profile['rule'],
        contains('DOMAIN,discord.example,Forced'),
      );
      expect(
        ((prepared.profile['proxy-groups'] as List)[2] as Map)['type'],
        'url-test',
      );
    },
  );
}
