import 'package:flutter/services.dart';

bool get isWindows => false;
bool get isIOS => false;
Future<void> prepareWindow({bool hidden = false}) async {}
Future<String?> readLegacyBackup() async => null;
Future<void> saveText(String name, String value) =>
    Clipboard.setData(ClipboardData(text: value));
Future<void> startNativeVpn(
  Map<String, dynamic> profile,
  Map<String, dynamic> settings,
) async => throw UnsupportedError(
  'VPN недоступен в браузере. Здесь можно проверить интерфейс и редактировать профиль.',
);
Future<void> stopNativeVpn() async {}
Future<Map<String, num>> nativeTraffic() async => {};

Future<void> initializeNativeRuntime() async {}
List<String> get nativeLogs => const [];
Future<bool> restartAsAdministrator() async => false;
Future<bool> installCloseHandler(
  Future<void> Function() cleanup, {
  required Map<String, dynamic> Function() settings,
}) async => false;

Future<void> runNativeSelfTest(String output) async {}

Future<Map<String, String>> nativeSelect(String group, String server) async =>
    throw UnsupportedError('Windows only');
Future<int> nativeDelay(String server) async => -1;
Future<Map<String, String>> nativeIp() async => {};

Future<bool> readWindowsAutostart() async => false;
Future<void> setWindowsAutostart(bool enabled) async {}

Future<void> finishStartupSelfTest(
  String output,
  Map<String, dynamic> report,
) async {}

Future<void> dragWindow() async {}
Future<void> minimizeWindow() async {}
Future<void> toggleMaximizeWindow() async {}
Future<void> closeWindow() async {}

bool get nativeRuntimeAlive => false;
Future<void> replaceNativeProfile(
  Map<String, dynamic> profile,
  Map<String, dynamic> settings,
) async {}
Future<Map<String, int?>> nativeMeasureDelays(
  Map<String, dynamic> profile,
  Map<String, dynamic> settings,
  List<String> names, {
  bool useActiveCore = false,
  void Function(String, int?)? onResult,
}) async => {};
Future<void> cancelNativeDelays() async {}

Future<void> showWindow() async {}
Future<void> closeNativeConnections() async {}
Future<void> openReleaseUrl(String url) async {}
Future<Map<String, dynamic>> runWindowLifecycleSelfTest() async => {};

Future<void> configureAppPreferences(Map<String, dynamic> settings) async {}
void recordAppEvent(String event) {}
Future<void> flushNativeLogs() async {}
Future<void> clearNativeLogs() async {}

Future<void> runNativeVpnSelfTest(
  String output,
  List<Map<String, dynamic>> cases,
) async {}
