import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'model/controller.dart';
import 'model/archive.dart';
import 'model/rules.dart';
import 'platform/platform.dart' as platform;
import 'ui/shell.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.length == 2 && arguments.first == '--self-test-core') {
    await platform.runNativeSelfTest(arguments.last);
    return;
  }
  if (arguments.length == 2 && arguments.first == '--self-test-vpn') {
    final controller = await DixController.load();
    final cases = <Map<String, dynamic>>[];
    for (final protocol in ['vless', 'hysteria2']) {
      final selected = controller.selected;
      final server = selected?.type == protocol
          ? selected
          : controller.servers
                .where((server) => server.type == protocol)
                .firstOrNull;
      if (server == null) continue;
      final archive = controller.archive.clone();
      archive.settings['currentServer'] = server.name;
      archive.settings['netMode'] = 'tun';
      cases.add({
        'protocol': protocol,
        'server': server.name,
        'profile': configuredProfile(archive, selected: server.name),
        'settings': archive.settings,
      });
    }
    await platform.runNativeVpnSelfTest(arguments.last, cases);
    return;
  }
  const preview = bool.fromEnvironment('DIX_PREVIEW');
  DixController controller;
  try {
    controller = preview ? DixController.fixture() : await DixController.load();
  } catch (e) {
    controller = DixController(DixArchive.empty())
      ..message = 'Не удалось прочитать данные: $e';
  }
  final isolated =
      arguments.isNotEmpty && arguments.first.startsWith('--self-test-');
  if (!preview && !isolated) {
    try {
      await platform.initializeNativeRuntime();
      await controller.loadWindowsFeatures();
      await platform.configureAppPreferences(controller.settings);
      platform.recordAppEvent('Приложение запущено');
    } catch (error) {
      controller.message = 'Проверьте восстановление системного прокси: $error';
    }
  }
  final trayReady =
      !preview &&
      await platform.installCloseHandler(
        controller.shutdown,
        settings: () => isolated
            ? {...controller.settings, 'flutterMinimizeToTray': true}
            : controller.settings,
      );
  final hidden =
      (isolated && arguments.first == '--self-test-lifecycle') ||
      !preview &&
          !isolated &&
          trayReady &&
          controller.message == null &&
          controller.settings['flutterStartHidden'] == true;
  await platform.prepareWindow(hidden: hidden);
  if (!isolated) controller.startBackgroundTasks();
  runApp(DixApp(controller: controller));
  if (!isolated) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(controller.applyStartupPreferences());
    });
  }
  if (arguments.length == 2 && arguments.first == '--self-test-lifecycle') {
    await WidgetsBinding.instance.endOfFrame;
    final result = await platform.runWindowLifecycleSelfTest();
    await platform.finishStartupSelfTest(arguments.last, {
      ...result,
      'connected': controller.connected,
      'startupError': result.values.every((value) => value == true)
          ? null
          : 'Window lifecycle test failed',
    });
  }
  if (arguments.length == 2 && arguments.first == '--self-test-delay') {
    await WidgetsBinding.instance.endOfFrame;
    final names = controller.browsingServers.take(2).toList();
    await controller.testDelays(names);
    await platform.finishStartupSelfTest(arguments.last, {
      'offlineDelayTest': true,
      'count': controller.delays.length,
      'delays': controller.delays.values.toList(),
      'connected': controller.connected,
      'startupError': controller.message,
    });
  }
  if (arguments.length == 2 && arguments.first == '--self-test-startup') {
    await WidgetsBinding.instance.endOfFrame;
    await platform.finishStartupSelfTest(arguments.last, {
      'firstFrameRendered': true,
      'servers': controller.servers.length,
      'profileLoaded': controller.selected != null,
      'connected': controller.connected,
      'startupError': controller.message,
    });
  }
}

class DixApp extends StatelessWidget {
  final DixController controller;
  const DixApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final light = controller.archive.light,
          classic = controller.archive.appearance == 'classic';
      final bg = light ? const Color(0xfffafafa) : const Color(0xff0a0a0a);
      final ink = light ? const Color(0xff171717) : const Color(0xfffafafa);
      final accent = classic ? const Color(0xff3df0e6) : ink;
      final scheme =
          ColorScheme.fromSeed(
            seedColor: accent,
            brightness: light ? Brightness.light : Brightness.dark,
          ).copyWith(
            surface: bg,
            primary: accent,
            onPrimary: classic ? const Color(0xff04222b) : bg,
            onSurface: ink,
            onSurfaceVariant: ink.withValues(alpha: .56),
            secondary: ink,
            onSecondary: bg,
            secondaryContainer: light
                ? const Color(0xffe8e8e8)
                : const Color(0xff292929),
            onSecondaryContainer: ink,
            surfaceTint: Colors.transparent,
            outline: light ? const Color(0xffdedede) : const Color(0xff303030),
          );
      return MaterialApp(
        title: 'Dix',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: bg,
          fontFamily: 'Inter',
          visualDensity: VisualDensity.compact,
          dividerColor: scheme.outline,
          listTileTheme: ListTileThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: light ? Colors.white : const Color(0xff202020),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            surfaceTintColor: Colors.transparent,
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: light ? Colors.white : const Color(0xff252525),
            contentTextStyle: TextStyle(color: ink, fontSize: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: bg,
            indicatorColor: scheme.secondaryContainer,
            labelTextStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 10),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: light ? Colors.white : const Color(0xff171717),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: bg,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: light ? Colors.white : const Color(0xff141414),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: scheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: scheme.outline),
            ),
          ),
          textTheme: TextTheme(
            bodyMedium: TextStyle(color: ink, fontSize: 13),
            bodySmall: TextStyle(
              color: ink.withValues(alpha: .55),
              fontSize: 11,
            ),
          ),
        ),
        home: DixShell(controller: controller),
      );
    },
  );
}
