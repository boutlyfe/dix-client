import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../model/archive.dart';
import '../model/controller.dart';
import 'dix_flag.dart';
import 'notice.dart';

/// Shared by the desktop dock, full page and mobile server sheet.
class DixServersPanel extends StatefulWidget {
  final DixController controller;
  final bool docked;
  final VoidCallback onAddSubscription;
  final VoidCallback? onSelected;
  const DixServersPanel({
    super.key,
    required this.controller,
    required this.onAddSubscription,
    this.onSelected,
    this.docked = false,
  });

  @override
  State<DixServersPanel> createState() => _DixServersPanelState();
}

class _DixServersPanelState extends State<DixServersPanel> {
  final _search = TextEditingController();
  bool _favoritesOnly = false;
  String _sort = 'original', _group = 'country';
  final Set<String> _collapsed = {};
  DixController get model => widget.controller;
  String? get _activeProfileId => model.connected
      ? model.runningArchive?.activeId ?? model.archive.activeId
      : model.archive.activeId;
  Color get muted => Theme.of(context).colorScheme.onSurfaceVariant;

  @override
  void initState() {
    super.initState();
    _sort = model.settings['serverSort']?.toString() ?? 'original';
    _group = model.settings['serverGroup']?.toString() ?? 'country';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final favorites = (model.settings['favorites'] as List? ?? [])
          .map((e) => e.toString())
          .toSet();
      final query = _search.text.trim().toLowerCase();
      final servers = model.browsingServers
          .where(
            (s) =>
                '${s.name} ${s.type} ${_countryName(s.countryCode)}'
                    .toLowerCase()
                    .contains(query) &&
                (!_favoritesOnly || favorites.contains(s.name)),
          )
          .toList();
      if (_sort != 'original') {
        servers.sort((a, b) {
          if (_sort == 'ping') {
            final aDelay = model.delays[a.name];
            final bDelay = model.delays[b.name];
            final priority = (aDelay ?? 0x7fffffff).compareTo(
              bDelay ?? 0x7fffffff,
            );
            if (priority != 0) return priority;
          }
          if (_sort == 'favorites') {
            final priority =
                (favorites.contains(b.name) ? 1 : 0) -
                (favorites.contains(a.name) ? 1 : 0);
            if (priority != 0) return priority;
          }
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        });
      }
      final groups = <String, List<DixServer>>{};
      for (final server in servers) {
        final key = switch (_group) {
          'country' => _countryName(server.countryCode),
          'protocol' => server.type.toUpperCase(),
          _ => 'Все серверы',
        };
        (groups[key] ??= []).add(server);
      }
      final rows = <Object>[
        for (final entry in groups.entries) ...[
          if (_group != 'none') entry,
          if (!_collapsed.contains(entry.key)) ...entry.value,
        ],
      ];
      final padding = widget.docked ? 14.0 : 22.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Серверы',
                      style: TextStyle(
                        fontSize: widget.docked ? 18 : 25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Добавить подписку',
                      onPressed: widget.onAddSubscription,
                      icon: const Icon(LucideIcons.plus, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _profiles(),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('server-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Название, страна, протокол',
                    hintStyle: const TextStyle(fontSize: 11),
                    prefixIcon: const Icon(LucideIcons.search, size: 16),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Очистить поиск',
                            icon: const Icon(LucideIcons.x, size: 15),
                            onPressed: () => setState(_search.clear),
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    FilterChip(
                      avatar: Icon(
                        LucideIcons.star,
                        size: 13,
                        color: _favoritesOnly
                            ? Theme.of(context).colorScheme.onSurface
                            : muted,
                      ),
                      label: Text(
                        'Избранные${favorites.isEmpty ? '' : ' ${favorites.length}'}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      selected: _favoritesOnly,
                      onSelected: (value) =>
                          setState(() => _favoritesOnly = value),
                      visualDensity: VisualDensity.compact,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const Key('test-all-delays'),
                      tooltip: model.pinging
                          ? 'Остановить проверку пинга'
                          : 'Проверить пинг показанных серверов',
                      onPressed: model.pinging
                          ? () => model.cancelPings()
                          : servers.isEmpty
                          ? null
                          : () => model.testDelays(servers),
                      icon: Icon(
                        model.pinging ? LucideIcons.square : LucideIcons.zap,
                        size: 17,
                      ),
                    ),
                    PopupMenuButton<String>(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      tooltip: 'Сортировка и группировка',
                      icon: const Icon(LucideIcons.slidersHorizontal, size: 17),
                      onSelected: (value) => setState(() {
                        if (value.startsWith('sort:')) {
                          _sort = value.substring(5);
                          model.patch({'serverSort': _sort});
                        } else {
                          _group = value.substring(6);
                          model.patch({'serverGroup': _group});
                          _collapsed.clear();
                        }
                      }),
                      itemBuilder: (_) => [
                        for (final e in {
                          'original': 'Порядок подписки',
                          'name': 'По названию',
                          'ping': 'По пингу',
                          'favorites': 'Избранные сначала',
                        }.entries)
                          CheckedPopupMenuItem(
                            value: 'sort:${e.key}',
                            checked: _sort == e.key,
                            child: Text(e.value),
                          ),
                        const PopupMenuDivider(),
                        for (final e in {
                          'country': 'По странам',
                          'protocol': 'По протоколам',
                          'none': 'Без группировки',
                        }.entries)
                          CheckedPopupMenuItem(
                            value: 'group:${e.key}',
                            checked: _group == e.key,
                            child: Text(e.value),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${servers.length} из ${model.browsingServers.length} серверов',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
                if (model.connected)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      model.browsedProfileId == _activeProfileId
                          ? 'Нажмите на сервер, чтобы переключиться'
                          : 'Просмотр подписки · VPN остаётся подключён',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: servers.isEmpty
                ? _empty(query)
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, 20),
                    itemCount: rows.length,
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      if (row is MapEntry<String, List<DixServer>>) {
                        return _groupHeader(row);
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _tile(row as DixServer, favorites),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );

  Widget _groupHeader(MapEntry<String, List<DixServer>> entry) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: () => setState(() {
      if (!_collapsed.add(entry.key)) {
        _collapsed.remove(entry.key);
      }
    }),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.key.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
          Text(
            '${entry.value.length}',
            style: TextStyle(fontSize: 10, color: muted),
          ),
          const SizedBox(width: 7),
          Icon(
            _collapsed.contains(entry.key)
                ? LucideIcons.chevronRight
                : LucideIcons.chevronDown,
            size: 13,
            color: muted,
          ),
        ],
      ),
    ),
  );

  Widget _profiles() {
    final profiles = model.archive.profiles;
    if (profiles.isEmpty) {
      return Text(
        'Выберите направление подключения',
        style: TextStyle(fontSize: 11, color: muted),
      );
    }
    final names = {
      for (final sub in model.archive.subscriptions)
        sub['id']?.toString(): (sub['name'] ?? sub['id']).toString(),
    };
    return DropdownButtonFormField<String>(
      borderRadius: BorderRadius.circular(16),
      key: ValueKey(model.browsedProfileId),
      initialValue: profiles.containsKey(model.browsedProfileId)
          ? model.browsedProfileId
          : null,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelText: 'Подписка',
      ),
      items: [
        for (final id in profiles.keys)
          DropdownMenuItem(
            value: id,
            child: Text(
              names[id] ?? (id == 'preview' ? 'Предпросмотр' : id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
      onChanged: (id) async {
        if (id == null || id == model.browsedProfileId) return;
        try {
          await model.browseProfile(id);
          if (!mounted) return;
          setState(() {
            _search.clear();
            _collapsed.clear();
          });
        } catch (error) {
          if (!mounted) return;
          showDixNotice(context, error);
        }
      },
    );
  }

  Widget _tile(DixServer server, Set<String> favorites) {
    final selected =
        model.browsedProfileId == _activeProfileId &&
        model.selected?.name == server.name;
    final colors = Theme.of(context).colorScheme;
    final favorite = favorites.contains(server.name);
    return Material(
      clipBehavior: Clip.antiAlias,
      color: selected
          ? colors.onSurface.withValues(alpha: .09)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: selected ? colors.onSurface : colors.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: model.busy
            ? null
            : () async {
                await model.select(server, profileId: model.browsedProfileId);
                if (mounted && model.message == null) widget.onSelected?.call();
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 3, 12),
          child: Row(
            children: [
              if (server.countryCode != null)
                DixFlag(countryCode: server.countryCode!)
              else
                Icon(LucideIcons.server, size: 21, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: server.displayName,
                      child: Text(
                        server.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${server.type.toUpperCase()}${selected ? ' · Выбран' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 67,
                child: Tooltip(
                  message:
                      model.delays.containsKey(server.name) &&
                          model.delays[server.name] == null
                      ? 'Нет ответа от двух адресов проверки. Нажмите для повтора. Тайм-аут меняется в настройках подключения.'
                      : 'Проверить задержку HTTPS через сервер',
                  child: TextButton(
                    onPressed: !model.testingDelays.contains(server.name)
                        ? () => model.testDelay(server)
                        : null,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 32),
                    ),
                    child: Text(
                      model.testingDelays.contains(server.name)
                          ? '…'
                          : model.delays.containsKey(server.name)
                          ? model.delays[server.name] == null
                                ? 'Нет ответа'
                                : '${model.delays[server.name]} ms'
                          : 'Пинг',
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: favorite ? 'Убрать из избранного' : 'В избранное',
                onPressed: () {
                  final updated = {...favorites};
                  if (!updated.add(server.name)) updated.remove(server.name);
                  model.patch({'favorites': updated.toList()});
                },
                icon: Icon(
                  LucideIcons.star,
                  size: 17,
                  color: favorite ? const Color(0xfff0c66a) : muted,
                ),
                isSelected: favorite,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(String query) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            model.browsingServers.isEmpty
                ? LucideIcons.server
                : LucideIcons.search,
            size: 28,
            color: muted,
          ),
          const SizedBox(height: 14),
          Text(
            model.browsingServers.isEmpty
                ? 'Здесь появятся ваши серверы'
                : _favoritesOnly && query.isEmpty
                ? 'Избранных серверов пока нет'
                : 'Ничего не найдено',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            model.browsingServers.isEmpty
                ? 'Добавьте подписку по ссылке или из файла.'
                : _favoritesOnly
                ? 'Отметьте серверы звёздочкой или измените фильтр.'
                : 'Попробуйте другую страну или название.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: model.browsingServers.isEmpty
                ? widget.onAddSubscription
                : () => setState(() {
                    _search.clear();
                    _favoritesOnly = false;
                  }),
            child: Text(
              model.browsingServers.isEmpty
                  ? 'Добавить подписку'
                  : 'Сбросить фильтры',
            ),
          ),
        ],
      ),
    ),
  );
}

String _countryName(String? code) =>
    const {
      'FI': 'Финляндия',
      'PL': 'Польша',
      'DE': 'Германия',
      'NL': 'Нидерланды',
      'RU': 'Россия',
      'US': 'США',
      'JP': 'Япония',
      'SE': 'Швеция',
      'FR': 'Франция',
      'GB': 'Великобритания',
      'CA': 'Канада',
      'TR': 'Турция',
      'KZ': 'Казахстан',
      'AM': 'Армения',
      'GE': 'Грузия',
      'CH': 'Швейцария',
      'AT': 'Австрия',
      'IT': 'Италия',
      'ES': 'Испания',
      'CZ': 'Чехия',
      'EE': 'Эстония',
      'LV': 'Латвия',
      'LT': 'Литва',
      'NO': 'Норвегия',
      'DK': 'Дания',
      'SG': 'Сингапур',
      'HK': 'Гонконг',
      'KR': 'Южная Корея',
      'AU': 'Австралия',
      'AE': 'ОАЭ',
      'UA': 'Украина',
      'BY': 'Беларусь',
      'IQ': 'Ирак',
      'IL': 'Израиль',
    }[code] ??
    (code ?? 'Другие серверы');
