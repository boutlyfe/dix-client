import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dix/model/controller.dart';
import 'package:dix/ui/app_settings.dart';

void main() {
  testWidgets(
    'application options persist independently and journal can be opened',
    (tester) async {
      final model = DixController.fixture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppSettingsControls(controller: model),
            ),
          ),
        ),
      );
      for (final key in [
        'flutterMinimizeToTray',
        'flutterStartHidden',
        'flutterAutoConnect',
        'flutterCloseConnections',
        'flutterLogging',
      ]) {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        final tile = tester.widget<SwitchListTile>(finder);
        final before = tile.value;
        tile.onChanged!(!before);
        await tester.pump();
        expect(model.settings[key], !before);
      }
      await tester.ensureVisible(find.text('Открыть журнал'));
      await tester.tap(find.text('Открыть журнал'));
      await tester.pumpAndSettle();
      expect(find.text('Журнал Dix'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
