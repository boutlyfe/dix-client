import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dix/model/home_layout.dart';
import 'package:dix/ui/home_canvas.dart';

void main() {
  testWidgets(
    'dashboard cards drag, resize, remove and add directly on canvas',
    (tester) async {
      final layout = HomeLayout.read({});
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: HomeCanvas(
                        layout: layout,
                        editing: true,
                        onChanged: () => update(() {}),
                        children: {
                          for (final id in homeLabels.keys)
                            id: SizedBox(
                              height: 45,
                              child: Text(homeLabels[id]!),
                            ),
                        },
                      ),
                    ),
                  ),
                  HomeEditBar(
                    layout: layout,
                    onChanged: () => update(() {}),
                    onReset: () {},
                    onCancel: () {},
                    onDone: () => saved = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final server = find.byKey(const ValueKey('home-tile-server'));
      final originalWidth = tester.getSize(server).width;
      await tester.tap(find.byKey(const Key('home-resize-server')));
      await tester.pumpAndSettle();
      expect(tester.getSize(server).width, greaterThan(originalWidth));
      await tester.tap(find.byKey(const Key('home-resize-server')));
      await tester.pumpAndSettle();
      final from = tester.getCenter(find.byKey(const Key('home-drag-mode')));
      final to = tester.getTopLeft(server) + const Offset(3, -7);
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(from + const Offset(0, 12));
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('home-drop-placeholder')), findsOneWidget);
      expect(
        layout.order.indexOf('server'),
        lessThan(layout.order.indexOf('mode')),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        layout.order.indexOf('mode'),
        lessThan(layout.order.indexOf('server')),
      );
      await tester.tap(find.byKey(const Key('home-remove-server')));
      await tester.pumpAndSettle();
      expect(server, findsNothing);
      await tester.tap(find.text('Добавить блок'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(homeLabels['server']!));
      await tester.pumpAndSettle();
      expect(server, findsOneWidget);
      expect(find.byKey(const Key('home-remove-connection')), findsNothing);
      await tester.tap(find.byKey(const Key('save-home')));
      expect(saved, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
