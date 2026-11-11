import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core_rpc.dart';
import 'core_session.dart';
import 'core_probe.dart';
import 'core_selection.dart';
import 'core_latency.dart';
import 'app_journal.dart';
import 'windows_system.dart';

bool get isWindows => Platform.isWindows;
bool get isIOS => Platform.isIOS;
const _channel = MethodChannel('app.dix/vpn');
Future<void> prepareWindow({bool hidden = false}) async {
  if (!isWindows) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1180, 820),
      minimumSize: Size(760, 620),
      title: 'Dix',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    ),
    () async {
      if (!hidden) await showWindow();
    },
  );
}

Future<String?> readLegacyBackup() async {
  if (!isWindows) return null;
  final roaming = Platform.environment['APPDATA'];
  if (roaming == null) return null;
  final settings = File('$roaming/DixVPN-Client/settings.json');
  if (!await settings.exists()) return null;
  final profiles = <String, String>{};
  final dir = Directory('$roaming/dixvpn-next/home/profiles');
  if (await dir.exists()) {
    await for (final f in dir.list()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (!RegExp(r'\.(json|yaml|yml)$').hasMatch(name)) continue;
      profiles[name.replaceFirst(RegExp(r'\.(json|yaml|yml)$'), '')] = await f
          .readAsString();
    }
  }
  return jsonEncode({
    'settings': jsonDecode(await settings.readAsString()),
    'profiles': profiles,
  });
}

Future<void> saveText(String name, String value) async {
  if (isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(value, flush: true);
    await _channel.invokeMethod<void>('shareBackup', {'path': file.path});
    return;
  }
  final destination = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      const XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
  );
  if (destination == null) return;
  await XFile.fromData(
    utf8.encode(value),
    name: name,
    mimeType: 'application/json',
  ).saveTo(destination.path);
}

CoreRpc? _core, _measurement;
Object? _measurementToken;
bool _measurementOwned = false;
Map<String, dynamic>? _activeProfile, _activeSettings;
String? _manualRoot;
bool get nativeRuntimeAlive => _core?.isAlive == true;
ManualRoutingProfile _manualProfile(
  Map<String, dynamic> profile,
  Map<String, dynamic> settings,
) {
  final groups = (profile['proxy-groups'] as List? ?? []).whereType<Map>();
  var root = mainRoutingGroup(profile);
  if (root != null && root.contains(',')) {
    final alias = groups
        .where(
          (g) =>
              (g['proxies'] as List? ?? []).length == 1 &&
              (g['proxies'] as List).first == root &&
              !g['name'].toString().contains(','),
        )
        .firstOrNull;
    root = alias?['name']?.toString() ?? root;
  }
  return prepareManualRoutingProfile(
    profile,
    rootGroup: root,
    selectedServer: settings['currentServer']?.toString(),
  );
}

Map<String, dynamic> _selection(Map<String, dynamic> settings, String root) => {
  ...Map<String, dynamic>.from(settings['selected'] as Map? ?? {}),
  if (settings['currentServer'] != null) root: settings['currentServer'],
};
WindowsProxyLease? _proxy;
Future<void>? _stopping;
const _windowsChannel = MethodChannel('app.dix/windows');
final _runtimeLogs = <String>[];
AppJournal? _journal;
List<String> get nativeLogs => _journal?.entries ?? const [];
Future<void> configureAppPreferences(Map<String, dynamic> settings) async {
  if (!isWindows) return;
  _journal ??= AppJournal(Directory('${(await _appDirectory()).path}/logs'));
  await _journal!.setEnabled(settings['flutterLogging'] == true);
  if (settings['flutterLogging'] == true) _log('Журнал событий включён');
}

void recordAppEvent(String event) => _log(event);
Future<void> flushNativeLogs() async => _journal?.flush();
Future<void> clearNativeLogs() async => _journal?.clear();

void _log(String message) {
  _journal?.record(message);
  _runtimeLogs.add('${DateTime.now().toIso8601String()} $message');
  if (_runtimeLogs.length > 200) _runtimeLogs.removeAt(0);
}

Future<Directory> _appDirectory() => getApplicationSupportDirectory();
Future<WindowsProxyLease> _proxyLease() async =>
    _proxy ??= WindowsProxyLease(directory: await _appDirectory());

Future<void> initializeNativeRuntime() async {
  if (isWindows) await (await _proxyLease()).recoverAbandoned();
}

Future<void> _availablePort(int port) async {
  try {
    final socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    await socket.close();
  } on SocketException {
    throw StateError('Порт $port занят. Отключите другой VPN или прокси.');
  }
}

Future<void> _checkLegacyClient() async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      7897,
      timeout: const Duration(milliseconds: 350),
    );
    socket.destroy();
  } on SocketException {
    return;
  }
  throw StateError(
    'Отключите VPN в прежнем Dix перед подключением Flutter-версии.',
  );
}

Future<String> _coreExecutable(Map<String, dynamic> settings) async {
  final custom = settings['flutterCorePath']?.toString().trim();
  final candidates = [
    if (custom != null && custom.isNotEmpty) custom,
    '${File(Platform.resolvedExecutable).parent.path}/core/DixCore.exe',
  ];
  for (final path in candidates) {
    if (await File(path).exists()) return File(path).absolute.path;
  }
  throw StateError(
    'Ядро отсутствует. Распакуйте весь архив Dix вместе с папкой core.',
  );
}

Future<void> startNativeVpn(
  Map<String, dynamic> profile,
  Map<String, dynamic> settings,
) async {
  if (isIOS) {
    await _channel.invokeMethod<void>('connect', {
      'config': jsonEncode(profile),
    });
    return;
  }
  if (!isWindows) {
    throw UnsupportedError('Подключение доступно только на Windows');
  }
  if (_core != null || _stopping != null) {
    throw StateError('Подключение уже запущено или завершается');
  }
  if (settings['killSwitch'] == true) {
    throw UnsupportedError(
      'Kill Switch пока не перенесён. Отключите сохранённый Kill Switch в настройках или используйте прежний Dix.',
    );
  }
  final tun = settings['netMode'] != 'proxy';
  if (tun && !await WindowsSystem.isAdministrator()) {
    throw StateError(
      'Для режима TUN запустите Dix от имени администратора. Режим «Системный прокси» работает без этих прав.',
    );
  }
  await _checkLegacyClient();
  final mixedPort = profile['mixed-port'] as int;
  await _availablePort(mixedPort);
  final lease = await _proxyLease();
  await lease.recoverAbandoned();
  final exe = await _coreExecutable(settings);
  final home = Directory('${(await _appDirectory()).path}/core');
  await home.create(recursive: true);
  for (final name in ['GeoSite.dat', 'geoip.metadb']) {
    final source = File('${File(exe).parent.path}/$name');
    if (!await source.exists()) throw StateError('В сборке отсутствует $name');
    // Copy from the bundled engine, never from a running client's mutable home.
    await source.copy('${home.path}/$name');
  }
  final rpc = CoreRpc();
  _core = rpc;
  _runtimeLogs.clear();
  _log('Запуск ядра · ${tun ? 'TUN' : 'системный прокси'}');
  try {
    await rpc.start(exe, home.path);
    await _windowsChannel.invokeMethod<bool>('attachCore', rpc.pid);
    final initialized = await rpc.call(
      'initClash',
      jsonEncode({'home-dir': home.path, 'version': 20}),
    );
    if (initialized != true && initialized != 'true') {
      throw StateError('Ядро не инициализировано');
    }
    final prepared = _manualProfile(profile, settings);
    await applyCoreProfile(
      rpc,
      prepared.profile,
      tun: tun,
      selected: _selection(settings, prepared.rootGroup),
    );
    _activeProfile = prepared.profile;
    _activeSettings = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(settings)) as Map,
    );
    _manualRoot = prepared.rootGroup;
    final check = await Socket.connect(
      '127.0.0.1',
      mixedPort,
      timeout: const Duration(seconds: 3),
    );
    check.destroy();
    if (!rpc.isAlive) throw StateError('Ядро завершилось до подключения');
    if (!tun) await lease.enable(mixedPort);
    _log('Ядро работает; профиль и правила применены');
  } catch (error) {
    _log('Ошибка подключения: ${error.runtimeType}');
    await stopNativeVpn();
    rethrow;
  }
}

Future<void> stopNativeVpn() =>
    _stopping ??= _stopNativeVpn().whenComplete(() => _stopping = null);
Future<void> _stopNativeVpn() async {
  if (isIOS) {
    await _channel.invokeMethod<void>('disconnect');
    return;
  }
  Object? restoreError;
  try {
    await _proxy?.restore();
  } catch (error) {
    restoreError = error;
  }
  final core = _core;
  _core = null;
  _activeProfile = _activeSettings = null;
  _manualRoot = null;
  if (core != null) {
    for (final method in ['stopTun', 'stopListener']) {
      try {
        await core.call(method, null, const Duration(seconds: 3));
      } catch (_) {}
    }
    await core.close();
    _log('Ядро остановлено');
  }
  if (restoreError != null) {
    throw StateError('Прокси Windows не восстановлен: $restoreError');
  }
}

Future<Map<String, num>> nativeTraffic() async {
  if (isIOS) {
    return Map<String, num>.from(
      await _channel.invokeMapMethod<String, num>('traffic') ?? {},
    );
  }
  final core = _core;
  if (core == null || !core.isAlive) throw StateError('Ядро не запущено');
  var raw = await core.call('getTraffic', null, const Duration(seconds: 4));
  if (raw is String) raw = jsonDecode(raw);
  if (raw is! Map) throw const FormatException('Некорректная статистика ядра');
  return {
    for (final entry in raw.entries)
      if (entry.value is num) entry.key.toString(): entry.value as num,
  };
}

Future<bool> restartAsAdministrator() async {
  final started = await WindowsSystem.relaunchElevated();
  if (started) await windowManager.destroy();
  return started;
}

Future<bool> installCloseHandler(
  Future<void> Function() cleanup, {
  required Map<String, dynamic> Function() settings,
}) async {
  if (!isWindows) return false;
  await windowManager.ensureInitialized();
  final listener = _CloseListener(cleanup, settings);
  windowManager.addListener(listener);
  await windowManager.setPreventClose(true);
  _windowsChannel.setMethodCallHandler((call) async {
    if (call.method == 'trayAction') {
      if (call.arguments == 'open') await showWindow();
      if (call.arguments == 'quit') await listener.quit();
    }
  });
  final enabled =
      await _windowsChannel.invokeMethod<bool>('setTrayEnabled', true) ?? false;
  listener.trayReady = enabled;
  return enabled;
}

Future<void> showWindow() async {
  if (!isWindows) return;
  await _windowsChannel.invokeMethod<bool>('showWindow');
  await windowManager.focus();
}

class _CloseListener extends WindowListener {
  final Future<void> Function() cleanup;
  final Map<String, dynamic> Function() settings;
  bool closing = false, trayReady = false;
  _CloseListener(this.cleanup, this.settings);
  @override
  void onWindowClose() async {
    if (closing) return;
    if (trayReady && settings()['flutterMinimizeToTray'] != false) {
      await windowManager.hide();
      _log('Окно скрыто в трей');
      return;
    }
    await quit();
  }

  Future<void> quit() async {
    if (closing) return;
    closing = true;
    try {
      await cleanup();
      await flushNativeLogs();
      await _windowsChannel.invokeMethod<bool>('setTrayEnabled', false);
      await windowManager.destroy();
    } catch (error) {
      closing = false;
      _log('Ошибка завершения сеанса: ${error.runtimeType}');
      await showWindow();
    }
  }
}

Future<void> closeNativeConnections() async {
  final rpc = _core;
  if (rpc == null || !rpc.isAlive) throw StateError('Ядро не подключено');
  await rpc.call('closeConnections', null, const Duration(seconds: 8));
  _log('Старые соединения закрыты после смены сервера');
}

Future<void> openReleaseUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri?.scheme != 'https' || uri?.host != 'github.com') {
    throw const FormatException('Ожидается ссылка релиза GitHub');
  }
  if (isWindows &&
      await _windowsChannel.invokeMethod<bool>('openReleaseUrl', url) != true) {
    throw StateError('Не удалось открыть страницу релиза');
  }
}

Future<Map<String, dynamic>> runWindowLifecycleSelfTest() async {
  final initial = await _windowsChannel.invokeMapMethod<String, dynamic>(
    'windowState',
  );
  await showWindow();
  await windowManager.close();
  Map<String, dynamic>? hidden;
  for (var attempt = 0; attempt < 40; attempt++) {
    hidden = await _windowsChannel.invokeMapMethod<String, dynamic>(
      'windowState',
    );
    if (hidden?['visible'] == false) break;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  await showWindow();
  final shown = await _windowsChannel.invokeMapMethod<String, dynamic>(
    'windowState',
  );
  return {
    'hiddenStartupVerified': initial?['visible'] == false,
    'trayEnabled': hidden?['trayEnabled'] == true,
    'closeToTrayVerified': hidden?['visible'] == false,
    'restoreVerified': shown?['visible'] == true,
  };
}

Future<void> runNativeVpnSelfTest(
  String output,
  List<Map<String, dynamic>> cases,
) async {
  final report = <String, dynamic>{
    'scope':
        'temporary actual Windows TUN; settings unchanged; own adapter removed after test',
    'cases': <Map<String, dynamic>>[],
  };
  var passed = cases.length == 2;
  try {
    for (final entry in cases) {
      final row = <String, dynamic>{'protocol': entry['protocol']};
      (report['cases'] as List).add(row);
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        await startNativeVpn(
          Map<String, dynamic>.from(entry['profile'] as Map),
          Map<String, dynamic>.from(entry['settings'] as Map),
        );
        dynamic tun = await _core!.call('getTunStatus', null);
        if (tun is String) tun = jsonDecode(tun);
        row['tunEnabled'] = tun is Map && tun['enabled'] == true;
        final delays = await nativeMeasureDelays(
          Map<String, dynamic>.from(entry['profile'] as Map),
          Map<String, dynamic>.from(entry['settings'] as Map),
          [entry['server'] as String],
          useActiveCore: true,
        );
        row['delayMs'] = delays[entry['server']];
        final request = await client
            .getUrl(Uri.parse('https://www.gstatic.com/generate_204'))
            .timeout(const Duration(seconds: 12));
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        row['systemHttpsStatus'] = response.statusCode;
        await response.drain<void>();
        dynamic connections = await _core!.call('getConnections', null);
        if (connections is String) connections = jsonDecode(connections);
        final items = connections is Map
            ? connections['connections'] as List? ?? []
            : const [];
        row['systemTrafficUsesSelectedServer'] = items.whereType<Map>().any(
          (value) =>
              (value['chains'] as List? ?? []).contains(entry['server']) &&
              (value['metadata'] as Map?)?['host'] == 'www.gstatic.com',
        );
        final ip = await nativeIp();
        row['exitCountry'] = ip['countryCode'];
        final okay =
            row['tunEnabled'] == true &&
            row['systemHttpsStatus'] == 204 &&
            row['systemTrafficUsesSelectedServer'] == true &&
            row['delayMs'] is int;
        if (!okay) passed = false;
      } catch (error) {
        passed = false;
        row['error'] = error.toString();
      } finally {
        client.close(force: true);
        await cancelNativeDelays();
        await stopNativeVpn();
      }
    }
  } catch (error) {
    passed = false;
    report['error'] = error.runtimeType.toString();
  }
  report['passed'] = passed;
  report['closed'] = _core == null;
  await File(output).writeAsString(jsonEncode(report), flush: true);
  exit(passed ? 0 : 1);
}

Future<void> runNativeSelfTest(String output) async {
  try {
    final report = File(output).absolute;
    await report.parent.create(recursive: true);
    final results = await probeCore(
      await _coreExecutable({}),
      '${report.parent.path}/native-core-self-test',
      supervise: (pid) async {
        await _windowsChannel.invokeMethod<bool>('attachCore', pid);
      },
    );
    results['administrator'] = await WindowsSystem.isAdministrator();
    await report.writeAsString(jsonEncode(results), flush: true);
    exit(0);
  } catch (error, stack) {
    await File(output).writeAsString(
      jsonEncode({'error': error.toString(), 'stack': stack.toString()}),
      flush: true,
    );
    exit(1);
  }
}

Future<Map<String, String>> nativeSelect(String group, String server) async {
  final rpc = _core;
  if (rpc == null || !rpc.isAlive) throw StateError('Ядро не подключено');
  final changed = await selectRuntimeServer(
    (method, data) => rpc.call(method, data),
    preferredGroup: group,
    server: server,
    rootGroup: _manualRoot,
    global: _activeProfile?['mode'] == 'global',
  );
  _activeSettings?['currentServer'] = server;
  _activeSettings?['selected'] = {
    ...Map<String, dynamic>.from(_activeSettings?['selected'] as Map? ?? {}),
    ...changed,
  };
  return changed;
}

Future<void> replaceNativeProfile(
  Map<String, dynamic> profile,
  Map<String, dynamic> settings,
) async {
  final rpc = _core,
      previous = _activeProfile,
      previousSettings = _activeSettings,
      previousRoot = _manualRoot;
  if (rpc == null || previous == null || previousSettings == null) {
    throw StateError('Ядро не подключено');
  }
  final tun = previousSettings['netMode'] != 'proxy';
  final prepared = _manualProfile(profile, settings);
  try {
    await applyCoreProfile(
      rpc,
      prepared.profile,
      tun: tun,
      selected: _selection(settings, prepared.rootGroup),
    );
    _activeProfile = prepared.profile;
    _activeSettings = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(settings)) as Map,
    )..['netMode'] = previousSettings['netMode'];
    _manualRoot = prepared.rootGroup;
  } catch (_) {
    try {
      await applyCoreProfile(
        rpc,
        previous,
        tun: tun,
        selected: _selection(previousSettings, previousRoot!),
      );
    } catch (_) {
      await stopNativeVpn();
    }
    rethrow;
  }
}

Future<Map<String, int?>> nativeMeasureDelays(
  Map<String, dynamic> profile,
  Map<String, dynamic> settings,
  List<String> names, {
  bool useActiveCore = false,
  void Function(String, int?)? onResult,
}) async {
  if (_measurementToken != null) {
    throw StateError('Проверка задержки уже выполняется');
  }
  final token = Object();
  _measurementToken = token;
  final live = useActiveCore && _core?.isAlive == true ? _core : null;
  final rpc = live ?? CoreRpc();
  final owned = live == null;
  _measurement = rpc;
  _measurementOwned = owned;
  Directory? home;
  final result = <String, int?>{};
  bool current() => _measurementToken == token;
  try {
    if (owned) {
      final exe = await _coreExecutable(settings);
      final base = Directory('${(await _appDirectory()).path}/measurements');
      await base.create(recursive: true);
      home = await base.createTemp('batch-');
      for (final name in ['GeoSite.dat', 'geoip.metadb']) {
        await File('${File(exe).parent.path}/$name').copy('${home.path}/$name');
      }
      if (!current()) return result;
      await rpc.start(exe, home.path);
      await _windowsChannel.invokeMethod<bool>('attachCore', rpc.pid);
      await rpc.call(
        'initClash',
        jsonEncode({'home-dir': home.path, 'version': 20}),
      );
      final config =
          Map<String, dynamic>.from(jsonDecode(jsonEncode(profile)) as Map)
            ..['mixed-port'] = 0
            ..['mode'] = 'rule'
            ..['rule'] = ['MATCH,DIRECT'];
      if (_core?.isAlive == true) {
        dynamic state = await _core!.call('getTunStatus', null);
        if (state is String) state = jsonDecode(state);
        final outbound = state is Map
            ? state['outboundInterface']?.toString() ?? ''
            : '';
        if (outbound.isNotEmpty) {
          config['interface-name'] = outbound;
        } else if (state is Map && state['enabled'] == true) {
          throw StateError(
            'Для проверки другой подписки отключите VPN: не удалось определить внешний сетевой адаптер.',
          );
        }
      }
      await applyCoreProfile(rpc, config, tun: false, startListener: false);
    }
    var cursor = 0;
    Future<void> worker() async {
      while (current() && cursor < names.length) {
        final name = names[cursor++];
        final timeout =
            (settings['pingTimeoutSeconds'] is num
                    ? (settings['pingTimeoutSeconds'] as num).toInt()
                    : 10)
                .clamp(5, 20);
        final value = await measureProxyLatency(
          (method, data) =>
              rpc.call(method, data, Duration(seconds: timeout + 3)),
          name,
          timeoutMs: timeout * 1000,
          cancelled: () => !current(),
        );
        if (current()) {
          result[name] = value;
          onResult?.call(name, value);
        }
      }
    }

    await Future.wait(
      List.generate(names.length < 3 ? names.length : 3, (_) => worker()),
    );
    return result;
  } finally {
    if (current()) {
      _measurementToken = null;
      _measurement = null;
      _measurementOwned = false;
    }
    if (owned) await rpc.close();
    if (home != null && await home.exists()) {
      final base = Directory(
        '${(await _appDirectory()).path}/measurements',
      ).absolute;
      if (home.absolute.uri.toString().startsWith(base.uri.toString()) &&
          home.absolute.uri != base.uri) {
        await home.delete(recursive: true);
      }
    }
  }
}

Future<void> cancelNativeDelays() async {
  final rpc = _measurement;
  final owned = _measurementOwned;
  _measurementToken = null;
  _measurement = null;
  _measurementOwned = false;
  if (owned) await rpc?.close();
}

Future<int> nativeDelay(String server) async {
  final rpc = _core;
  if (rpc == null || !rpc.isAlive) {
    throw StateError('Подключите VPN перед проверкой');
  }
  var result = await rpc.call(
    'asyncTestDelay',
    jsonEncode({
      'proxy-name': server,
      'test-url': 'https://www.gstatic.com/generate_204',
      'timeout': 5000,
    }),
    const Duration(seconds: 8),
  );
  if (result is String) result = jsonDecode(result);
  return result is Map && result['value'] is num
      ? (result['value'] as num).toInt()
      : -1;
}

Future<Map<String, String>> nativeIp() async {
  if (_core == null || !_core!.isAlive) throw StateError('Ядро не подключено');
  final client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:17897';
  try {
    final request = await client
        .getUrl(Uri.parse('https://ipwho.is/'))
        .timeout(const Duration(seconds: 8));
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw HttpException('IP lookup HTTP ${response.statusCode}');
    }
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    final data = jsonDecode(text);
    if (data is! Map ||
        data['success'] != true ||
        InternetAddress.tryParse(data['ip']?.toString() ?? '') == null) {
      throw const FormatException('Не удалось определить IP');
    }
    return {
      'ip': data['ip'].toString(),
      'countryCode': data['country_code']?.toString() ?? '',
      'location': [
        data['city'],
        data['country'],
      ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
    };
  } finally {
    client.close(force: true);
  }
}

Future<bool> readWindowsAutostart() async =>
    isWindows &&
    (await WindowsSystem.command({
          'action': 'startupRead',
          'executable': Platform.resolvedExecutable,
        }))['enabled'] ==
        true;
Future<void> setWindowsAutostart(bool enabled) async {
  if (!isWindows) return;
  await WindowsSystem.command({
    'action': 'startupSet',
    'executable': Platform.resolvedExecutable,
    'enabled': enabled,
  });
}

Future<void> finishStartupSelfTest(
  String output,
  Map<String, dynamic> report,
) async {
  final state = await _windowsChannel.invokeMapMethod<String, dynamic>(
    'windowState',
  );
  report['window'] = state;
  await _windowsChannel.invokeMethod<bool>('setTrayEnabled', false);
  await File(output).writeAsString(jsonEncode(report), flush: true);
  exit(report['startupError'] == null ? 0 : 1);
}

Future<void> dragWindow() async {
  if (isWindows) await windowManager.startDragging();
}

Future<void> minimizeWindow() async {
  if (isWindows) await windowManager.minimize();
}

Future<void> toggleMaximizeWindow() async {
  if (!isWindows) return;
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

Future<void> closeWindow() async {
  if (isWindows) await windowManager.close();
}
