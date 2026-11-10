import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../model/archive.dart';
import '../model/controller.dart';
import '../model/rule_document.dart';
import '../model/rules.dart';

/// Embedded in the shell's scrolling page, with dialogs that also fit a phone.
class RulesPanel extends StatefulWidget {
  final DixController controller;
  const RulesPanel({super.key, required this.controller});
  @override
  State<RulesPanel> createState() => _RulesPanelState();
}

class _RulesPanelState extends State<RulesPanel> {
  DixController get model => widget.controller;
  Map<String, dynamic> get advanced => jsonMap(model.settings['advancedRules']);
  RuleDocument get document => RuleDocument(advanced['text']?.toString() ?? '');
  Set<String> get targets {
    final profile = model.archive.activeProfile;
    return {
      '@VPN',
      'DIRECT',
      'REJECT',
      'REJECT-DROP',
      'PASS',
      ...(profile['proxy-groups'] as List? ?? []).whereType<Map>().map(
        (g) => g['name'].toString(),
      ),
      ...model.servers.map((s) => s.name),
      ...(advanced['groups'] as List? ?? []).whereType<Map>().map(
        (g) => g['name'].toString(),
      ),
    };
  }

  void patch(Map<String, dynamic> changes) => model.patch({
    'advancedRules': {...advanced, ...changes},
  });

  bool save(RuleDocument source) {
    // Unknown imported targets remain visible and editable. Checking the whole
    // document here must not prevent removing a different broken imported row.
    final errors = source.validate();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errors.first)));
      return false;
    }
    patch({'text': source.toString()});
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final source = document, indices = source.indices;
      final fallback = (advanced['fallback'] ?? '@VPN').toString();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Куда направлять трафик',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'rule',
                      label: Text('По правилам'),
                      icon: Icon(LucideIcons.route, size: 15),
                    ),
                    ButtonSegment(
                      value: 'global',
                      label: Text('Весь трафик'),
                      icon: Icon(LucideIcons.globe, size: 15),
                    ),
                  ],
                  selected: {
                    model.settings['routeMode'] == 'global' ? 'global' : 'rule',
                  },
                  onSelectionChanged: (v) =>
                      model.patch({'routeMode': v.first}),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Свои правила',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Выше в списке — выше приоритет',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: advanced['enabled'] == true,
                  onChanged: (v) => patch({'enabled': v}),
                ),
                if (model.settings['routeMode'] == 'global')
                  const Text(
                    'Список сохранён. Чтобы применять его, выберите «По правилам».',
                    style: TextStyle(fontSize: 12),
                  ),
                if (model.connected)
                  const Text(
                    'Изменения применятся после переподключения.',
                    style: TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('add-rule'),
                onPressed: () => editRule(),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Добавить правило'),
              ),
              OutlinedButton.icon(
                onPressed: editText,
                icon: const Icon(LucideIcons.code, size: 16),
                label: const Text('Текст / импорт'),
              ),
              OutlinedButton.icon(
                onPressed: editGroups,
                icon: const Icon(LucideIcons.layers, size: 16),
                label: const Text('Свои группы'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (indices.isEmpty)
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Первое правило — за пару шагов',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Выберите сайт или приложение и укажите: через VPN, напрямую или заблокировать.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Сайт напрямую'),
                        onPressed: () =>
                            editRule(initial: 'DOMAIN-SUFFIX,,DIRECT'),
                      ),
                      ActionChip(
                        label: const Text('Discord через VPN'),
                        onPressed: () =>
                            editRule(initial: 'GEOSITE,discord,@VPN'),
                      ),
                      ActionChip(
                        label: const Text('Приложение напрямую'),
                        onPressed: () =>
                            editRule(initial: 'PROCESS-NAME,,DIRECT'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: indices.length,
            onReorderItem: (oldIndex, newIndex) {
              source.move(oldIndex, newIndex);
              save(source);
            },
            itemBuilder: (context, index) {
              final line = indices[index],
                  raw = source.ruleAt(line)!,
                  fields = ruleFields(raw);
              final isMatch = fields.first == 'MATCH',
                  enabled = source.enabledAt(line);
              final target = fields.length > (isMatch ? 1 : 2)
                  ? fields[isMatch ? 1 : 2]
                  : '';
              return Padding(
                key: ValueKey('rule-$line-$raw'),
                padding: const EdgeInsets.only(bottom: 8),
                child: _Card(
                  padding: const EdgeInsets.fromLTRB(6, 10, 4, 10),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Tooltip(
                            message: 'Перетащить',
                            child: Icon(LucideIcons.gripVertical, size: 17),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => editRule(index: line),
                          borderRadius: BorderRadius.circular(8),
                          child: Opacity(
                            opacity: enabled ? 1 : .45,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isMatch
                                        ? 'Остальной трафик'
                                        : fields.length > 1
                                        ? fields[1]
                                        : raw,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${ruleLabels[fields.first] ?? fields.first}  →  ${ruleTargetLabel(target)}${enabled ? '' : ' · выключено'}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Действия с правилом',
                        icon: const Icon(LucideIcons.ellipsis, size: 18),
                        onSelected: (action) {
                          if (action == 'edit') {
                            editRule(index: line);
                            return;
                          }
                          if (action == 'toggle') {
                            source.setEnabled(line, !enabled);
                          }
                          if (action == 'delete') source.lines.removeAt(line);
                          if (action == 'up') source.move(index, index - 1);
                          if (action == 'down') source.move(index, index + 1);
                          save(source);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Изменить'),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(enabled ? 'Выключить' : 'Включить'),
                          ),
                          if (index > 0 && !isMatch)
                            const PopupMenuItem(
                              value: 'up',
                              child: Text('Поднять выше'),
                            ),
                          if (index < indices.length - 1 && !isMatch)
                            const PopupMenuItem(
                              value: 'down',
                              child: Text('Опустить ниже'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Удалить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Если правило не подошло',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (indices.any(
                  (i) =>
                      source.enabledAt(i) &&
                      source.ruleAt(i)!.startsWith('MATCH,'),
                ))
                  const Text(
                    'Используется последнее правило «Остальной трафик». Измените его в списке.',
                    style: TextStyle(fontSize: 12),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: fallback,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Остальной трафик',
                    ),
                    items: targetItems({...targets, fallback}),
                    onChanged: (v) => patch({'fallback': v}),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  List<DropdownMenuItem<String>> targetItems(Set<String> values) => [
    for (final value in values)
      DropdownMenuItem(
        value: value,
        child: Text(
          ruleTargetLabel(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
  ];

  Future<void> editRule({int? index, String? initial}) async {
    final source = document;
    final fields = ruleFields(
      initial ??
          (index == null ? 'DOMAIN-SUFFIX,,DIRECT' : source.ruleAt(index)!),
    );
    var type = ruleTypes.contains(fields.first)
        ? fields.first
        : 'DOMAIN-SUFFIX';
    final content = TextEditingController(
      text: type == 'MATCH' ? '' : fields.elementAtOrNull(1) ?? '',
    );
    var target = fields.elementAtOrNull(type == 'MATCH' ? 1 : 2) ?? 'DIRECT';
    var noResolve = fields.last == 'no-resolve';
    String? error;
    final choices = {...targets, target};
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) {
          final hint = switch (type) {
            'DOMAIN' || 'DOMAIN-SUFFIX' => 'example.com',
            'DOMAIN-KEYWORD' => 'avito',
            'GEOSITE' => 'discord или category-ru',
            'GEOIP' => 'RU',
            'PROCESS-NAME' => 'FortniteClient-Win64-Shipping.exe',
            'PROCESS-NAME-REGEX' => '(?i)(steam|cs2|fortnite)',
            'IP-CIDR' || 'SRC-IP-CIDR' => '192.168.0.0/16',
            'IP-CIDR6' => '2001:db8::/32',
            'NETWORK' => 'tcp или udp',
            'DST-PORT' || 'SRC-PORT' => '443 или 8000-9000',
            _ => 'Значение правила',
          };
          return AlertDialog(
            title: Text(
              index == null ? 'Добавить правило' : 'Изменить правило',
            ),
            content: SizedBox(
              width: 490,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Что проверять',
                      ),
                      items: [
                        for (final t in ruleTypes)
                          DropdownMenuItem(
                            value: t,
                            child: Text(
                              ruleLabels[t] ?? t,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => update(() {
                        type = v!;
                        error = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (type != 'MATCH') ...[
                      TextField(
                        key: const Key('rule-value'),
                        controller: content,
                        autofocus: index == null,
                        maxLines: type.contains('REGEX') ? 3 : 1,
                        decoration: InputDecoration(
                          labelText: 'Содержание',
                          hintText: hint,
                          helperText: type == 'DOMAIN-SUFFIX'
                              ? 'Включая все поддомены. Без https:// и пути.'
                              : hint,
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: target,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Куда направить',
                      ),
                      items: targetItems(choices),
                      onChanged: (v) => update(() => target = v!),
                    ),
                    if ([
                          'GEOIP',
                          'IP-CIDR',
                          'IP-CIDR6',
                          'IP-ASN',
                          'SRC-IP-CIDR',
                          'SRC-IP-ASN',
                        ].contains(type) ||
                        noResolve)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Без DNS-поиска',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: noResolve,
                        onChanged: (v) => update(() => noResolve = v!),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Отмена'),
              ),
              FilledButton(
                key: const Key('save-rule'),
                onPressed: () {
                  final rule = [
                    type,
                    if (type != 'MATCH') content.text.trim(),
                    target,
                    if (noResolve && type != 'MATCH') 'no-resolve',
                  ].join(',');
                  final errors = validateRules(rule, targets: choices);
                  if (errors.isNotEmpty) {
                    update(() => error = errors.first);
                    return;
                  }
                  final candidate = RuleDocument(source.toString());
                  if (index == null) {
                    candidate.add(rule);
                  } else {
                    candidate.replace(index, rule);
                  }
                  final issues = candidate.validate();
                  if (issues.isNotEmpty) {
                    update(() => error = issues.first);
                    return;
                  }
                  Navigator.pop(dialog, candidate.toString());
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
    // Routes finish their closing animation before disposing the field.
    if (result != null && mounted) patch({'text': result});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    content.dispose();
  }

  Future<void> editText() async {
    final input = TextEditingController(text: document.toString());
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Текст правил'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Вставьте список из Clash: по одному правилу на строку. Префиксы «- » и комментарии поддерживаются.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('rules-text'),
                    controller: input,
                    minLines: 5,
                    maxLines: 12,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      hintText:
                          'DOMAIN,example.com,DIRECT\nGEOSITE,discord,@VPN',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final errors = validateRules(input.text);
                if (errors.isNotEmpty) {
                  update(() => error = errors.take(4).join('\n'));
                  return;
                }
                Navigator.pop(dialog, input.text);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) patch({'text': result});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
  }

  Future<void> editGroups() async {
    final groups = (advanced['groups'] as List? ?? [])
        .whereType<Map>()
        .map((g) => Map<String, dynamic>.from(g))
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Свои группы'),
          content: SizedBox(
            width: 490,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Группа даёт понятное имя маршруту. Например, «Российские сайты» → напрямую.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  for (final (i, group) in groups.indexed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(group['name'].toString()),
                      subtitle: Text(
                        ruleTargetLabel(group['target'].toString()),
                      ),
                      trailing: IconButton(
                        tooltip: 'Удалить группу',
                        icon: const Icon(LucideIcons.trash2, size: 17),
                        onPressed: () {
                          final name = group['name'].toString();
                          final source = document;
                          final used =
                              source.indices.any((line) {
                                final f = ruleFields(source.ruleAt(line)!);
                                return f.elementAtOrNull(
                                      f.first == 'MATCH' ? 1 : 2,
                                    ) ==
                                    name;
                              }) ||
                              advanced['fallback'] == name ||
                              groups.any((g) => g['target'] == name);
                          if (used) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Группа используется правилом или маршрутом. Сначала измените его цель.',
                                ),
                              ),
                            );
                            return;
                          }
                          update(() => groups.removeAt(i));
                          patch({'groups': groups});
                        },
                      ),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Добавить группу'),
                    onPressed: () async {
                      final added = await addGroup({
                        ...targets,
                        ...groups.map((g) => g['name'].toString()),
                      });
                      if (added != null && context.mounted) {
                        update(() => groups.add(added));
                        patch({'groups': groups});
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Готово'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> addGroup(Set<String> existing) async {
    final name = TextEditingController();
    var target = 'DIRECT';
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Новая группа'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      hintText: 'Российские сайты',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: target,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Маршрут'),
                    items: targetItems(existing),
                    onChanged: (v) => target = v!,
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final value = name.text.trim();
                if (value.isEmpty ||
                    existing.contains(value) ||
                    value.contains(RegExp(r'[,\r\n]'))) {
                  update(() => error = 'Введите уникальное имя без запятых');
                  return;
                }
                Navigator.pop(dialog, {'name': value, 'target': target});
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    return result;
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff171717)
        : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}
