import 'package:dix/model/archive.dart';
import 'package:dix/model/rules.dart';
import 'package:dix/model/profile_network.dart';
import 'package:flutter_test/flutter_test.dart';

DixArchive sample(Map<String, dynamic> settings) => DixArchive({
  'settings': {'activeSub': 'one', 'routeMode': 'rule', ...settings},
  'profiles': {
    'one': {
      'proxies': [
        {
          'name': 'Finland',
          'type': 'vless',
          'reality-opts': {'public-key': 'preserved'},
        },
      ],
      'proxy-groups': [
        {
          'name': 'VPN',
          'type': 'select',
          'proxies': ['Finland'],
        },
      ],
      'rules': ['MATCH,VPN'],
      'dns': {
        'nameserver': ['https://profile.example/dns-query'],
        'future-dns-field': 42,
        'nameserver-policy': {
          'kept.example': ['1.2.3.4'],
        },
      },
      'future': {'keep': true},
    },
  },
});

void main() {
  test('provider override off preserves routing DNS mode and sniffing', () {
    final archive = sample({
      'flutterOverrideProvider': false,
      'routeMode': 'global',
      'aiDns': true,
      'ruOptimization': true,
      'dnsMode': 'custom',
      'dnsCustom': ['invalid://resolver'],
      'rules': [
        {'type': 'unknown', 'value': 'ignored'},
      ],
      'advancedRules': {'enabled': true, 'text': 'INVALID'},
    });
    final provider = archive.profiles['one'] as Map;
    provider['mode'] = 'rule';
    provider['sniffer'] = {'enable': false, 'override-destination': true};
    provider['rules'] = ['DOMAIN,provider.example,DIRECT', 'MATCH,VPN'];
    final before = archive.encode();
    final result = configuredProfile(archive, selected: 'Finland');
    expect(result['mode'], 'rule');
    expect(result['rule'], provider['rules']);
    expect(result['dns'], provider['dns']);
    expect(result['sniffer'], provider['sniffer']);
    expect(result['tun']['enable'], false);
    expect(result['mixed-port'], 17897);
    expect(result['external-controller'], '');
    expect(result.containsKey('rules'), false);
    expect(archive.encode(), before);
  });

  test('provider global mode stays global when manual override is off', () {
    final archive = sample({
      'flutterOverrideProvider': false,
      'routeMode': 'rule',
    });
    (archive.profiles['one'] as Map)['mode'] = 'global';
    expect(configuredProfile(archive, selected: 'Finland')['mode'], 'global');
    archive.settings['flutterOverrideProvider'] = true;
    expect(configuredProfile(archive, selected: 'Finland')['mode'], 'rule');
  });

  test(
    'Windows config applies DNS presets, ru settings and legacy rules without modifying archive',
    () {
      final archive = sample({
        'dnsMode': 'quad9',
        'ruOptimization': true,
        'rules': [
          {'type': 'process', 'value': 'Steam.exe', 'action': 'no'},
          {'type': 'domainSuffix', 'value': '*.example.com', 'action': 'block'},
          {'type': 'domainKeyword', 'value': 'disabled', 'enabled': false},
        ],
      });
      final before = archive.encode();
      final result = configuredProfile(archive, selected: 'Finland');
      expect(
        result['rule'],
        containsAll([
          'PROCESS-NAME,Steam.exe,DIRECT',
          'DOMAIN-SUFFIX,example.com,REJECT',
          'MATCH,DIRECT',
        ]),
      );
      expect(result['rule'].toString(), isNot(contains('disabled')));
      expect(
        result['dns']['nameserver'],
        contains('https://9.9.9.9/dns-query'),
      );
      expect(result['dns']['ipv6'], false);
      expect(result['dns']['future-dns-field'], 42);
      expect(result['sniffer']['enable'], true);
      expect(result['proxies'][0]['reality-opts']['public-key'], 'preserved');
      expect(
        result['proxies'][0]['reality-opts']['support-x25519mlkem768'],
        true,
      );
      expect(result['future'], {'keep': true});
      expect(archive.encode(), before);
    },
  );

  test(
    'AI-DNS global mode becomes rule mode and uses regional bootstrap and direct AI routes',
    () {
      final result = configuredProfile(
        sample({'routeMode': 'global', 'aiDns': true, 'aiDnsRegion': 'EU'}),
        selected: 'Finland',
      );
      expect(result['mode'], 'rule');
      expect(result['rule'].first, 'DOMAIN,gemini.google.com,DIRECT');
      expect(result['rule'].last, 'MATCH,VPN');
      expect(result['dns']['default-nameserver'], contains('5.175.161.3'));
      expect(result['dns']['nameserver-policy']['gemini.google.com'], [
        'https://eu.geohide.ru/dns-query',
      ]);
      expect(result['dns']['nameserver-policy']['kept.example'], ['1.2.3.4']);
      expect(result['dns']['future-dns-field'], 42);
    },
  );

  test('AI-DNS does not override explicit advanced routing', () {
    final result = configuredProfile(
      sample({
        'aiDns': true,
        'advancedRules': {
          'enabled': true,
          'text': 'DOMAIN,gemini.google.com,REJECT',
          'fallback': '@VPN',
        },
      }),
      selected: 'Finland',
    );
    expect(result['rule'], ['DOMAIN,gemini.google.com,REJECT', 'MATCH,VPN']);
  });

  test('custom groups reject cycles, collisions and missing targets', () {
    for (final groups in [
      [
        {'name': 'A', 'target': 'B'},
        {'name': 'B', 'target': 'A'},
      ],
      [
        {'name': 'VPN', 'target': 'DIRECT'},
      ],
      [
        {'name': 'A', 'target': 'DIRECT'},
        {'name': 'A', 'target': 'DIRECT'},
      ],
      [
        {'name': 'A', 'target': 'missing'},
      ],
    ]) {
      expect(
        () => configuredProfile(
          sample({
            'advancedRules': {'enabled': true, 'groups': groups},
          }),
          selected: 'Finland',
        ),
        throwsFormatException,
      );
    }
    final valid = configuredProfile(
      sample({
        'advancedRules': {
          'enabled': true,
          'text': 'MATCH,A',
          'groups': [
            {'name': 'A', 'target': 'B'},
            {'name': 'B', 'target': '@VPN'},
          ],
        },
      }),
      selected: 'Finland',
    );
    expect(valid['proxy-groups'].last['proxies'], ['VPN']);
  });

  test(
    'core grammar rejects unsupported RE2 expressions, invalid CIDRs and flags',
    () {
      for (final line in [
        r'DOMAIN-REGEX,(?<=a)b,DIRECT',
        r'PROCESS-NAME-REGEX,(a)\1,DIRECT',
        'DOMAIN,a.local,DIRECT,no-resolve',
        'IP-CIDR,999.1.2.3/32,DIRECT',
        'IP-CIDR6,2001:db8::/129,DIRECT',
        'NETWORK,http,DIRECT',
        'DST-PORT,65536,DIRECT',
      ]) {
        expect(validateRules(line), isNotEmpty, reason: line);
      }
      expect(
        validateRules(
          r'PROCESS-NAME-REGEX,(?i)(steam|a{1,3}),DIRECT'
          '\nIP-CIDR6,2001:db8::/32,DIRECT,no-resolve',
        ),
        isEmpty,
      );
      expect(normalizeDnsResolver('udp://1.2.3.4:53'), '1.2.3.4');
      expect(normalizeDnsResolver('tls://1.1.1.1'), isNull);
      expect(
        () => configuredProfile(
          sample({
            'dnsMode': 'custom',
            'dnsCustom': ['tls://1.1.1.1'],
          }),
          selected: 'Finland',
        ),
        throwsFormatException,
      );
    },
  );
}
