import 'dart:convert';
import 'archive.dart';
import 'profile_network.dart';

const ruleTypes = [
  'DOMAIN',
  'DOMAIN-SUFFIX',
  'DOMAIN-KEYWORD',
  'DOMAIN-REGEX',
  'GEOSITE',
  'GEOIP',
  'IP-CIDR',
  'IP-CIDR6',
  'SRC-IP-CIDR',
  'IP-ASN',
  'SRC-IP-ASN',
  'PROCESS-NAME',
  'PROCESS-NAME-REGEX',
  'PROCESS-PATH',
  'PROCESS-PATH-REGEX',
  'DST-PORT',
  'SRC-PORT',
  'NETWORK',
  'MATCH',
];

/// Split only outside regex parentheses/classes, so {1,3} and (a,b) stay intact.
List<String> ruleFields(String source) {
  final fields = <String>[];
  var start = 0, depth = 0, braces = 0;
  var inClass = false, escape = false;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (c == r'\') {
      escape = true;
      continue;
    }
    if (c == '[') inClass = true;
    if (c == ']') inClass = false;
    if (!inClass) {
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == '{') braces++;
      if (c == '}') braces--;
    }
    if (c == ',' && !inClass && depth == 0 && braces == 0) {
      fields.add(source.substring(start, i).trim());
      start = i + 1;
    }
  }
  fields.add(source.substring(start).trim());
  return fields;
}

bool _validCidr(String value, {required bool ipv6}) {
  final pieces = value.split('/');
  if (pieces.length > 2) return false;
  if (pieces.length == 2) {
    final prefix = int.tryParse(pieces.last);
    if (prefix == null || prefix < 0 || prefix > (ipv6 ? 128 : 32)) {
      return false;
    }
  }
  final ip = pieces.first;
  if (!ipv6) {
    final bytes = ip.split('.');
    return bytes.length == 4 &&
        bytes.every(
          (s) => RegExp(r'^\d{1,3}$').hasMatch(s) && int.parse(s) <= 255,
        );
  }
  if (!RegExp(r'^[0-9a-fA-F:]+$').hasMatch(ip) || ip.contains(':::')) {
    return false;
  }
  final compressed = ip.split('::');
  if (compressed.length > 2) return false;
  final words = ip.split(':').where((s) => s.isNotEmpty).toList();
  if (words.any((s) => s.length > 4)) return false;
  return compressed.length == 2 ? words.length < 8 : words.length == 8;
}

List<String> validateRules(String text, {Set<String>? targets}) {
  final errors = <String>[];
  var match = false;
  for (final (index, raw) in text.split('\n').indexed) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('- ')) line = line.substring(2).trim();
    final f = ruleFields(line), type = f.first;
    void error(String message) => errors.add('Строка ${index + 1}: $message');
    if (match) error('MATCH должен быть последним правилом');
    if (!ruleTypes.contains(type)) {
      error('Неизвестный тип $type');
      continue;
    }
    final expected = type == 'MATCH' ? 2 : 3;
    if (f.length != expected &&
        !(f.length == expected + 1 && f.last == 'no-resolve')) {
      error('Неверное число полей');
      continue;
    }
    if (f.any((v) => v.isEmpty)) {
      error('Пустое поле');
      continue;
    }
    if (f.length == expected + 1 &&
        ![
          'GEOIP',
          'IP-CIDR',
          'IP-CIDR6',
          'IP-ASN',
          'SRC-IP-CIDR',
          'SRC-IP-ASN',
        ].contains(type)) {
      error('no-resolve допустим только для правил IP');
    }
    final target = f[expected - 1];
    if (targets != null && !targets.contains(target) && target != '@VPN') {
      error('Неизвестная цель $target');
    }
    if (type == 'DOMAIN' || type == 'DOMAIN-SUFFIX') {
      if (f[1].contains(RegExp(r'[\s/:]'))) {
        error('Введите домен без адреса страницы');
      }
    }
    if (type.endsWith('REGEX') &&
        (RegExp(r'\(\?(?:[=!]|<[=!])').hasMatch(f[1]) ||
            RegExp(r'(?<!\\)\\[1-9]').hasMatch(f[1]))) {
      error('Ядро RE2 не поддерживает lookaround и обратные ссылки');
    }
    if (type == 'NETWORK' && !['tcp', 'udp'].contains(f[1].toLowerCase())) {
      error('Протокол должен быть tcp или udp');
    }
    if (['IP-CIDR', 'IP-CIDR6', 'SRC-IP-CIDR'].contains(type) &&
        !_validCidr(
          f[1],
          ipv6:
              type == 'IP-CIDR6' ||
              (type == 'SRC-IP-CIDR' && f[1].contains(':')),
        )) {
      error('Некорректный IP-адрес или префикс подсети');
    }
    if (['DST-PORT', 'SRC-PORT'].contains(type)) {
      final parts = f[1].split('-');
      final values = parts.map(int.tryParse).toList();
      if (parts.length > 2 ||
          values.any((v) => v == null || v < 1 || v > 65535) ||
          (values.length == 2 && values[0]! > values[1]!)) {
        error('Порт должен быть от 1 до 65535 или диапазоном');
      }
    }
    if (type == 'MATCH') match = true;
  }
  return errors;
}

Map<String, dynamic> configuredProfile(
  DixArchive archive, {
  required String selected,
}) {
  final config = jsonMap(jsonDecode(jsonEncode(archive.activeProfile)));
  if (config.isEmpty) throw StateError('Импортируйте профиль с серверами');
  if (archive.settings['flutterOverrideProvider'] == false) {
    // Provider mode, DNS, sniffing and routing remain untouched. Only aliases
    // and the application's private listeners/TUN ownership are normalized.
    config['proxies'] = config['proxies'] ?? config['proxy'] ?? [];
    config['proxy-groups'] =
        config['proxy-groups'] ?? config['proxyGroups'] ?? [];
    config['rule'] = config['rule'] ?? config['rules'] ?? [];
    if (!['rule', 'global', 'direct'].contains(config['mode'])) {
      config['mode'] = 'rule';
    }
    return _ownedProfile(config, archive.settings);
  }
  final groups =
      ((config['proxy-groups'] ?? config['proxyGroups']) as List? ?? [])
          .whereType<Map>()
          .map(jsonMap)
          .toList();
  config['proxies'] = config['proxies'] ?? config['proxy'] ?? [];
  final servers = DixServer.fromProfile(config);
  final known = {
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'PASS',
    'GLOBAL',
    ...servers.map((s) => s.name),
    ...groups.map((g) => g['name'].toString()),
  };
  final advanced = jsonMap(archive.settings['advancedRules']);
  final custom = (advanced['groups'] as List? ?? []).whereType<Map>().toList();
  final reserved = {...known, ...custom.map((g) => g['name'].toString())};
  String alias(String original) {
    if (!original.contains(',')) return original;
    var name = 'VPN ${original.replaceAll(',', ' ')}', i = 2;
    final base = name;
    while (reserved.contains(name)) {
      name = '$base (${i++})';
    }
    reserved.add(name);
    known.add(name);
    groups.add({
      'name': name,
      'type': 'select',
      'proxies': [original],
    });
    return name;
  }

  final vpn = alias(groups.firstOrNull?['name']?.toString() ?? selected);
  final advancedEnabled =
      archive.settings['routeMode'] != 'global' && advanced['enabled'] == true;
  if (advancedEnabled) {
    final customNames = <String>{};
    for (final group in custom) {
      final name = group['name']?.toString().trim() ?? '';
      if (name.isEmpty ||
          name != group['name'] ||
          RegExp(r'[,\r\n]').hasMatch(name) ||
          name == '@VPN' ||
          known.contains(name) ||
          !customNames.add(name)) {
        throw FormatException(
          'Повторяющееся или некорректное имя группы: $name',
        );
      }
    }
    final targets = {
      'DIRECT',
      'REJECT',
      'REJECT-DROP',
      'PASS',
      selected,
      ...groups.whereType<Map>().map((g) => g['name'].toString()),
      ...DixServer.fromProfile(config).map((s) => s.name),
      ...custom.map((g) => g['name'].toString()),
      ...known,
    };
    final links = <String, String>{};
    for (final group in custom) {
      final name = group['name'].toString();
      final target = group['target'] == '@VPN'
          ? vpn
          : group['target']?.toString();
      if (target == null || !targets.contains(target)) {
        throw FormatException('Неизвестная цель группы $name: $target');
      }
      links[name] = target;
    }
    final visited = <String>{}, visiting = <String>{};
    void visit(String name) {
      if (visited.contains(name)) return;
      if (!visiting.add(name)) throw FormatException('Цикл в группах: $name');
      final target = links[name];
      if (target != null && links.containsKey(target)) visit(target);
      visiting.remove(name);
      visited.add(name);
    }

    for (final name in links.keys) {
      visit(name);
    }
    final text = advanced['text']?.toString() ?? '';
    final errors = validateRules(text, targets: targets);
    if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
    final rules = <String>[];
    for (var line in text.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('- ')) line = line.substring(2);
      final f = ruleFields(line);
      final t = f[0] == 'MATCH' ? 1 : 2;
      if (f[t] == '@VPN') f[t] = vpn;
      rules.add(f.join(','));
    }
    if (!rules.any((r) => r.startsWith('MATCH,'))) {
      var fallback = (advanced['fallback'] ?? '@VPN').toString();
      if (fallback == '@VPN') fallback = vpn;
      if (!targets.contains(fallback)) {
        throw FormatException('Неизвестная цель: $fallback');
      }
      rules.add('MATCH,$fallback');
    }
    for (final group in custom) {
      final name = group['name']?.toString() ?? '',
          target = group['target'] == '@VPN'
              ? vpn
              : group['target']?.toString();
      if (name.isEmpty || target == null || !targets.contains(target)) {
        throw const FormatException('Некорректная группа');
      }
      groups.add({
        'name': name,
        'type': 'select',
        'proxies': [target],
      });
    }
    config.remove('rules');
    config['rule'] = rules;
    config['proxy-groups'] = groups;
    config['find-process-mode'] = 'always';
  } else {
    final customRules = <String>[];
    for (final raw
        in (archive.settings['rules'] as List? ?? []).whereType<Map>()) {
      if (raw['enabled'] == false) continue;
      final value = raw['value']?.toString().trim() ?? '';
      if (value.isEmpty || value.contains(',') || value.contains('\n')) {
        throw const FormatException(
          'Некорректное значение сохранённого правила',
        );
      }
      final requested = raw['proxy']?.toString();
      final target = raw['action'] == 'no'
          ? 'DIRECT'
          : raw['action'] == 'block'
          ? 'REJECT'
          : requested != null && known.contains(requested)
          ? alias(requested)
          : vpn;
      final type = {
        'process': 'PROCESS-NAME',
        'domainSuffix': 'DOMAIN-SUFFIX',
        'domainKeyword': 'DOMAIN-KEYWORD',
        'geoSite': 'GEOSITE',
        'geoIp': 'GEOIP',
        'ipCidr': value.contains(':') ? 'IP-CIDR6' : 'IP-CIDR',
      }[raw['type']];
      if (type == null) {
        throw FormatException(
          'Неизвестный тип сохранённого правила: ${raw['type']}',
        );
      }
      if (value == '0.0.0.0/0' || value == '::/0') {
        customRules.add('MATCH,$target');
      } else {
        final normalized = type == 'DOMAIN-SUFFIX'
            ? value.replaceFirst(RegExp(r'^[*+]?\.'), '')
            : value;
        customRules.add(
          '$type,$normalized,$target${['GEOIP', 'IP-CIDR', 'IP-CIDR6'].contains(type) ? ',no-resolve' : ''}',
        );
      }
    }
    if (archive.settings['routeMode'] != 'global') {
      final ruTarget = archive.settings['ruSitesVpn'] == true ? vpn : 'DIRECT';
      config['rule'] = [
        for (final domain in [
          'check-host.net',
          'ipwho.is',
          'ip-api.com',
          'ipapi.co',
        ])
          'DOMAIN-SUFFIX,$domain,$vpn',
        for (final category in [
          'category-ru',
          'category-gov-ru',
          'category-media-ru',
        ])
          'GEOSITE,$category,$ruTarget',
        ...customRules,
        if (!customRules.any((r) => r.startsWith('MATCH,'))) 'MATCH,DIRECT',
      ];
      config['find-process-mode'] = 'always';
    } else {
      config['rule'] = archive.settings['aiDns'] == true
          ? ['MATCH,$vpn']
          : [
              ...customRules,
              ...((config['rule'] ?? config['rules']) as List? ?? [])
                  .whereType<String>(),
            ];
    }
  }
  config.remove('rules');
  config.remove('proxyGroups');
  config.remove('proxy');
  config['proxy-groups'] = groups;
  configureNetwork(config, archive.settings, advanced: advancedEnabled);
  config['mode'] =
      archive.settings['routeMode'] == 'global' &&
          archive.settings['aiDns'] != true
      ? 'global'
      : 'rule';
  return _ownedProfile(config, archive.settings);
}

Map<String, dynamic> _ownedProfile(
  Map<String, dynamic> config,
  Map<String, dynamic> settings,
) {
  config.remove('rules');
  config.remove('proxyGroups');
  config.remove('proxy');
  config['mixed-port'] = 17897;
  config['external-controller'] = '';
  config['allow-lan'] = settings['allowLan'] == true;
  config['unified-delay'] = true;
  config['tcp-concurrent'] = true;
  config['tun'] = {
    ...jsonMap(config['tun']),
    'enable': false,
    'device': 'Dix Flutter',
    'stack': 'mixed',
    'auto-route': true,
    'strict-route': false,
    'auto-detect-interface': true,
    'dns-hijack': ['any:53'],
  };
  return config;
}
