import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../model/controller.dart';
import '../platform/platform.dart' as platform;
import 'notice.dart';

class AppSettingsControls extends StatelessWidget {
  const AppSettingsControls({super.key, required this.controller});
  final DixController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    Widget option(
      String key,
      String title,
      String subtitle, {
      bool defaultOn = false,
      bool enabled = true,
    }) => SwitchListTile.adaptive(
      key: ValueKey(key),
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: settings[key] is bool ? settings[key] == true : defaultOn,
      onChanged: enabled ? (value) => controller.patch({key: value}) : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        option(
          'flutterMinimizeToTray',
          'Сворачивать при закрытии',
          'Крестик скрывает окно в трей. Выход — через меню значка Dix.',
          defaultOn: true,
        ),
        option(
          'flutterStartHidden',
          'Скрытый запуск',
          'Запускать в трее, без открытия главного окна',
        ),
        option(
          'flutterAutoConnect',
          'Подключаться при запуске',
          'Автоматически включать последний сервер. Для TUN нужны права администратора.',
        ),
        const Divider(height: 24),
        option(
          'flutterCloseConnections',
          'Закрывать соединения при смене сервера',
          'Приложения создадут новые соединения через выбранный сервер',
        ),
        option(
          'flutterLogging',
          'Журнал событий',
          'Сохранять события запуска, подключения и ошибки на этом компьютере',
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.receipt_long_outlined, size: 20),
          title: const Text('Открыть журнал'),
          subtitle: const Text('Просмотреть, скопировать или сохранить в файл'),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _showJournal(context),
        ),
        const Divider(height: 24),
        option(
          'flutterAnimateTabs',
          'Анимация вкладок',
          'Доступна только в мобильном режиме; на Windows вкладки переключаются сразу.',
          defaultOn: true,
          enabled: !platform.isWindows,
        ),
      ],
    );
  }

  Future<void> _showJournal(BuildContext context) async {
    final logs = platform.nativeLogs.join('\n');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Журнал Dix'),
        content: SizedBox(
          width: 640,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(
              logs.isEmpty
                  ? 'Записей пока нет. Включите журнал событий, чтобы сохранять новые события.'
                  : logs,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: logs.isEmpty
                ? null
                : () async {
                    try {
                      await platform.clearNativeLogs();
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    } catch (error) {
                      if (dialogContext.mounted) {
                        showDixNotice(dialogContext, error);
                      }
                    }
                  },
            child: const Text('Очистить'),
          ),
          TextButton(
            onPressed: logs.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: logs));
                    if (dialogContext.mounted) {
                      showDixNotice(dialogContext, 'Журнал скопирован');
                    }
                  },
            child: const Text('Копировать'),
          ),
          TextButton(
            onPressed: logs.isEmpty
                ? null
                : () async {
                    try {
                      await platform.saveText('dix-journal.txt', logs);
                    } catch (error) {
                      if (dialogContext.mounted) {
                        showDixNotice(dialogContext, error);
                      }
                    }
                  },
            child: const Text('Сохранить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}
