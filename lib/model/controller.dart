import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../platform/platform.dart' as platform;
import 'archive.dart';
import 'rules.dart';
import 'app_updates.dart';
import 'startup_actions.dart';

class DixController extends ChangeNotifier {
  DixArchive archive;
  bool connected = false, busy = false;
  String? message;
  bool? windowsAutostart;
  bool checkingUpdates = false;
  String? updateStatus;
  AppRelease? availableRelease;
  String get updateRepository =>
      settings['flutterUpdateRepository']?.toString().trim() ??
      defaultUpdateRepository;
  final _startupActions = StartupActions();
  Future<void> applyStartupPreferences({bool isolated = false}) async {
    await _startupActions.run(
      settings,
      preview: preview,
      isolated: isolated,
      checkUpdates: () async {
        if (updateRepository.isNotEmpty) {
          await checkForUpdates();
        }
      },
      connect: () async {
        await toggle();
        if (!connected && message != null) await platform.showWindow();
      },
    );
  }

  Future<void> checkForUpdates() async {
    if (checkingUpdates) return;
    final repo = updateRepository;
    if (repo.isEmpty) {
      updateStatus = 'Источник GitHub пока не настроен';
      notifyListeners();
      return;
    }
    checkingUpdates = true;
    availableRelease = null;
    updateStatus = null;
    notifyListeners();
    final client = createClient();
    try {
      final release = await checkGitHubRelease(client, repo);
      availableRelease = release.available ? release : null;
      if (release.available && message == null) {
        message =
            'Доступна новая версия Dix ${release.version}. Откройте Настройки → Обновления.';
      }
      updateStatus = release.available
          ? 'Доступна версия ${release.version}'
          : 'Новых версий нет';
      platform.recordAppEvent('Проверка обновлений завершена');
    } catch (error) {
      updateStatus = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('FormatException: ', '');
      platform.recordAppEvent(
        'Ошибка проверки обновлений: ${error.runtimeType}',
      );
    } finally {
      client.close();
      checkingUpdates = false;
      notifyListeners();
    }
  }

  String? _browsedProfileId;
  DixArchive? _runningArchive;

  /// Browsing subscription contents never replaces a live tunnel's profile.
  String? get browsedProfileId =>
      archive.profiles.containsKey(_browsedProfileId)
      ? _browsedProfileId
      : archive.activeId;
  DixArchive? get runningArchive => _runningArchive;
  void captureRunningArchive([DixArchive? value]) {
    _runningArchive = (value ?? archive).clone();
  }

  List<DixServer> get browsingServers {
    try {
      return DixServer.fromProfile(
        parseProfile(archive.profiles[browsedProfileId]),
      );
    } catch (_) {
      return [];
    }
  }

  Future<void> browseProfile(String id) async {
    if (!archive.profiles.containsKey(id)) {
      throw StateError('Профиль не найден');
    }
    if (DixServer.fromProfile(parseProfile(archive.profiles[id])).isEmpty) {
      throw const FormatException('В профиле нет серверов');
    }
    if (!connected) {
      await activateProfile(id);
    }
    _browsedProfileId = id;
    notifyListeners();
  }

  Future<void> loadWindowsFeatures() async {
    if (!platform.isWindows || preview) return;
    windowsAutostart = await platform.readWindowsAutostart();
  }

  Future<void> setWindowsAutostart(bool enabled) async {
    if (preview) {
      windowsAutostart = enabled;
      notifyListeners();
      return;
    }
    await platform.setWindowsAutostart(enabled);
    windowsAutostart = enabled;
    notifyListeners();
  }

  List<double> history = List.filled(60, 0);
  double down = 0, up = 0;
  String? publicIp, ipLocation;
  bool checkingIp = false;
  final _profileDelays = <String, Map<String, int?>>{};
  Map<String, int?> get delays =>
      _profileDelays.putIfAbsent(browsedProfileId ?? '', () => {});
  bool pinging = false;
  int _pingGeneration = 0;
  final testingDelays = <String>{};
  int _sessionId = 0;
  DateTime? connectedAt;
  Timer? _timer, _subscriptionTimer;
  bool _refreshing = false;
  final http.Client Function() createClient;
  bool _polling = false;
  Future<void> _saving = Future.value();
  final bool preview;
  DixController(
    this.archive, {
    this.preview = false,
    http.Client Function()? createClient,
  }) : createClient = createClient ?? http.Client.new;
  static const _key = 'dix.flutter.archive.v1';
  static Future<DixController> load() async {
    final prefs = SharedPreferencesAsync();
    final saved = await prefs.getString(_key);
    final legacy = saved == null ? await platform.readLegacyBackup() : null;
    final controller = DixController(
      saved != null
          ? DixArchive.decode(saved)
          : legacy != null
          ? DixArchive.decode(legacy)
          : DixArchive.empty(),
    );
    if (legacy != null) await controller.save();
    return controller;
  }

  factory DixController.fixture() => DixController(
    DixArchive({
      'settings': {
        'appearance': 'minimal',
        'theme': 'dark',
        'anim': false,
        'currentServer': '🇫🇮 Финляндия',
        'routeMode': 'rule',
        'activeSub': 'preview',
        'advancedRules': {
          'enabled': true,
          'text': 'DOMAIN,dubapparels.com,DIRECT\nGEOSITE,discord,@VPN',
          'fallback': '@VPN',
        },
      },
      'profiles': {
        'preview': {
          'proxies': [
            for (final country in [
              '🇫🇮 Финляндия',
              '🇵🇱 Польша',
              '🇩🇪 Германия',
              '🇳🇱 Нидерланды',
            ])
              {'name': country, 'type': 'vless'},
          ],
          'proxy-groups': [
            {
              'name': 'Зарубежные сайты',
              'type': 'select',
              'proxies': [
                '🇫🇮 Финляндия',
                '🇵🇱 Польша',
                '🇩🇪 Германия',
                '🇳🇱 Нидерланды',
              ],
            },
          ],
          'rules': ['MATCH,Зарубежные сайты'],
        },
      },
    }),
    preview: true,
  );
  List<DixServer> get servers {
    try {
      return (connected ? _runningArchive ?? archive : archive).servers;
    } catch (_) {
      return [];
    }
  }

  DixServer? get selected =>
      servers
          .where(
            (s) =>
                s.name ==
                (connected ? _runningArchive ?? archive : archive)
                    .settings['currentServer'],
          )
          .firstOrNull ??
      servers.firstOrNull;
  Map<String, dynamic> get settings => archive.settings;
  void clearMessage() {
    message = null;
    notifyListeners();
  }

  void patch(Map<String, dynamic> value) {
    settings.addAll(value);
    if (value.containsKey('flutterUpdateRepository')) {
      updateStatus = null;
      availableRelease = null;
    }
    if (!preview && value.containsKey('flutterLogging')) {
      unawaited(
        platform.configureAppPreferences(settings).catchError((Object error) {
          message = 'Не удалось настроить журнал: ${error.runtimeType}';
          notifyListeners();
        }),
      );
    }
    notifyListeners();
    unawaited(
      save().catchError((Object e) {
        message = 'Не удалось сохранить: $e';
        notifyListeners();
      }),
    );
  }

  Future<void> save() {
    if (preview) return Future.value();
    final encoded = archive.encode();
    final operation = _saving
        .catchError((_) {})
        .then((_) => SharedPreferencesAsync().setString(_key, encoded));
    _saving = operation;
    return operation;
  }

  Future<void> select(DixServer server, {String? profileId}) async {
    if (busy) return;
    final id = profileId ?? browsedProfileId ?? archive.activeId;
    final runtime = (_runningArchive ?? archive).clone();
    final next = archive.clone();
    next.settings['activeSub'] = id;
    next.settings['currentServer'] = server.name;
    next.settings['selected'] = {
      ...jsonMap(next.settings['selected']),
      server.group: server.name,
      'GLOBAL': server.name,
    };
    message = null;
    if (connected) {
      busy = true;
      notifyListeners();
      try {
        if (id != runtime.activeId ||
            jsonEncode(runtime.profiles[id]) != jsonEncode(next.profiles[id])) {
          await platform.replaceNativeProfile(
            configuredProfile(next, selected: server.name),
            next.settings,
          );
          captureRunningArchive(next);
        } else {
          final selected = await platform.nativeSelect(
            server.group,
            server.name,
          );
          runtime.settings['currentServer'] = server.name;
          runtime.settings['selected'] = {
            ...jsonMap(runtime.settings['selected']),
            ...selected,
          };
          captureRunningArchive(runtime);
        }
        if (settings['flutterCloseConnections'] == true) {
          try {
            await platform.closeNativeConnections();
          } catch (error) {
            message =
                'Сервер изменён, но старые соединения не закрылись. Повторите подключение при необходимости.';
          }
        }
        platform.recordAppEvent('Сервер изменён');
      } catch (error) {
        message = 'Не удалось сменить сервер: $error';
        if (!platform.nativeRuntimeAlive) {
          connected = false;
          _timer?.cancel();
        }
        return;
      } finally {
        busy = false;
        notifyListeners();
      }
    }
    patch({
      'activeSub': id,
      'currentServer': server.name,
      'selected': next.settings['selected'],
    });
    if (connected) {
      _sessionId++;
      checkingIp = false;
      publicIp = ipLocation = null;
      unawaited(refreshIp());
    }
  }

  Future<void> refreshIp() async {
    if (!connected || checkingIp || preview) return;
    final session = _sessionId;
    checkingIp = true;
    notifyListeners();
    try {
      final result = await platform.nativeIp();
      if (connected && session == _sessionId) {
        publicIp = result['ip'];
        ipLocation = result['location'];
      }
    } catch (_) {
      if (session == _sessionId) {
        publicIp = null;
        ipLocation = 'Не удалось проверить IP';
      }
    } finally {
      if (session == _sessionId) checkingIp = false;
      notifyListeners();
    }
  }

  Future<void> testDelay(DixServer server) => testDelays([server]);
  Future<void> testDelays(List<DixServer> servers) async {
    if (pinging || preview || servers.isEmpty) return;
    final id = browsedProfileId ?? archive.activeId ?? '';
    final names = servers.map((s) => s.name).toSet().toList();
    final source = archive.clone();
    source.settings['activeSub'] = id;
    source.settings['advancedRules'] = {'enabled': false};
    source.settings['rules'] = [];
    source.settings['routeMode'] = 'global';
    source.settings['aiDns'] = false;
    final generation = ++_pingGeneration;
    pinging = true;
    testingDelays.addAll(names);
    notifyListeners();
    try {
      await platform.nativeMeasureDelays(
        configuredProfile(source, selected: names.first),
        source.settings,
        names,
        onResult: (name, value) {
          if (generation != _pingGeneration) return;
          _profileDelays.putIfAbsent(id, () => {})[name] = value;
          testingDelays.remove(name);
          notifyListeners();
        },
      );
    } catch (error) {
      if (generation == _pingGeneration) {
        message = 'Не удалось проверить задержку: $error';
      }
    } finally {
      if (generation == _pingGeneration) {
        pinging = false;
        testingDelays.clear();
        notifyListeners();
      }
    }
  }

  Future<void> cancelPings() async {
    _pingGeneration++;
    pinging = false;
    testingDelays.clear();
    notifyListeners();
    await platform.cancelNativeDelays();
  }

  Future<void> importBackup(String source) async {
    if (connected || busy) throw StateError('Отключите VPN перед импортом');
    final candidate = DixArchive.decode(source);
    final old = archive;
    archive = candidate;
    try {
      await save();
    } catch (_) {
      archive = old;
      rethrow;
    }
    message = 'Данные импортированы';
    notifyListeners();
  }

  Future<void> addProfile(
    String name,
    String source, {
    Map<String, dynamic> metadata = const {},
  }) async {
    final parsed = parseProfile(source);
    if (DixServer.fromProfile(parsed).isEmpty) {
      throw const FormatException('В профиле не найдены серверы Clash/Mihomo');
    }
    final id = 'flutter-${DateTime.now().microsecondsSinceEpoch}';
    final old = archive.clone();
    archive.profiles[id] = source;
    if (!connected) settings['activeSub'] = id;
    final subs = archive.subscriptions;
    subs.add({
      ...metadata,
      'id': id,
      'name': name,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    settings['subs'] = subs;
    try {
      await save();
    } catch (_) {
      archive = old;
      rethrow;
    }
    _browsedProfileId = id;
    notifyListeners();
  }

  Future<({String source, Map<String, dynamic> metadata})>
  _downloadSubscription(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Нужна HTTPS-ссылка подписки');
    }
    final client = createClient();
    try {
      final reply = await client
          .get(
            uri,
            headers: {
              'User-Agent': 'Clash/Meta; DixVPN/v5.1.0 Platform/windows',
            },
          )
          .timeout(const Duration(seconds: 25));
      if (reply.statusCode != 200) {
        throw StateError('Сервер вернул ${reply.statusCode}');
      }
      if (reply.bodyBytes.length > 16 * 1024 * 1024) {
        throw const FormatException('Подписка слишком большая');
      }
      final source = utf8.decode(reply.bodyBytes);
      if (DixServer.fromProfile(parseProfile(source)).isEmpty) {
        throw const FormatException('Сервер не вернул профиль Clash/Mihomo');
      }
      return (
        source: source,
        metadata: {
          'url': url,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          if (reply.headers['subscription-userinfo'] != null)
            'userinfo': reply.headers['subscription-userinfo'],
          if (int.tryParse(reply.headers['profile-update-interval'] ?? '')
              case final int interval when interval > 0)
            'interval': interval,
        },
      );
    } finally {
      client.close();
    }
  }

  Future<void> importUrl(String url) async {
    final data = await _downloadSubscription(url);
    await addProfile(Uri.parse(url).host, data.source, metadata: data.metadata);
  }

  Future<void> refreshProfile(String id) async {
    if (_refreshing) {
      throw StateError('Дождитесь завершения обновления подписки');
    }
    final sub = archive.subscriptions
        .where((s) => s['id']?.toString() == id)
        .firstOrNull;
    final url = sub?['url']?.toString();
    if (url == null || url.isEmpty) {
      throw StateError('У файлового профиля нет ссылки для обновления');
    }
    _refreshing = true;
    try {
      final data = await _downloadSubscription(url);
      if (!archive.profiles.containsKey(id)) {
        throw StateError('Состояние профиля изменилось, повторите обновление');
      }
      final old = archive.clone();
      if (connected && _runningArchive == null) captureRunningArchive();
      archive.profiles[id] = data.source;
      settings['subs'] = [
        for (final item in archive.subscriptions)
          if (item['id']?.toString() == id)
            {...item, ...data.metadata}
          else
            item,
      ];
      try {
        await save();
      } catch (_) {
        archive = old;
        rethrow;
      }
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  void startBackgroundTasks() {
    if (preview || _subscriptionTimer != null) return;
    _subscriptionTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      if (settings['autoUpdateSubs'] == false || busy || _refreshing) {
        return;
      }
      for (final sub in archive.subscriptions) {
        final updated =
            num.tryParse(sub['updatedAt']?.toString() ?? '')?.toInt() ?? 0;
        final hours =
            num.tryParse(sub['interval']?.toString() ?? '')?.clamp(1, 168) ??
            24;
        if (sub['url'] is String &&
            DateTime.now().millisecondsSinceEpoch - updated >=
                hours * 3600000) {
          try {
            await refreshProfile(sub['id'].toString());
          } catch (_) {
            /* Keep the last working profile and retry on a later tick. */
          }
          break;
        }
      }
    });
  }

  Future<void> renameProfile(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Введите название профиля');
    }
    if (!archive.profiles.containsKey(id)) {
      throw StateError('Профиль не найден');
    }
    final old = archive.clone();
    final subs = archive.subscriptions;
    final index = subs.indexWhere((s) => s['id']?.toString() == id);
    if (index < 0) {
      subs.add({'id': id, 'name': trimmed});
    } else {
      subs[index] = {...subs[index], 'name': trimmed};
    }
    settings['subs'] = subs;
    try {
      await save();
    } catch (_) {
      archive = old;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> activateProfile(String id) async {
    if (connected || busy) {
      throw StateError('Отключите VPN перед сменой профиля');
    }
    if (!archive.profiles.containsKey(id)) {
      throw StateError('Профиль не найден');
    }
    final servers = DixServer.fromProfile(parseProfile(archive.profiles[id]));
    if (servers.isEmpty) throw const FormatException('В профиле нет серверов');
    final old = archive.clone();
    settings['activeSub'] = id;
    _browsedProfileId = id;
    settings['currentServer'] = servers.first.name;
    settings['selected'] = {
      ...jsonMap(settings['selected']),
      servers.first.group: servers.first.name,
      'GLOBAL': servers.first.name,
    };
    try {
      await save();
    } catch (_) {
      archive = old;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> removeProfile(String id) async {
    if (connected && (runningArchive ?? archive).activeId == id) {
      throw StateError(
        'Этот профиль используется подключением. Сначала выберите сервер другой подписки или отключите VPN',
      );
    }
    if (!archive.profiles.containsKey(id)) return;
    final old = archive.clone();
    final wasActive = archive.activeId == id;
    archive.profiles.remove(id);
    for (final key in ['subs', 'subscriptions']) {
      final records = settings[key];
      if (records is List) {
        settings[key] = records
            .where((s) => s is! Map || s['id']?.toString() != id)
            .toList();
      }
    }
    if (wasActive) {
      settings['activeSub'] = archive.profiles.keys.firstOrNull ?? '';
      settings.remove('currentServer');
      final selection = jsonMap(settings['selected']);
      selection.remove('GLOBAL');
      settings['selected'] = selection;
    }
    if (_browsedProfileId == id) _browsedProfileId = null;
    try {
      await save();
    } catch (_) {
      archive = old;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    if (busy) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      if (connected) {
        await platform.stopNativeVpn();
        connected = false;
        _timer?.cancel();
        down = up = 0;
        _sessionId++;
        publicIp = ipLocation = null;
        checkingIp = false;
      } else {
        if (preview) {
          throw StateError('Предпросмотр интерфейса: VPN не запускается');
        }
        final server = selected;
        if (server == null) {
          throw StateError(
            'Добавьте подписку или импортируйте резервную копию Dix',
          );
        }
        final starting = archive.clone();
        starting.settings['currentServer'] = server.name;
        starting.settings['selected'] = {
          ...jsonMap(starting.settings['selected']),
          server.group: server.name,
          'GLOBAL': server.name,
        };
        await platform.startNativeVpn(
          configuredProfile(starting, selected: server.name),
          starting.settings,
        );
        settings['currentServer'] = server.name;
        settings['selected'] = starting.settings['selected'];
        captureRunningArchive();
        connected = true;
        platform.recordAppEvent('VPN подключён');
        _sessionId++;
        publicIp = ipLocation = null;
        checkingIp = false;
        unawaited(refreshIp());
        connectedAt = DateTime.now();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
      }
    } catch (e) {
      message = e.toString().replaceFirst('Bad state: ', '');
      platform.recordAppEvent('Ошибка подключения: ${e.runtimeType}');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _poll() async {
    if (_polling || !connected || busy) return;
    _polling = true;
    try {
      final traffic = await platform.nativeTraffic();
      if (!connected) return;
      down = (traffic['down'] ?? traffic['download'] ?? 0).toDouble() * 8 / 1e6;
      up = (traffic['up'] ?? traffic['upload'] ?? 0).toDouble() * 8 / 1e6;
      history = [...history.skip(1), down];
      notifyListeners();
    } catch (e) {
      if (busy) return;
      message = 'Ошибка ядра: $e';
      connected = false;
      _timer?.cancel();
      down = up = 0;
      try {
        await platform.stopNativeVpn();
      } catch (cleanup) {
        message = '$message · $cleanup';
      }
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  Future<void> shutdown() async {
    busy = true;
    _timer?.cancel();
    _subscriptionTimer?.cancel();
    notifyListeners();
    try {
      await cancelPings();
      await platform.stopNativeVpn();
      connected = false;
      await _saving;
      await platform.flushNativeLogs();
    } catch (error) {
      message = 'Не удалось завершить сеанс: $error';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscriptionTimer?.cancel();
    super.dispose();
  }
}
