import 'package:dix/model/controller.dart';
import 'package:dix/ui/connection_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DNS editor validates before saving legacy keys', (tester) async {
    final model = DixController.fixture();
    model.patch({
      'dnsMode': 'custom',
      'dnsCustom': ['https://1.1.1.1/dns-query'],
      'futureSetting': {'preserve': true},
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConnectionSettingsPanel(controller: model),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Свои DNS-серверы'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'http://insecure.example/dns',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    expect(find.textContaining('Проверьте адрес:'), findsOneWidget);
    expect(model.settings['dnsCustom'], ['https://1.1.1.1/dns-query']);
    await tester.enterText(
      find.byType(TextField),
      'https://dns.google/dns-query\nudp://1.2.3.4, https://dns.google/dns-query',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(model.settings['dnsCustom'], [
      'https://dns.google/dns-query',
      'udp://1.2.3.4',
    ]);
    expect(model.settings['futureSetting'], {'preserve': true});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets('unknown imported enum values stay visible and unchanged', (
    tester,
  ) async {
    final model = DixController.fixture();
    model.patch({'dnsMode': 'future-resolver', 'netMode': 'future-mode'});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConnectionSettingsPanel(controller: model),
          ),
        ),
      ),
    );
    expect(
      find.text('Из перенесённых настроек: future-resolver'),
      findsOneWidget,
    );
    expect(model.settings['dnsMode'], 'future-resolver');
    expect(model.settings['netMode'], 'future-mode');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
