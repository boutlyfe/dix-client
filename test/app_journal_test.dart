import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dix/platform/app_journal.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dix-journal-test-');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('opt-in journal keeps events across disabled sessions', () async {
    final journal = AppJournal(directory);
    journal.record('ignored');
    await journal.flush();
    expect(await directory.list().isEmpty, isTrue);
    await journal.setEnabled(true);
    journal.record('application_started');
    await journal.setEnabled(false);
    journal.record('ignored again');
    await journal.flush();
    final reopened = AppJournal(directory);
    await reopened.setEnabled(true);
    expect(reopened.entries, hasLength(1));
    expect(reopened.entries.single, endsWith('application_started'));
  });

  test(
    'serialized events preserve order and enforce UTF-8 byte bounds',
    () async {
      final journal = AppJournal(directory, maxBytes: 220, maxEntries: 3);
      await journal.setEnabled(true);
      for (var i = 0; i < 20; i++) {
        journal.record('событие_$i');
      }
      await journal.flush();
      expect(journal.entries, hasLength(3));
      expect(journal.entries.first, endsWith('событие_17'));
      expect(journal.entries.last, endsWith('событие_19'));
      final file = directory.listSync().single as File;
      expect(await file.length(), lessThanOrEqualTo(220));
      final restored = AppJournal(directory, maxBytes: 100, maxEntries: 10);
      await restored.setEnabled(true);
      expect(restored.entries, isNotEmpty);
      expect(restored.entries.last, endsWith('событие_19'));
    },
  );

  test(
    'events cannot inject lines and clear is ordered with pending writes',
    () async {
      final journal = AppJournal(directory);
      await journal.setEnabled(true);
      journal.record('started\nforged\r\nentry\x00');
      await journal.flush();
      expect(journal.entries.single, endsWith('started forged  entry'));
      journal.record('pending');
      await journal.clear();
      expect(journal.entries, isEmpty);
      expect(await directory.list().isEmpty, isTrue);
      journal.record('after_clear');
      await journal.flush();
      expect(journal.entries.single, endsWith('after_clear'));
    },
  );

  test('failed disk writes do not crash runtime or poison the queue', () async {
    final blocker = File('${directory.path}/blocked');
    await blocker.writeAsString('file blocks directory creation');
    final journal = AppJournal(Directory(blocker.path));
    await journal.setEnabled(true);
    journal.record('first');
    await journal.flush();
    await blocker.delete();
    journal.record('recovered');
    await journal.flush();
    expect(journal.entries.last, endsWith('recovered'));
    expect(await File('${blocker.path}/dix-events.log').exists(), isTrue);
  });
}
