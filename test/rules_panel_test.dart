import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dix/model/controller.dart';
import 'package:dix/model/archive.dart';
import 'package:dix/ui/rules_panel.dart';

void main() {
  testWidgets(
    'phone form creates a rule, reports invalid domain and preserves metadata',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = DixController.fixture();
      model.patch({
        'advancedRules': {
          ...jsonMap(model.settings['advancedRules']),
          'futureKey': 42,
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: RulesPanel(controller: model),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('add-rule')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('rule-value')),
        'https://example.com',
      );
      await tester.tap(find.byKey(const Key('save-rule')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Введите домен без адреса страницы'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('rule-value')),
        'example.com',
      );
      await tester.tap(find.byKey(const Key('save-rule')));
      await tester.pumpAndSettle();
      final advanced = jsonMap(model.settings['advancedRules']);
      expect(advanced['text'], contains('DOMAIN-SUFFIX,example.com,DIRECT'));
      expect(advanced['futureKey'], 42);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
