import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../model/controller.dart';
import 'app_settings.dart';
import 'notice.dart';
import '../model/profile_network.dart';
import '../platform/platform.dart' as platform;

/// Uses the original Dix settings keys so imported preferences round-trip.
/// Controls use the same effective settings as the Windows runtime.
class ConnectionSettingsPanel extends StatelessWidget {
  const ConnectionSettingsPanel({
    super.key,
    required this.controller,
    this.category,
  });

  final DixController controller;
  final String? category;

  static const dnsProviders = {
    'auto': 'Автоматически',
    'cloudflare': 'Cloudflare · 1.1.1.1',
    'google': 'Google · 8.8.8.8',
    'adguard': 'AdGuard',
    'quad9': 'Quad9',
    'custom': 'Свои серверы',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final settings = controller.settings;
      final locked = controller.connected || controller.busy;
      final manual = settings['flutterOverrideProvider'] != false;
      final networkLocked = locked || !manual;
      final dnsMode = settings['dnsMode']?.toString() ?? 'auto';
      final netMode = settings['netMode']?.toString() ?? 'tun';
      final region = settings['aiDnsRegion']?.toString() ?? 'RU';
      final colors = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (category == null || category == 'network')
            _Section(
              icon: LucideIcons.network,
              title: 'Подключение и DNS',
              subtitle:
                  'Предпочтения сохраняются вместе с настройками Dix. '
                  'Применяются при следующем подключении на Windows.',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Переопределять настройки подписки'),
                  subtitle: const Text(
                    'Выключите, чтобы использовать DNS, режим и правила провайдера. Настройки Dix сохранятся.',
                  ),
                  value: manual,
                  onChanged: locked
                      ? null
                      : (value) => controller.patch({
                          'flutterOverrideProvider': value,
                        }),
                ),
                const Divider(height: 28),
                _Choice(
                  label: 'Тайм-аут пинга',
                  value: '${settings['pingTimeoutSeconds'] ?? 10}',
                  values: const {
                    '5': '5 секунд',
                    '10': '10 секунд',
                    '15': '15 секунд',
                    '20': '20 секунд',
                  },
                  enabled: !controller.pinging,
                  onChanged: (value) => controller.patch({
                    'pingTimeoutSeconds': int.parse(value),
                  }),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Пинг проверяет HTTPS через сервер. Если первый адрес не отвечает, используется второй.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 18),
                if (locked)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Для изменения настроек отключите VPN.'),
                  ),
                _Choice(
                  label: 'Способ подключения',
                  value: netMode,
                  values: const {
                    'tun': 'TUN · весь трафик устройства',
                    'proxy': 'Системный прокси',
                  },
                  enabled: !locked,
                  onChanged: (value) => controller.patch({'netMode': value}),
                ),
                const SizedBox(height: 16),
                _Choice(
                  label: 'DNS-резолвер',
                  value: dnsMode,
                  values: dnsProviders,
                  enabled: !networkLocked,
                  onChanged: (value) => controller.patch({'dnsMode': value}),
                ),
                if (dnsMode == 'custom') ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Свои DNS-серверы'),
                    subtitle: Text(
                      settings['dnsCustom'] is List &&
                              (settings['dnsCustom'] as List).isNotEmpty
                          ? (settings['dnsCustom'] as List).join('\n')
                          : 'Добавьте IP-адрес или HTTPS-адрес DoH',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(LucideIcons.pencil, size: 18),
                    onTap: networkLocked
                        ? null
                        : () async {
                            final result = await showDialog<List<String>>(
                              context: context,
                              builder: (_) => _DnsServersDialog(
                                servers: settings['dnsCustom'] is List
                                    ? (settings['dnsCustom'] as List)
                                          .map((v) => v.toString())
                                          .toList()
                                    : const [],
                              ),
                            );
                            if (result != null &&
                                !controller.connected &&
                                !controller.busy) {
                              controller.patch({'dnsCustom': result});
                            }
                          },
                  ),
                ],
                const Divider(height: 28),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI-DNS'),
                  subtitle: const Text('Отдельный DNS для Gemini и AI Studio'),
                  value: settings['aiDns'] == true,
                  onChanged: networkLocked
                      ? null
                      : (value) => controller.patch({'aiDns': value}),
                ),
                if (settings['aiDns'] == true) ...[
                  const SizedBox(height: 8),
                  _Choice(
                    label: 'Регион AI-DNS',
                    value: region,
                    values: const {
                      'RU': 'Россия · RU',
                      'EU': 'Европа · EU',
                      'US': 'США · US',
                    },
                    enabled: !networkLocked,
                    onChanged: (value) =>
                        controller.patch({'aiDnsRegion': value}),
                  ),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('RU-оптимизация'),
                  subtitle: const Text('Яндекс DNS и определение доменов'),
                  value: settings['ruOptimization'] == true,
                  onChanged: networkLocked
                      ? null
                      : (value) => controller.patch({'ruOptimization': value}),
                ),
              ],
            ),
          const SizedBox(height: 10),
          if (category == null || category == 'windows')
            _Section(
              icon: LucideIcons.monitor,
              title: 'Windows',
              subtitle: 'Поведение окна, запуск и журнал приложения.',
              children: [
                if (platform.isWindows)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Запускать Dix вместе с Windows'),
                    subtitle: const Text('Автоподключение настраивается ниже'),
                    value: controller.windowsAutostart ?? false,
                    onChanged: (value) async {
                      try {
                        await controller.setWindowsAutostart(value);
                      } catch (error) {
                        if (context.mounted) {
                          showDixNotice(context, error);
                        }
                      }
                    },
                  ),
                AppSettingsControls(controller: controller),
                for (final item in [('Горячая клавиша', 'hotkeyEnabled')])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.$1)),
                        const SizedBox(width: 8),
                        Text(
                          settings.containsKey(item.$2)
                              ? settings[item.$2] == true
                                    ? 'Сохранено: вкл.'
                                    : 'Сохранено: выкл.'
                              : 'Не настроено',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 24),
                if (settings['killSwitch'] == true)
                  TextButton(
                    onPressed: locked
                        ? null
                        : () => controller.patch({'killSwitch': false}),
                    child: const Text('Отключить сохранённый Kill Switch'),
                  ),
                Text(
                  'Kill Switch и системная защита пока недоступны в этой сборке.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
        ],
      );
    },
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.values,
    required this.enabled,
    required this.onChanged,
  });
  final String label, value;
  final Map<String, String> values;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final item in values.entries)
        DropdownMenuItem(
          value: item.key,
          child: Text(item.value, overflow: TextOverflow.ellipsis),
        ),
      if (!values.containsKey(value))
        DropdownMenuItem(
          value: value,
          child: Text('Из перенесённых настроек: $value'),
        ),
    ],
    onChanged: enabled ? (value) => onChanged(value!) : null,
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final IconData icon;
  final String title, subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outline.withValues(alpha: .35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DnsServersDialog extends StatefulWidget {
  const _DnsServersDialog({required this.servers});
  final List<String> servers;
  @override
  State<_DnsServersDialog> createState() => _DnsServersDialogState();
}

class _DnsServersDialogState extends State<_DnsServersDialog> {
  late final field = TextEditingController(text: widget.servers.join('\n'));
  String? error;

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  void save() {
    final servers = field.text
        .split(RegExp(r'[,\n]'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    if (servers.isEmpty) {
      setState(() => error = 'Добавьте хотя бы один DNS-сервер');
      return;
    }
    for (final server in servers) {
      final valid =
          !server.startsWith('http://') && normalizeDnsResolver(server) != null;
      if (!valid) {
        setState(() => error = 'Проверьте адрес: $server');
        return;
      }
    }
    Navigator.pop(context, servers);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Свои DNS-серверы'),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 480,
        child: TextField(
          controller: field,
          minLines: 4,
          maxLines: 8,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'https://1.1.1.1/dns-query\nudp://1.2.3.4',
            helperText: 'По одному адресу на строку или через запятую',
            helperMaxLines: 2,
            errorText: error,
            errorMaxLines: 3,
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: save, child: const Text('Сохранить')),
    ],
  );
}
