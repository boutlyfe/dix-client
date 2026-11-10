import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dix/main.dart';
import 'package:dix/model/controller.dart';
import 'package:dix/ui/globe.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  Future<void> prepare(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
    final icon = LucideIcons.power;
    final icons = FontLoader('packages/${icon.fontPackage}/${icon.fontFamily}')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
  }

  Future<void> render(WidgetTester tester, DixController model) async {
    await tester.pumpWidget(DixApp(controller: model));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 350)),
    );
    await tester.pump(const Duration(milliseconds: 150));
  }

  testWidgets(
    'desktop dashboard shows Dix cards and globe without games',
    (tester) async {
      await prepare(tester, const Size(1240, 820));
      final model = DixController.fixture();
      await render(tester, model);
      expect(find.byType(DixGlobe), findsOneWidget);
      expect(find.text('СКОРОСТЬ'), findsOneWidget);
      expect(find.text('ВАШ IP-АДРЕС'), findsOneWidget);
      expect(find.text('СЕРВЕР'), findsOneWidget);
      expect(find.textContaining('Спиннер'), findsNothing);
      expect(find.textContaining('Рулетка'), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(DixApp),
        matchesGoldenFile('goldens/minimal-desktop.png'),
      );
      await tester.tap(find.byKey(const Key('edit-home')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(DixApp),
        matchesGoldenFile('goldens/home-editor-desktop.png'),
      );
      final start = tester.getCenter(find.byKey(const Key('home-drag-ip')));
      final slot =
          tester.getTopLeft(find.byKey(const ValueKey('home-tile-server'))) +
          const Offset(4, -7);
      final drag = await tester.startGesture(start);
      await drag.moveTo(start + const Offset(0, 12));
      await tester.pump();
      await drag.moveTo(slot);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('home-drop-placeholder')), findsOneWidget);
      await expectLater(
        find.byType(DixApp),
        matchesGoldenFile('goldens/home-drag-preview-desktop.png'),
      );
      await drag.moveTo(const Offset(-20, -20));
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-drop-placeholder')), findsNothing);
      expect(model.settings['flutterHomeLayout'], isNull);

      await tester.tap(find.byKey(const Key('edit-home')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('server-search')), 'Польша');
      await tester.pump();
      expect(find.text('Германия'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Польша',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets(
    'iPhone width remains usable; Classic can be restored without losing rules',
    (tester) async {
      await prepare(tester, const Size(393, 852));
      final model = DixController.fixture();
      final rules = model.settings['advancedRules'];
      await render(tester, model);
      expect(find.byKey(const Key('connect')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(DixApp),
        matchesGoldenFile('goldens/minimal-iphone.png'),
      );
      model.patch({'appearance': 'classic'});
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(DixGlobe), findsNothing);
      expect(model.settings['advancedRules'], rules);
      model.patch({'appearance': 'minimal', 'theme': 'light'});
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
      await expectLater(
        find.byType(DixApp),
        matchesGoldenFile('goldens/minimal-iphone-light.png'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets('phone home customization and rule form persist user choices', (
    tester,
  ) async {
    await prepare(tester, const Size(393, 852));
    final model = DixController.fixture();
    await render(tester, model);
    await tester.tap(find.byKey(const Key('edit-home')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DixApp),
      matchesGoldenFile('goldens/home-editor-iphone.png'),
    );
    await tester.tap(find.byKey(const Key('home-remove-server')));
    await tester.pumpAndSettle();
    expect(model.settings['flutterHomeLayout'], isNull);
    await tester.tap(find.byKey(const Key('edit-home')));
    await tester.pumpAndSettle();
    expect(find.text('СЕРВЕР'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-remove-server')));
    await tester.tap(find.byKey(const Key('save-home')));
    await tester.pumpAndSettle();
    expect(find.text('СЕРВЕР'), findsNothing);
    expect(model.settings['flutterHomeLayout']['hidden'], contains('server'));
    await tester.tap(find.text('Правила').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-rule')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DixApp),
      matchesGoldenFile('goldens/rule-editor-iphone.png'),
    );
    await tester.enterText(find.byKey(const Key('rule-value')), 'example.com');
    await tester.tap(find.byKey(const Key('save-rule')));
    await tester.pumpAndSettle();
    expect(
      model.settings['advancedRules']['text'],
      contains('DOMAIN-SUFFIX,example.com,'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  testWidgets('Windows settings and subscription actions remain usable', (
    tester,
  ) async {
    await prepare(tester, const Size(1240, 820));
    final model = DixController.fixture();
    await render(tester, model);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-network')));
    await tester.pumpAndSettle();
    expect(find.text('Подключение и DNS'), findsOneWidget);
    expect(find.text('Тайм-аут пинга'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-updates')));
    await tester.pumpAndSettle();
    expect(find.text('Dix 0.2.3'), findsOneWidget);
    expect(find.text('boutlyfe/dix-client'), findsOneWidget);
    expect(find.textContaining('отдельное хранилище'), findsNothing);
    await expectLater(
      find.byType(DixApp),
      matchesGoldenFile('goldens/updates-desktop.png'),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Подписки'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Действия с профилем'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Переименовать'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Моя подписка');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(model.archive.subscriptions.single['name'], 'Моя подписка');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
  testWidgets(
    'rounded notices hide technical prefixes and custom window controls render',
    (tester) async {
      await prepare(tester, const Size(1240, 820));
      final model = DixController.fixture();
      model.message =
          'Bad state: Для режима TUN запустите Dix от имени администратора.';
      await render(tester, model);
      expect(find.textContaining('Bad state:'), findsNothing);
      expect(find.text('Для TUN нужны права администратора'), findsOneWidget);
      expect(find.byTooltip('Свернуть'), findsOneWidget);
      expect(find.byTooltip('Закрыть Dix'), findsOneWidget);
      await expectLater(
        find.byType(DixApp),
        matchesGoldenFile('goldens/notice-desktop.png'),
      );
      await tester.tap(find.byTooltip('Закрыть уведомление'));
      await tester.pumpAndSettle();
      expect(model.message, isNull);
      await tester.tap(find.byTooltip('Правила'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(DixApp),
        matchesGoldenFile('goldens/rules-desktop.png'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
