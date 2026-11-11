import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../model/controller.dart';
import '../model/app_updates.dart';
import '../platform/platform.dart' as platform;
import 'notice.dart';

class UpdatesPanel extends StatelessWidget {
  const UpdatesPanel({super.key, required this.controller});
  final DixController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget card(Widget child) => Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(
          Row(
            children: [
              SvgPicture.asset(
                'assets/dix-icon-rounded.svg',
                width: 48,
                height: 48,
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dix $dixVersion',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Установленная версия · Windows',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Обновления через GitHub',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                key: const Key('auto-update-check'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Проверять при запуске'),
                subtitle: const Text(
                  'Уведомлять о новой Windows-версии из репозитория релизов',
                ),
                value: controller.settings['flutterCheckUpdates'] != false,
                onChanged: (value) =>
                    controller.patch({'flutterCheckUpdates': value}),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Источник GitHub'),
                subtitle: Text(
                  controller.updateRepository.isEmpty
                      ? 'Пока не подключён'
                      : controller.updateRepository,
                ),
                trailing: const Icon(LucideIcons.chevronRight, size: 17),
                onTap: () => _repository(context),
              ),
              const SizedBox(height: 8),
              Text(
                controller.updateStatus ??
                    'Установка обновлений пока выполняется вручную.',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.checkingUpdates
                        ? null
                        : controller.checkForUpdates,
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: Text(
                      controller.checkingUpdates
                          ? 'Проверяем…'
                          : 'Проверить обновления',
                    ),
                  ),
                  if (controller.availableRelease != null)
                    FilledButton(
                      onPressed: () async {
                        try {
                          await platform.openReleaseUrl(
                            controller.availableRelease!.pageUrl,
                          );
                        } catch (error) {
                          if (context.mounted) {
                            showDixNotice(context, error);
                          }
                        }
                      },
                      child: const Text('Открыть релиз'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Что нового',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        for (final release in const [
          (
            '0.2.4',
            'Исправление подключения',
            'Ручной выбор следует фактическому основному маршруту. Проверка реального состояния TUN и пинг через активное ядро при подключении.',
          ),
          (
            '0.2.3',
            'Настройки приложения работают',
            'Трей и скрытый запуск, автоподключение, журнал событий, переопределение провайдера и закрытие соединений при смене сервера. Проверка обновлений из выбранного репозитория GitHub.',
          ),
          (
            '0.2.2',
            'Пинг и порядок в настройках',
            'Повтор проверки через второй адрес, увеличенный тайм-аут и понятный статус недоступности. Категории настроек, страница обновлений и имя ядра DixCore.exe.',
          ),
          (
            '0.2.1',
            'Удобнее каждый день',
            'Переключение серверов и работа с подписками при подключении, массовый пинг, сортировка по задержке, собственный заголовок окна и скругления.',
          ),
          (
            '0.2.0',
            'Dix на Flutter для Windows',
            'Подключение через ядро, импорт подписок и правил, темы Classic и Minimal, планета и редактирование блоков главного экрана.',
          ),
        ]) ...[
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dix ${release.$1} · ${release.$2}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  release.$3,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _repository(BuildContext context) async {
    final field = TextEditingController(text: controller.updateRepository);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Репозиторий релизов'),
          content: SizedBox(
            width: 440,
            child: TextField(
              controller: field,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Владелец/репозиторий',
                hintText: 'owner/dix',
                errorText: error,
                helperText: 'Публичные релизы с архивом Dix-Windows-версия.zip',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final value = field.text.trim();
                if (value.isNotEmpty && !validReleaseRepository(value)) {
                  update(() => error = 'Введите владелец/имя без URL');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    field.dispose();
    if (result != null) controller.patch({'flutterUpdateRepository': result});
  }
}
