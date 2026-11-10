import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dix/model/controller.dart';
import 'package:dix/ui/dix_flag.dart';
import 'package:dix/ui/servers_panel.dart';

void main() {
  Future<void> render(WidgetTester tester, DixController model) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: DixServersPanel(controller: model, onAddSubscription: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'flags are clipped and ping actions are available while offline',
    (tester) async {
      final model = DixController.fixture();
      await render(tester, model);
      final bulk = tester.widget<IconButton>(
        find.byKey(const Key('test-all-delays')),
      );
      expect(bulk.onPressed, isNotNull);
      final pings = tester.widgetList<TextButton>(
        find.ancestor(of: find.text('Пинг'), matching: find.byType(TextButton)),
      );
      expect(pings, isNotEmpty);
      expect(pings.every((button) => button.onPressed != null), isTrue);
      final flags = find.byType(DixFlag);
      expect(flags, findsWidgets);
      final clips = tester.widgetList<ClipRRect>(
        find.descendant(of: flags, matching: find.byType(ClipRRect)),
      );
      expect(
        clips.any((clip) => clip.borderRadius == BorderRadius.circular(4)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets(
    'latency sort survives rebuilding and puts measured servers first',
    (tester) async {
      final model = DixController.fixture();
      model.patch({'serverSort': 'ping', 'serverGroup': 'none'});
      model.delays.addAll({
        model.servers[0].name: 130,
        model.servers[1].name: null,
        model.servers[2].name: 24,
      });
      await render(tester, model);
      final germanyY = tester.getTopLeft(find.text('Германия')).dy;
      final finlandY = tester.getTopLeft(find.text('Финляндия')).dy;
      final polandY = tester.getTopLeft(find.text('Польша')).dy;
      expect(germanyY, lessThan(finlandY));
      expect(finlandY, lessThan(polandY));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets('subscription picker browses another profile during connection', (
    tester,
  ) async {
    final model = DixController.fixture();
    model.archive.profiles['another'] = {
      'proxies': [
        {'name': 'Other location', 'type': 'vless'},
      ],
    };
    model.captureRunningArchive();
    model.connected = true;
    await render(tester, model);
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(dropdown.onChanged, isNotNull);
    dropdown.onChanged!('another');
    await tester.pump();
    expect(model.browsedProfileId, 'another');
    expect(model.archive.activeId, 'preview');
    expect(model.selected?.displayName, 'Финляндия');
    expect(find.text('Other location'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
