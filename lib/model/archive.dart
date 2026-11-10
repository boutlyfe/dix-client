import 'dart:convert';
import 'package:yaml/yaml.dart';

const dashboardWidgetIds = {
  'connection',
  'server',
  'mode',
  'traffic',
  'stats',
  'ip',
  'controls',
  'graph',
  'speed',
  'subscriptions',
  'support',
};
Map<String, dynamic> jsonMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

/// The archive is the compatibility boundary. Unknown settings and profiles survive
/// an import/export cycle, including options not yet exposed by the Flutter UI.
class DixArchive {
  final Map<String, dynamic> document;
  Object? _cachedRaw;
  Map<String, dynamic>? _cachedProfile;
  List<DixServer>? _cachedServers;
  DixArchive(Map<String, dynamic> value)
    : document = jsonMap(jsonDecode(jsonEncode(value)));
  factory DixArchive.empty() => DixArchive({
    'settings': {'appearance': 'minimal', 'theme': 'dark'},
    'profiles': <String, dynamic>{},
  });
  factory DixArchive.decode(String source) {
    final parsed = jsonDecode(source);
    if (parsed is! Map) throw const FormatException('Ожидается JSON-объект');
    final root = jsonMap(parsed);
    if (root.containsKey('settings') && root['settings'] is! Map) {
      throw const FormatException('Некорректные настройки в резервной копии');
    }
    if (root.containsKey('profiles') && root['profiles'] is! Map) {
      throw const FormatException('Некорректные профили в резервной копии');
    }
    return DixArchive(
      root.containsKey('settings')
          ? root
          : {'settings': root, 'profiles': <String, dynamic>{}},
    );
  }
  Map<String, dynamic> _section(String key) {
    final existing = document[key];
    if (existing is Map<String, dynamic>) return existing;
    final normalized = jsonMap(existing);
    document[key] = normalized;
    return normalized;
  }

  Map<String, dynamic> get settings => _section('settings');
  Map<String, dynamic> get profiles => _section('profiles');
  String get appearance =>
      settings['appearance'] == 'classic' ? 'classic' : 'minimal';
  bool get light => settings['theme'] == 'light';
  List<Map<String, dynamic>> get subscriptions =>
      ((settings['subs'] ?? settings['subscriptions']) as List? ?? [])
          .whereType<Map>()
          .map((e) => jsonMap(e))
          .toList();
  String? get activeId =>
      settings['activeSub']?.toString() ?? profiles.keys.firstOrNull;
  Map<String, dynamic> get activeProfile {
    final raw = profiles[activeId];
    if (_cachedProfile == null || !identical(raw, _cachedRaw)) {
      final parsed = parseProfile(raw);
      _cachedRaw = raw;
      _cachedProfile = parsed;
      _cachedServers = null;
    }
    return _cachedProfile!;
  }

  List<DixServer> get servers {
    final profile = activeProfile;
    return _cachedServers ??= DixServer.fromProfile(profile);
  }

  List<String> get activeWidgetIds => ((settings['layout'] as List?) ?? [])
      .whereType<Map>()
      .where((e) => e['on'] != false)
      .map((e) => e['id'].toString())
      .where((id) => dashboardWidgetIds.contains(id))
      .toList();
  String encode() => const JsonEncoder.withIndent('  ').convert(document);
  DixArchive clone() => DixArchive(document);
}

Map<String, dynamic> parseProfile(Object? raw) {
  if (raw is Map) return jsonMap(raw);
  if (raw is! String || raw.trim().isEmpty) return {};
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    decoded = loadYaml(raw);
  }
  return jsonMap(normalizeYaml(decoded));
}

Object? normalizeYaml(Object? value) {
  if (value is Map) {
    return {
      for (final e in value.entries) e.key.toString(): normalizeYaml(e.value),
    };
  }
  if (value is List) return value.map(normalizeYaml).toList();
  return value;
}

class DixServer {
  final String name, type, group;
  final Map<String, dynamic> raw;
  const DixServer(this.name, this.type, this.group, this.raw);
  String get displayName => name
      .replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '')
      .trim();
  String? get countryCode {
    final match = RegExp(
      r'([\u{1F1E6}-\u{1F1FF}]{2})',
      unicode: true,
    ).firstMatch(name);
    if (match == null) return null;
    return String.fromCharCodes(
      match.group(1)!.runes.map((code) => code - 0x1f1e6 + 65),
    );
  }

  double get latitude => switch (_country) {
    'fi' => 60.17,
    'de' => 50.11,
    'nl' => 52.37,
    'ru' => 55.75,
    'us' => 40.71,
    'jp' => 35.68,
    'se' => 59.33,
    'fr' => 48.85,
    _ => 51.51,
  };
  double get longitude => switch (_country) {
    'fi' => 24.94,
    'de' => 8.68,
    'nl' => 4.90,
    'ru' => 37.62,
    'us' => -74.01,
    'jp' => 139.69,
    'se' => 18.07,
    'fr' => 2.35,
    _ => -0.13,
  };
  String get _country {
    final n = name.toLowerCase();
    for (final e in {
      'fi': ['🇫🇮', 'финлян', 'finland', 'helsinki'],
      'de': ['🇩🇪', 'герман', 'germany', 'frankfurt'],
      'nl': ['🇳🇱', 'нидер', 'nether', 'amsterdam'],
      'ru': ['🇷🇺', 'росси', 'russia', 'москва'],
      'us': ['🇺🇸', 'сша', 'united states'],
      'jp': ['🇯🇵', 'япони', 'japan'],
      'se': ['🇸🇪', 'швец', 'sweden'],
      'fr': ['🇫🇷', 'франц', 'france'],
    }.entries) {
      if (e.value.any(n.contains)) return e.key;
    }
    return 'gb';
  }

  static List<DixServer> fromProfile(Map<String, dynamic> config) {
    final proxies = (config['proxies'] ?? config['proxy']) as List? ?? [];
    final groups =
        (config['proxy-groups'] ?? config['proxyGroups']) as List? ?? [];
    return proxies.whereType<Map>().where((p) => p['name'] is String).map((p) {
      final name = p['name'] as String;
      final group = groups
          .whereType<Map>()
          .where((g) => (g['proxies'] as List? ?? []).contains(name))
          .firstOrNull;
      return DixServer(
        name,
        (p['type'] ?? 'VPN').toString(),
        (group?['name'] ?? 'Серверы').toString(),
        jsonMap(p),
      );
    }).toList();
  }
}
