import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../model/archive.dart';
import '../model/controller.dart';
import 'notice.dart';

class SubscriptionsPanel extends StatefulWidget {
  final DixController controller;
  final VoidCallback onImportLink, onImportFile, onExport;
  const SubscriptionsPanel({
    super.key,
    required this.controller,
    required this.onImportLink,
    required this.onImportFile,
    required this.onExport,
  });

  @override
  State<SubscriptionsPanel> createState() => _SubscriptionsPanelState();
}

class _SubscriptionsPanelState extends State<SubscriptionsPanel> {
  bool working = false;

  Future<void> run(Future<void> Function() action) async {
    setState(() => working = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showDixNotice(context, e);
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> rename(String id, String current) async {
    var edited = current;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название профиля'),
        content: SizedBox(
          width: 380,
          child: TextFormField(
            initialValue: current,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (value) => edited = value,
            onFieldSubmitted: (value) {
              if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (edited.trim().isNotEmpty) {
                Navigator.pop(context, edited.trim());
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      await run(() => widget.controller.renameProfile(id, result));
    }
  }

  Future<void> remove(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить профиль?'),
        content: Text(
          '«$name» и его серверы будут удалены из этой версии Dix. Перед удалением можно сохранить резервную копию через «Экспорт».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await run(() => widget.controller.removeProfile(id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final model = widget.controller;
      final profiles = model.archive.profiles;
      final locked = working || model.busy;
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ваши подключения',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Добавьте ссылку подписки, файл Clash/Mihomo или резервную копию Dix. Выбранный профиль определяет список серверов.',
                  style: TextStyle(color: muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: locked ? null : widget.onImportLink,
                      icon: const Icon(LucideIcons.link, size: 16),
                      label: const Text('Добавить ссылку'),
                    ),
                    OutlinedButton.icon(
                      onPressed: locked ? null : widget.onImportFile,
                      icon: const Icon(LucideIcons.fileInput, size: 16),
                      label: const Text('Импорт файла'),
                    ),
                    OutlinedButton.icon(
                      onPressed: locked ? null : widget.onExport,
                      icon: const Icon(LucideIcons.download, size: 16),
                      label: const Text('Экспорт'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (model.connected)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Можно добавлять и обновлять подписки во время подключения. Просмотр другой подписки не меняет текущий VPN; подключение переключится при выборе сервера.',
                style: TextStyle(color: muted),
              ),
            ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            title: const Text('Автообновление подписок'),
            subtitle: const Text(
              'По интервалу провайдера; приложение должно быть открыто. Текущее подключение сохраняется.',
            ),
            value: model.settings['autoUpdateSubs'] != false,
            onChanged: (v) => model.patch({'autoUpdateSubs': v}),
          ),
          const SizedBox(height: 16),
          if (profiles.isEmpty)
            _card(
              context,
              Column(
                children: [
                  Icon(LucideIcons.folderOpen, size: 32, color: muted),
                  const SizedBox(height: 12),
                  const Text(
                    'Пока нет профилей',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Вставьте ссылку от вашего VPN-провайдера или выберите файл конфигурации.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, height: 1.5),
                  ),
                ],
              ),
            ),
          for (final entry in profiles.entries) ...[
            Builder(
              builder: (context) {
                final name =
                    model.archive.subscriptions
                        .where((s) => s['id']?.toString() == entry.key)
                        .firstOrNull?['name']
                        ?.toString() ??
                    'Профиль ${entry.key}';
                var count = 0;
                String? error;
                try {
                  count = DixServer.fromProfile(
                    parseProfile(entry.value),
                  ).length;
                  if (count == 0) error = 'В профиле нет серверов';
                } catch (_) {
                  error = 'Не удалось прочитать профиль';
                }
                final active = model.browsedProfileId == entry.key;
                final running =
                    model.connected &&
                    (model.runningArchive ?? model.archive).activeId ==
                        entry.key;
                return _card(
                  context,
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          error != null
                              ? LucideIcons.triangleAlert
                              : LucideIcons.folder,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              error ??
                                  '$count серверов${running
                                      ? ' · подключён'
                                      : active
                                      ? ' · открыт'
                                      : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: error != null
                                    ? Theme.of(context).colorScheme.error
                                    : muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: active
                            ? 'Открытая подписка'
                            : 'Открыть серверы подписки',
                        onPressed: locked || error != null || active
                            ? null
                            : () => run(() => model.browseProfile(entry.key)),
                        icon: Icon(
                          active ? LucideIcons.circleCheck : LucideIcons.circle,
                          size: 21,
                        ),
                      ),
                      PopupMenuButton<String>(
                        enabled: !locked,
                        tooltip: 'Действия с профилем',
                        onSelected: (action) {
                          if (action == 'refresh') {
                            run(() => model.refreshProfile(entry.key));
                          }
                          if (action == 'rename') rename(entry.key, name);
                          if (action == 'remove') remove(entry.key, name);
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'refresh',
                            enabled: model.archive.subscriptions.any(
                              (s) =>
                                  s['id']?.toString() == entry.key &&
                                  s['url'] is String,
                            ),
                            child: const Text('Обновить подписку'),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Переименовать'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            enabled: !running,
                            child: const Text('Удалить'),
                          ),
                        ],
                        icon: const Icon(LucideIcons.ellipsis, size: 20),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          if (working)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      );
    },
  );

  Widget _card(BuildContext context, Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xff171717)
          : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );
}
