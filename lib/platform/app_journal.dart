import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Persists only application events already sanitized by the caller.
/// Never pass configuration, subscription URLs, core output or raw exceptions.
class AppJournal {
  AppJournal(this.directory, {this.maxBytes = 262144, this.maxEntries = 200})
    : assert(maxBytes > 0),
      assert(maxEntries > 0);

  final Directory directory;
  final int maxBytes, maxEntries;
  final List<String> _entries = [];
  Future<void> _pending = Future.value();
  bool _enabled = false;

  File get _file => File('${directory.path}/dix-events.log');
  List<String> get entries => List.unmodifiable(_entries);

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    // An unavailable disk must not poison subsequent writes or the app runtime.
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> setEnabled(bool enabled) => _enqueue(() async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) return;
    try {
      if (!await _file.exists()) return;
      final input = await _file.open();
      try {
        final size = await input.length();
        final start = size > maxBytes ? size - maxBytes : 0;
        await input.setPosition(start);
        var content = utf8.decode(
          await input.read(maxBytes),
          allowMalformed: true,
        );
        if (start > 0) {
          final newline = content.indexOf('\n');
          content = newline < 0 ? '' : content.substring(newline + 1);
        }
        _entries
          ..clear()
          ..addAll(
            const LineSplitter().convert(content).where((s) => s.isNotEmpty),
          );
        _bound();
      } finally {
        await input.close();
      }
    } on FileSystemException {
      // Logging is optional; the next event may retry after disk recovery.
    }
  });

  void record(String sanitizedEvent) {
    if (!_enabled) return;
    final event = sanitizedEvent
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .trim();
    if (event.isEmpty) return;
    final boundedEvent = String.fromCharCodes(event.runes.take(1024));
    final line = '${DateTime.now().toUtc().toIso8601String()} $boundedEvent';
    unawaited(
      _enqueue(() async {
        _entries.add(line);
        _bound();
        await directory.create(recursive: true);
        await _file.writeAsString(_content, flush: true);
      }).catchError((Object _) {}),
    );
  }

  String get _content => _entries.isEmpty ? '' : '${_entries.join('\n')}\n';

  void _bound() {
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    while (_entries.isNotEmpty && utf8.encode(_content).length > maxBytes) {
      _entries.removeAt(0);
    }
  }

  Future<void> flush() => _pending;

  Future<void> clear() => _enqueue(() async {
    if (await _file.exists()) await _file.delete();
    _entries.clear();
  });
}
