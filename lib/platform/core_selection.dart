import 'dart:convert';

typedef SelectionRpc = Future<dynamic> Function(String method, dynamic data);

class ManualRoutingProfile {
  const ManualRoutingProfile(this.profile, this.rootGroup);
  final Map<String, dynamic> profile;
  final String rootGroup;
}

/// Resolve the main destination from the effective catch-all rule. Provider
/// group order does not indicate which group application rules actually use.
String? mainRoutingGroup(Map<String, dynamic> profile) {
  final groups =
      (profile['proxy-groups'] ?? profile['proxyGroups'] ?? []) as List;
  final names = groups
      .whereType<Map>()
      .map((group) => group['name']?.toString())
      .whereType<String>()
      .where((name) => name.isNotEmpty)
      .toList();
  final rules = (profile['rule'] ?? profile['rules'] ?? []) as List;
  for (final rule in rules.whereType<String>()) {
    final match = RegExp(
      r'^\s*(?:MATCH|FINAL)\s*,\s*(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(rule);
    if (match == null) continue;
    final target = match.group(1)!;
    // DIRECT/REJECT are explicit policies, never rewrite them as a VPN root.
    return target != 'DIRECT' && target != 'REJECT' && names.contains(target)
        ? target
        : names.firstOrNull;
  }
  return names.firstOrNull;
}

/// Adds an app-owned selection point without converting automatic groups or
/// changing explicit rule destinations. The imported document stays intact.
ManualRoutingProfile prepareManualRoutingProfile(
  Map<String, dynamic> source, {
  String? rootGroup,
  String? selectedServer,
}) {
  final profile = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(source)) as Map,
  );
  final groups =
      (profile['proxy-groups'] ?? profile['proxyGroups'] ?? []) as List;
  final nodes = ((profile['proxies'] ?? profile['proxy'] ?? []) as List)
      .whereType<Map>()
      .map((node) => node['name']?.toString())
      .whereType<String>()
      .where((name) => name.isNotEmpty)
      .toSet()
      .toList();
  if (nodes.isEmpty) throw StateError('В профиле нет серверов для выбора.');
  final root = rootGroup ?? mainRoutingGroup(profile) ?? selectedServer;
  final names = {
    ...nodes,
    for (final group in groups.whereType<Map>()) group['name']?.toString(),
    'GLOBAL',
    'DIRECT',
    'REJECT',
  };
  var name = 'Dix · сервер';
  var suffix = 2;
  while (names.contains(name)) {
    name = 'Dix · сервер ${suffix++}';
  }
  profile['proxy-groups'] = [
    ...groups,
    {'name': name, 'type': 'select', 'proxies': nodes},
  ];
  profile.remove('proxyGroups');
  // The bridge's normalized schema uses `rule`, raw Mihomo uses `rules`.
  for (final field in ['rules', 'rule']) {
    if (profile[field] is! List) continue;
    profile[field] = [
      for (final line in profile[field] as List)
        if (line is String) _replaceRoutingTarget(line, root, name) else line,
    ];
  }
  if (profile['mode'] == 'global') {
    // Global remains "all traffic through the chosen server", with an explicit
    // app-owned selector even on engines that omit GLOBAL from getProxies.
    profile['mode'] = 'rule';
    profile['rule'] = ['MATCH,$name'];
    profile.remove('rules');
  }
  return ManualRoutingProfile(profile, name);
}

String _replaceRoutingTarget(String rule, String? root, String replacement) {
  if (root == null || root.isEmpty) return rule;
  // Only the final target (before optional no-resolve) is relevant. Parsing
  // backwards keeps commas in PROCESS-NAME-REGEX and logical rules untouched.
  final tail = RegExp(r',([^,]+)(,no-resolve)?$').firstMatch(rule);
  if (tail == null || tail.group(1) != root) return rule;
  return rule.replaceRange(
    tail.start + 1,
    tail.start + 1 + root.length,
    replacement,
  );
}

/// Selects only groups on the live VPN route. Imported group names and GLOBAL
/// are not guaranteed to exist after the engine normalizes a profile.
Future<Map<String, String>> selectRuntimeServer(
  SelectionRpc call, {
  required String preferredGroup,
  required String server,
  String? rootGroup,
  bool global = false,
}) async {
  dynamic raw = await call('getProxies', null);
  if (raw is String) raw = jsonDecode(raw);
  if (raw is Map && raw['proxies'] is Map) raw = raw['proxies'];
  if (raw is! Map) {
    throw StateError('Ядро не вернуло список серверов. Переподключитесь.');
  }
  final proxies = <String, Map>{
    for (final entry in raw.entries)
      if (entry.value is Map) entry.key.toString(): entry.value as Map,
  };
  if (!proxies.containsKey(server)) {
    throw StateError(
      'Этого сервера нет в подключённом профиле. Обновите список.',
    );
  }
  const reserved = {'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS', 'COMPATIBLE'};
  bool selector(String name) =>
      proxies[name]?['type']?.toString().toLowerCase() == 'selector';
  List<String> children(String name) =>
      (proxies[name]?['all'] as List? ?? []).map((e) => e.toString()).toList();

  // Return leaf-first operations so traffic changes at the routing root last.
  Map<String, String>? path(String name, Set<String> seen) {
    if (name == server) return {};
    if (reserved.contains(name) || !seen.add(name)) return null;
    final options = children(name);
    if (selector(name)) {
      final ordered = [
        if (options.contains(server)) server,
        ...options.where((n) => n != server && n != 'GLOBAL'),
      ];
      for (final child in ordered) {
        final nested = path(child, {...seen});
        if (nested != null) return {...nested, name: child};
      }
    } else if (options.length == 1) {
      // An immutable alias with one destination needs no selection operation.
      return path(options.single, {...seen});
    }
    return null;
  }

  Map<String, String>? plan;
  final explicit = global
      ? 'GLOBAL'
      : rootGroup != null && proxies.containsKey(rootGroup)
      ? rootGroup
      : proxies.containsKey(preferredGroup)
      ? preferredGroup
      : null;
  if (explicit != null) {
    plan = path(explicit, {});
  } else if (!global) {
    // Favor outer routing groups over aliases and nested selectors. Never
    // blindly update every group: custom rules can intentionally force DIRECT.
    final referenced = {
      for (final name in proxies.keys)
        if (name != 'GLOBAL') ...children(name),
    };
    final roots = proxies.keys.where(
      (n) => n != 'GLOBAL' && selector(n) && !referenced.contains(n),
    );
    final candidates = roots
        .map((name) => path(name, {}))
        .whereType<Map<String, String>>()
        .toList();
    if (candidates.length == 1) plan = candidates.single;
  }
  if (plan == null) {
    throw StateError(
      'В этом профиле нельзя выбрать сервер вручную в текущей группе. '
      'Выберите группу с ручным выбором или переподключитесь.',
    );
  }

  // Keep GLOBAL ready for switching routing modes when it exists and exposes
  // this node. Its absence is normal for some versions of the core.
  if (!global && selector('GLOBAL')) {
    final globalPath = path('GLOBAL', {});
    if (globalPath != null &&
        globalPath.entries.every(
          (entry) =>
              entry.key == 'GLOBAL' ||
              plan![entry.key] == entry.value ||
              proxies[entry.key]?['now'] == entry.value,
        )) {
      for (final entry in globalPath.entries) {
        if (entry.key == 'GLOBAL' || !plan.containsKey(entry.key)) {
          plan[entry.key] = entry.value;
        }
      }
    }
  }
  final changed = <String, String>{};
  final previous = <String, String>{};
  Future<void> change(String group, String target) async {
    final result = await call(
      'changeProxy',
      jsonEncode({'group-name': group, 'proxy-name': target}),
    );
    if (result == false || (result is String && result.trim().isNotEmpty)) {
      throw StateError('Ядро не смогло сменить сервер. Попробуйте ещё раз.');
    }
  }

  try {
    for (final entry in plan.entries) {
      final now = proxies[entry.key]?['now']?.toString();
      if (now == entry.value) continue;
      // Refuse an operation we could not restore after a partial failure.
      if (now == null || !children(entry.key).contains(now)) {
        throw StateError(
          'Состояние группы изменилось. Обновите список серверов.',
        );
      }
      previous[entry.key] = now;
      // Include attempted writes: a timeout can follow a successful core write.
      changed[entry.key] = entry.value;
      await change(entry.key, entry.value);
    }
  } catch (error) {
    var restored = true;
    for (final group in changed.keys.toList().reversed) {
      try {
        await change(group, previous[group]!);
      } catch (_) {
        restored = false;
      }
    }
    if (!restored) {
      throw StateError(
        'Не удалось восстановить выбор сервера. Переподключитесь.',
      );
    }
    rethrow;
  }
  return plan;
}
