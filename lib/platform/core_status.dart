import 'dart:convert';
import 'core_selection.dart';

Future<void> requireStartedTun(SelectionRpc call) async {
  dynamic value = await call('getTunStatus', null);
  if (value is String) value = jsonDecode(value);
  if (value is! Map || value['enabled'] != true) {
    final reason = value is Map ? value['error']?.toString().trim() ?? '' : '';
    throw StateError(
      reason.isEmpty
          ? 'TUN-адаптер не запущен. Проверьте права администратора и драйвер Wintun.'
          : 'Не удалось запустить TUN: $reason',
    );
  }
}
