import 'rules.dart';

const disabledRulePrefix = '# dix-disabled: ';

/// The visual editor modifies individual lines; comments and blank lines survive.
class RuleDocument {
  final List<String> lines;
  RuleDocument(String text) : lines = text.split('\n');

  List<int> get indices => [
    for (var i = 0; i < lines.length; i++)
      if (ruleAt(i) != null) i,
  ];

  String? ruleAt(int index) {
    var line = lines[index].trim();
    if (line.startsWith(disabledRulePrefix)) {
      return line.substring(disabledRulePrefix.length);
    }
    if (line.isEmpty || line.startsWith('#')) return null;
    if (line.startsWith('- ')) line = line.substring(2).trim();
    return line;
  }

  bool enabledAt(int index) =>
      !lines[index].trim().startsWith(disabledRulePrefix);

  void setEnabled(int index, bool enabled) {
    final rule = ruleAt(index)!;
    lines[index] = enabled ? rule : '$disabledRulePrefix$rule';
  }

  void replace(int index, String rule) {
    lines[index] = enabledAt(index) ? rule : '$disabledRulePrefix$rule';
  }

  void add(String rule) {
    final match = indices
        .where((i) => ruleAt(i)!.startsWith('MATCH,'))
        .firstOrNull;
    if (match != null && !rule.startsWith('MATCH,')) {
      lines.insert(match, rule);
    } else {
      if (lines.length == 1 && lines.first.isEmpty) lines.clear();
      lines.add(rule);
    }
  }

  /// Reorders rule slots while leaving all unrelated source lines intact.
  void move(int oldIndex, int newIndex) {
    final slots = indices;
    final entries = slots.map((i) => lines[i]).toList();
    final entry = entries.removeAt(oldIndex);
    entries.insert(newIndex.clamp(0, entries.length), entry);
    // A catch-all is always last, including when temporarily disabled.
    final catchAll = entries.where((e) {
      final raw = e.trim().replaceFirst(disabledRulePrefix, '');
      return raw.startsWith('MATCH,') || raw.startsWith('- MATCH,');
    }).toList();
    entries.removeWhere(catchAll.contains);
    entries.addAll(catchAll);
    for (var i = 0; i < slots.length; i++) {
      lines[slots[i]] = entries[i];
    }
  }

  List<String> validate({Set<String>? targets}) =>
      validateRules(toString(), targets: targets);

  @override
  String toString() => lines.join('\n');
}

const ruleLabels = <String, String>{
  'DOMAIN': 'Точный домен',
  'DOMAIN-SUFFIX': 'Домен и поддомены',
  'DOMAIN-KEYWORD': 'Слово в домене',
  'DOMAIN-REGEX': 'Домен по выражению',
  'GEOSITE': 'Категория сайтов',
  'GEOIP': 'Страна IP-адреса',
  'IP-CIDR': 'Подсеть IPv4',
  'IP-CIDR6': 'Подсеть IPv6',
  'SRC-IP-CIDR': 'Исходная подсеть',
  'IP-ASN': 'Номер сети ASN',
  'SRC-IP-ASN': 'Исходная сеть ASN',
  'PROCESS-NAME': 'Название приложения',
  'PROCESS-NAME-REGEX': 'Приложения по выражению',
  'PROCESS-PATH': 'Путь приложения',
  'PROCESS-PATH-REGEX': 'Пути по выражению',
  'DST-PORT': 'Порт назначения',
  'SRC-PORT': 'Исходный порт',
  'NETWORK': 'Протокол сети',
  'MATCH': 'Остальной трафик',
};

String ruleTargetLabel(String target) => switch (target) {
  '@VPN' => 'Через VPN',
  'DIRECT' => 'Напрямую',
  'REJECT' => 'Заблокировать',
  'REJECT-DROP' => 'Сбросить соединение',
  'PASS' => 'Следующее правило',
  _ => target,
};
