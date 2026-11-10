import 'archive.dart';

// These endpoints and defaults match the Windows Dix configuration pipeline.
const dnsFallback = [
  'https://1.1.1.1/dns-query',
  'https://8.8.8.8/dns-query',
  'https://94.140.14.14/dns-query',
];
const dnsPresets = {
  'cloudflare': ['https://1.1.1.1/dns-query', 'https://1.0.0.1/dns-query'],
  'google': ['https://8.8.8.8/dns-query', 'https://8.8.4.4/dns-query'],
  'adguard': [
    'https://94.140.14.14/dns-query',
    'https://94.140.15.15/dns-query',
  ],
  'quad9': ['https://9.9.9.9/dns-query', 'https://149.112.112.112/dns-query'],
};
const aiDomains = [
  'gemini.google.com',
  'aistudio.google.com',
  'generativelanguage.googleapis.com',
  'alkalimakersuite-pa.clients6.google.com',
  'labs.google',
  'aisandbox-pa.googleapis.com',
  'accounts.google.com',
  'oauth2.googleapis.com',
  'www.gstatic.com',
  'gemini.gstatic.com',
  'fonts.gstatic.com',
  'lh3.googleusercontent.com',
  'clients2.googleusercontent.com',
  'ogads-pa.clients6.google.com',
  'signaler-pa.clients6.google.com',
  'waa-pa.clients6.google.com',
  'bard.google.com',
  'ai.google.dev',
  'assistant.google.com',
  'robinfrontend-pa.googleapis.com',
  'robinhood-pa.googleapis.com',
  'assistantsdk-pa.googleapis.com',
  'bard-pa.googleapis.com',
  'geminigenerativeapis.googleapis.com',
];
const aiGatewayDomains = [
  'gemini.google.com',
  'aistudio.google.com',
  'generativelanguage.googleapis.com',
  'alkalimakersuite-pa.clients6.google.com',
  'labs.google',
  'aisandbox-pa.googleapis.com',
  'ai.google.dev',
  'robinfrontend-pa.googleapis.com',
];
const aiDnsRegions = {
  'RU': (
    'https://geohide.ru/dns-query',
    [
      '159.194.200.33',
      '193.233.112.67',
      '193.233.112.88',
      '37.230.192.51',
      '46.8.158.6',
      '193.233.112.68',
    ],
  ),
  'EU': (
    'https://eu.geohide.ru/dns-query',
    [
      '5.175.161.3',
      '5.175.161.40',
      '45.13.237.213',
      '31.25.239.132',
      '143.20.64.192',
    ],
  ),
  'US': (
    'https://us.geohide.ru/dns-query',
    ['192.255.159.240', '192.255.159.241', '192.3.233.253', '107.175.76.134'],
  ),
};

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : [];

String? normalizeDnsResolver(String source) {
  final value = source.trim();
  if (value.isEmpty) return null;
  final plain = RegExp(
    r'^(?:udp|plain|dns)://(\d{1,3}(?:\.\d{1,3}){3})(?::(\d+))?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (plain != null) {
    final ip = plain[1]!;
    if (ip.split('.').any((part) => int.parse(part) > 255)) return null;
    final port = int.tryParse(plain[2] ?? '53');
    if (port == null || port < 1 || port > 65535) return null;
    return port == 53 ? ip : '$ip:$port';
  }
  if (value.contains(':853') ||
      RegExp(r'^(tls|quic)://', caseSensitive: false).hasMatch(value)) {
    return null;
  }
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.host.isNotEmpty && uri.userInfo.isEmpty
        ? value
        : null;
  }
  if (RegExp(r'^[a-z0-9.-]+$', caseSensitive: false).hasMatch(value)) {
    return 'https://$value/dns-query';
  }
  return null;
}

/// Mutates only the cloned effective profile, never the stored subscription.
void configureNetwork(
  Map<String, dynamic> config,
  Map<String, dynamic> settings, {
  required bool advanced,
}) {
  final ai = settings['aiDns'] == true, ru = settings['ruOptimization'] == true;
  final dns = jsonMap(config['dns']);
  final policy = jsonMap(dns['nameserver-policy'] ?? dns['nameserverPolicy']);
  final region = aiDnsRegions[settings['aiDnsRegion']] ?? aiDnsRegions['RU']!;
  final mode = settings['dnsMode']?.toString() ?? 'auto';
  final user = mode == 'custom'
      ? _strings(settings['dnsCustom'])
      : dnsPresets[mode] ?? <String>[];
  if (mode == 'custom' &&
      (user.isEmpty || user.any((s) => normalizeDnsResolver(s) == null))) {
    throw const FormatException(
      'Укажите корректные DNS-серверы: HTTPS или udp://IP',
    );
  }
  final resolvers = {
    ...user.map(normalizeDnsResolver).whereType<String>(),
    if (ru) 'https://common.dot.dns.yandex.net/dns-query',
    ...dnsFallback,
  }.toList();
  if (ai) {
    for (final domain in aiDomains) {
      policy[domain] = [region.$1];
      policy['+.$domain'] = [region.$1];
    }
    final hosts = jsonMap(config['hosts'])..remove('xbox-dns.ru');
    if (hosts.isEmpty) {
      config.remove('hosts');
    } else {
      config['hosts'] = hosts;
    }
    config['dns'] = {
      ...dns,
      'enable': true,
      'ipv6': true,
      'use-hosts': true,
      'use-system-hosts': true,
      'respect-rules': false,
      'default-nameserver': region.$2,
      'enhanced-mode': 'fake-ip',
      'fake-ip-range': '198.18.0.1/16',
      'fake-ip-filter': {
        ..._strings(dns['fake-ip-filter']),
        ...aiDomains,
        ...aiDomains.map((d) => '*.$d'),
        '*.lan',
        'localhost.ptlogin2.qq.com',
        '*.ru',
        '*.yandex.ru',
        'ya.ru',
        '*.google.com',
        'mail.google.com',
        '*.instagram.com',
        '*.facebook.com',
        '*.youtube.com',
        '*.vk.com',
      }.toList(),
      'nameserver': dnsFallback,
      'fallback': dnsFallback,
      'proxy-server-nameserver': dnsFallback,
      'nameserver-policy': policy,
      'fallback-filter': {
        'geoip': false,
        'geoip-code': 'CN',
        'geosite': ['gfw'],
        'ipcidr': [],
        'domain': [],
      },
    };
    if (!advanced) {
      config['rule'] = [
        for (final domain in aiDomains) ...[
          'DOMAIN,$domain,DIRECT',
          'DOMAIN-SUFFIX,$domain,DIRECT',
        ],
        ..._strings(config['rule']),
      ];
    }
  } else {
    config['dns'] = {
      ...dns,
      'enable': true,
      if (ru) 'ipv6': false,
      'enhanced-mode': 'redir-host',
      'proxy-server-nameserver': resolvers
          .where((s) => s.startsWith('http'))
          .toList(),
      if (mode != 'auto' || _strings(dns['nameserver']).isEmpty)
        'nameserver': resolvers,
      'default-nameserver': {
        if (ru) ...['77.88.8.8', '77.88.8.1'],
        ..._strings(dns['default-nameserver']),
        '8.8.8.8',
        '1.1.1.1',
        if (!ru) ...['77.88.8.8', '77.88.8.1'],
      }.toList(),
    };
  }
  final sniffer = jsonMap(config['sniffer']);
  final sniff = jsonMap(sniffer['sniff']);
  for (final type in ['TLS', 'QUIC']) {
    if (sniff[type] is Map) {
      sniff[type] = {...jsonMap(sniff[type]), 'override-destination': false};
    }
  }
  config['sniffer'] = {
    ...sniffer,
    'override-destination': false,
    if (sniff.isNotEmpty) 'sniff': sniff,
    if (ai || ru) ...{
      'enable': true,
      'parse-pure-ip': true,
      if (ai)
        'override-destination-for': aiGatewayDomains
            .map((d) => '+.$d')
            .toList(),
      if (ru && !ai) 'force-dns-mapping': true,
      'sniff': {
        'HTTP': {
          'ports': ['80', '8080-8880'],
          'override-destination': ru && !ai,
        },
        for (final type in ['TLS', 'QUIC'])
          type: {
            'ports': ['443', '8443'],
            'override-destination': false,
          },
      },
    },
  };
  for (final proxy in (config['proxies'] as List? ?? []).whereType<Map>()) {
    if (proxy['reality-opts'] is Map) {
      proxy['reality-opts'] = {
        ...jsonMap(proxy['reality-opts']),
        'support-x25519mlkem768': true,
      };
      proxy['client-fingerprint'] = 'chrome';
    }
  }
}
