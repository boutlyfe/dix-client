import 'dart:convert';
import 'dart:io';
import 'core_rpc.dart';
import 'core_status.dart';

/// One configuration path is used by the app and the isolated real-engine test.
/// Imported listeners and control APIs must not bind unexpected system ports.
Map<String, dynamic> ownedCoreConfig(Map<String, dynamic> profile) {
  final effective = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(profile)) as Map,
  );
  for (final field in ['port', 'socks-port', 'redir-port', 'tproxy-port']) {
    effective[field] = 0;
  }
  for (final field in [
    'external-controller',
    'external-controller-tls',
    'external-controller-unix',
    'external-controller-pipe',
    'external-doh-server',
    'ss-config',
    'vmess-config',
  ]) {
    effective[field] = '';
  }
  effective['listeners'] = [];
  effective['tunnels'] = [];
  effective['allow-lan'] = false;
  effective['bind-address'] = '127.0.0.1';
  effective['dns'] = {
    ...Map<String, dynamic>.from(effective['dns'] as Map? ?? {}),
    'listen': '',
  };
  return effective;
}

Future<void> applyCoreProfile(
  CoreRpc rpc,
  Map<String, dynamic> profile, {
  required bool tun,
  Map<String, dynamic> selected = const {},
  bool startListener = true,
}) async {
  var effective = ownedCoreConfig(profile);
  void check(dynamic result) {
    if (result is String && result.trim().isNotEmpty) {
      throw FormatException(result);
    }
    if (result == false) throw StateError('Ядро отклонило конфигурацию');
  }

  // Mihomo's file parser accepts raw YAML/JSON types, while setupConfig expects
  // its normalized JSON schema (for example sniff ports must be strings).
  // The file parser uses `rules`; the bridge's normalized result uses `rule`.
  final raw = {
    ...effective,
    if (effective['rule'] != null) 'rules': effective['rule'],
  }..remove('rule');
  check(await rpc.call('validateConfig', jsonEncode(raw)));
  final directory = rpc.homeDirectory;
  if (directory == null) throw StateError('Не задан рабочий каталог ядра');
  final source = File(
    '$directory/effective-$pid-${DateTime.now().microsecondsSinceEpoch}.json',
  );
  try {
    await source.writeAsString(jsonEncode(raw), flush: true);
    var normalized = await rpc.call(
      'getConfig',
      source.path,
      const Duration(seconds: 120),
    );
    if (normalized is String) {
      try {
        normalized = jsonDecode(normalized);
      } catch (_) {
        throw FormatException(normalized);
      }
    }
    if (normalized is! Map) {
      throw const FormatException('Ядро не вернуло конфигурацию');
    }
    effective = ownedCoreConfig(Map<String, dynamic>.from(normalized));
  } finally {
    if (await source.exists()) await source.delete();
  }

  check(
    await rpc.call(
      'setupConfig',
      jsonEncode({
        'config': effective,
        'selected-map': selected,
        'test-url': 'https://www.gstatic.com/generate_204',
      }),
      const Duration(seconds: 120),
    ),
  );
  // This custom engine expects general parameters and the complete TUN schema
  // in separate calls. A partial TUN schema crashes its updateConfig handler.
  check(
    await rpc.call(
      'updateConfig',
      jsonEncode({
        'mixed-port': effective['mixed-port'],
        'mode': effective['mode'],
        'allow-lan': false,
        'external-controller': '',
        'unified-delay': true,
        'tcp-concurrent': true,
      }),
      const Duration(seconds: 120),
    ),
  );
  check(
    await rpc.call(
      'updateConfig',
      jsonEncode({
        'tun': {
          ...Map<String, dynamic>.from(effective['tun'] as Map? ?? {}),
          'enable': tun,
          'device': 'Dix Flutter',
          'stack': 'mixed',
          'dns-hijack': ['any:53'],
          'auto-route': true,
          'route-address': [],
        },
      }),
      const Duration(seconds: 120),
    ),
  );
  if (startListener) {
    check(await rpc.call('startListener', null, const Duration(seconds: 60)));
    if (tun) {
      await requireStartedTun((method, data) => rpc.call(method, data));
    }
  }
}
