import 'dart:convert';
import 'package:dix/platform/core_selection.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> node() => {'type': 'Vless'};
Map<String, dynamic> group(List<String> children, String now) => {
  'type': 'Selector',
  'all': children,
  'now': now,
};

void main() {
  test('effective catch-all chooses its actual automatic routing group', () {
    final source = <String, dynamic>{
      'proxies': [
        {'name': 'A'},
        {'name': 'B'},
      ],
      'proxy-groups': [
        {
          'name': 'Original',
          'type': 'select',
          'proxies': ['A', 'B'],
        },
        {
          'name': 'Forced',
          'type': 'select',
          'proxies': ['A'],
        },
        {
          'name': 'Effective',
          'type': 'url-test',
          'proxies': ['A', 'B'],
        },
      ],
      'rules': ['MATCH,Original'],
      'rule': [
        'DOMAIN,forced.example,Forced',
        'DOMAIN,main.example,Effective',
        'MATCH,Effective',
      ],
    };
    final before = jsonEncode(source);
    expect(mainRoutingGroup(source), 'Effective');
    final prepared = prepareManualRoutingProfile(source, selectedServer: 'B');
    expect(prepared.profile['rule'], [
      'DOMAIN,forced.example,Forced',
      'DOMAIN,main.example,${prepared.rootGroup}',
      'MATCH,${prepared.rootGroup}',
    ]);
    expect(prepared.profile['proxy-groups'][2]['type'], 'url-test');
    expect(jsonEncode(source), before);
  });

  test('explicit direct and reject catch-all policies remain explicit', () {
    for (final target in ['DIRECT', 'REJECT']) {
      final source = <String, dynamic>{
        'proxies': [
          {'name': 'A'},
        ],
        'proxy-groups': [
          {
            'name': 'Main',
            'type': 'select',
            'proxies': ['A'],
          },
        ],
        'rules': ['DOMAIN,main.example,Main', 'MATCH,$target'],
      };
      expect(mainRoutingGroup(source), 'Main');
      final prepared = prepareManualRoutingProfile(source);
      expect(prepared.profile['rules'], [
        'DOMAIN,main.example,${prepared.rootGroup}',
        'MATCH,$target',
      ]);
    }
  });

  test(
    'all traffic mode has an explicit manual route without relying on GLOBAL',
    () {
      final prepared = prepareManualRoutingProfile({
        'mode': 'global',
        'proxies': [
          {'name': 'A', 'type': 'http'},
          {'name': 'B', 'type': 'http'},
        ],
        'proxy-groups': [
          {
            'name': 'Auto',
            'type': 'url-test',
            'proxies': ['A', 'B'],
          },
        ],
        'rule': ['MATCH,Auto'],
      }, selectedServer: 'A');
      expect(prepared.profile['mode'], 'rule');
      expect(prepared.profile['rule'], ['MATCH,${prepared.rootGroup}']);
      expect(prepared.profile['proxy-groups'].first['type'], 'url-test');
    },
  );

  test(
    'manual routing leaves automatic and forced groups intact, source unchanged',
    () {
      final source = <String, dynamic>{
        'proxies': [
          {'name': 'A'},
          {'name': 'B'},
        ],
        'proxy-groups': [
          {
            'name': 'Auto',
            'type': 'url-test',
            'proxies': ['A', 'B'],
          },
          {
            'name': 'Bank',
            'type': 'select',
            'proxies': ['DIRECT'],
          },
        ],
        'rules': [
          'DOMAIN,bank.example,Bank',
          'IP-CIDR,1.2.3.0/24,Auto,no-resolve',
          'MATCH,Auto',
        ],
      };
      final before = jsonEncode(source);
      final prepared = prepareManualRoutingProfile(source);
      expect(jsonEncode(source), before);
      expect(prepared.profile['proxy-groups'][0]['type'], 'url-test');
      expect(prepared.profile['rules'], [
        'DOMAIN,bank.example,Bank',
        'IP-CIDR,1.2.3.0/24,${prepared.rootGroup},no-resolve',
        'MATCH,${prepared.rootGroup}',
      ]);
    },
  );

  late Map<String, dynamic> proxies;
  late List<String> calls;
  late String? fail;
  Future<dynamic> rpc(String method, dynamic data) async {
    if (method == 'getProxies') return jsonEncode({'proxies': proxies});
    final request = jsonDecode(data as String) as Map;
    final group = request['group-name'] as String;
    final target = request['proxy-name'] as String;
    calls.add('$group:$target');
    if (fail == '$group:$target') return 'Not found group';
    proxies[group]['now'] = target;
    return '';
  }

  setUp(() {
    proxies = {
      'A': node(),
      'B': node(),
      'DIRECT': {'type': 'Direct'},
    };
    calls = [];
    fail = null;
  });

  test(
    'missing imported group and absent GLOBAL select live routing root',
    () async {
      proxies['VPN'] = group(['A', 'B'], 'A');
      final selected = await selectRuntimeServer(
        rpc,
        preferredGroup: 'Old',
        server: 'B',
      );
      expect(selected, {'VPN': 'B'});
      expect(calls, ['VPN:B']);
    },
  );

  test(
    'nested selectors change from leaf to root and leave forced groups alone',
    () async {
      proxies.addAll({
        'VPN': group(['DIRECT', 'Region'], 'DIRECT'),
        'Region': group(['A', 'B'], 'A'),
        'Russian sites': group(['DIRECT'], 'DIRECT'),
        'GLOBAL': group(['VPN', 'A', 'B'], 'A'),
      });
      await selectRuntimeServer(
        rpc,
        preferredGroup: 'Missing',
        rootGroup: 'VPN',
        server: 'B',
      );
      expect(calls, ['Region:B', 'VPN:Region', 'GLOBAL:B']);
      expect(proxies['Russian sites']['now'], 'DIRECT');
    },
  );

  test('partial failure restores leaf and root in reverse order', () async {
    proxies.addAll({
      'VPN': group(['DIRECT', 'Region'], 'DIRECT'),
      'Region': group(['A', 'B'], 'A'),
    });
    fail = 'VPN:Region';
    await expectLater(
      selectRuntimeServer(rpc, preferredGroup: 'VPN', server: 'B'),
      throwsStateError,
    );
    expect(calls, ['Region:B', 'VPN:Region', 'VPN:DIRECT', 'Region:A']);
    expect(proxies['Region']['now'], 'A');
  });

  test(
    'automatic groups cannot silently claim to select an arbitrary node',
    () async {
      proxies['VPN'] = group(['Auto'], 'Auto');
      proxies['Auto'] = {
        'type': 'URLTest',
        'all': ['A', 'B'],
        'now': 'A',
      };
      await expectLater(
        selectRuntimeServer(rpc, preferredGroup: 'VPN', server: 'B'),
        throwsStateError,
      );
      expect(calls, isEmpty);
    },
  );

  test('global mode uses GLOBAL and leaves rule groups untouched', () async {
    proxies['VPN'] = group(['A', 'B'], 'A');
    proxies['GLOBAL'] = group(['A', 'B'], 'A');
    await selectRuntimeServer(
      rpc,
      preferredGroup: 'VPN',
      server: 'B',
      global: true,
    );
    expect(calls, ['GLOBAL:B']);
  });

  test('cycles and unknown node fail without mutation', () async {
    proxies['VPN'] = group(['VPN'], 'VPN');
    await expectLater(
      selectRuntimeServer(rpc, preferredGroup: 'VPN', server: 'B'),
      throwsStateError,
    );
    await expectLater(
      selectRuntimeServer(rpc, preferredGroup: 'VPN', server: 'Unknown'),
      throwsStateError,
    );
    expect(calls, isEmpty);
  });

  test(
    'ambiguous routing roots require explicit root and do not guess',
    () async {
      proxies['VPN'] = group(['A', 'B'], 'A');
      proxies['Other'] = group(['A', 'B'], 'A');
      await expectLater(
        selectRuntimeServer(rpc, preferredGroup: 'Missing', server: 'B'),
        throwsStateError,
      );
      expect(calls, isEmpty);
    },
  );
}
