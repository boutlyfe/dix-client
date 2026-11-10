import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NoticeText {
  final String title, body, details;
  final bool warning;
  const NoticeText(this.title, this.body, this.details, {this.warning = false});
  factory NoticeText.from(Object error) {
    final raw = error.toString();
    final clean = raw
        .replaceAll(
          RegExp(
            r'(Bad state|FormatException|Unsupported operation|Exception):\s*',
          ),
          '',
        )
        .trim();
    final low = clean.toLowerCase();
    if (low.contains('администратора')) {
      return NoticeText(
        'Для TUN нужны права администратора',
        'Перезапустите Dix с правами администратора в настройках или выберите режим «Прокси».',
        raw,
        warning: true,
      );
    }
    if (low.contains('not found group') ||
        low.contains('группа') && low.contains('не найд')) {
      return NoticeText(
        'Не удалось переключить сервер',
        'Не удалось найти маршрут этого сервера в активном профиле. Повторите выбор или обновите подписку.',
        raw,
        warning: true,
      );
    }
    if (low.contains('timeout') || low.contains('таймаут')) {
      return NoticeText(
        'Сервер не ответил вовремя',
        'Проверьте соединение и повторите действие. Можно попробовать другой сервер.',
        raw,
        warning: true,
      );
    }
    if (low.contains('порт') && low.contains('занят') ||
        low.contains('прежнем dix')) {
      return NoticeText(
        'Другое подключение уже работает',
        clean,
        raw,
        warning: true,
      );
    }
    if (low.startsWith('доступна новая версия')) {
      return NoticeText('Доступно обновление Dix', clean, raw);
    }
    final success =
        low.contains('импортирован') ||
        low.contains('скопирован') ||
        low.contains('очищен') ||
        low.contains('сохранен') ||
        low.contains('обновлена');
    return NoticeText(
      success ? 'Готово' : 'Не удалось выполнить действие',
      clean,
      raw,
      warning: !success,
    );
  }
}

void showDixNotice(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.all(18),
      duration: const Duration(seconds: 7),
      content: DixNoticeCard(
        error: error,
        onClose: messenger.hideCurrentSnackBar,
      ),
    ),
  );
}

class DixNoticeCard extends StatelessWidget {
  final Object error;
  final VoidCallback onClose;
  const DixNoticeCard({super.key, required this.error, required this.onClose});
  @override
  Widget build(BuildContext context) {
    final notice = NoticeText.from(error),
        scheme = Theme.of(context).colorScheme;
    final accent = notice.warning
        ? const Color(0xffcda66e)
        : const Color(0xff79b698);
    return Semantics(
      liveRegion: true,
      child: Material(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff1a1917)
            : const Color(0xfffffcf7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accent.withValues(alpha: .32)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  notice.warning ? LucideIcons.info : LucideIcons.check,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notice.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    if (notice.details != notice.body)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                        ),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (dialog) => AlertDialog(
                            title: const Text('Подробности'),
                            content: SingleChildScrollView(
                              child: SelectableText(
                                notice.details,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialog),
                                child: const Text('Закрыть'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text(
                          'Подробнее',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Закрыть уведомление',
                onPressed: onClose,
                icon: const Icon(LucideIcons.x, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
