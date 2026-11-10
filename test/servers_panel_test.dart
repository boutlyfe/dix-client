import 'package:dix/model/controller.dart';
import 'package:dix/ui/servers_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showPanel(WidgetTester tester, DixController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 286,
              child: DixServersPanel(
                controller: controller,
                docked: true,
                onAddSubscription: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'server search, favorites and selection rebuild in an isolated panel',
    (tester) async {
      final model = DixController.fixture();
      await showPanel(tester, model);
      await tester.enterText(find.byKey(const Key('server-search')), 'Польша');
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Польша'),
        findsOneWidget,
      );
      expect(find.text('Германия'), findsNothing);
      await tester.tap(find.byTooltip('В избранное'));
      await tester.pumpAndSettle();
      expect(model.settings['favorites'], ['🇵🇱 Польша']);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Польша'),
      );
      await tester.pumpAndSettle();
      expect(model.selected?.name, '🇵🇱 Польша');
      expect(find.text('VLESS · Выбран'), findsOneWidget);
      await tester.tap(find.byTooltip('Очистить поиск'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Польша'),
        findsOneWidget,
      );
      expect(find.text('Финляндия'), findsNothing);
      await tester.tap(find.byTooltip('Убрать из избранного'));
      await tester.pumpAndSettle();
      expect(find.text('Избранных серверов пока нет'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets('profile picker selects a server and preserves legacy data', (
    tester,
  ) async {
    final model = DixController.fixture();
    model.archive.profiles['second'] = {
      'proxies': [
        {'name': '🇯🇵 Токио', 'type': 'trojan'},
      ],
      'proxy-groups': [
        {
          'name': 'Second',
          'proxies': ['🇯🇵 Токио'],
        },
      ],
    };
    model.settings['subs'] = [
      {'id': 'second', 'name': 'Рабочая подписка'},
    ];
    model.settings['keepUnknown'] = {'nested': 42};
    await showPanel(tester, model);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Рабочая подписка').last);
    await tester.pumpAndSettle();
    expect(model.archive.activeId, 'second');
    expect(model.selected?.name, '🇯🇵 Токио');
    expect(model.settings['keepUnknown'], {'nested': 42});
    expect(model.settings['selected']['Second'], '🇯🇵 Токио');
    expect(find.text('Токио'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
