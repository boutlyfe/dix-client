import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// JSON-lines transport for the bundled Dix core. Owns only its child process.
class CoreRpc {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _pending = <String, Completer<dynamic>>{};
  ServerSocket? _server;
  Socket? _socket;
  Process? _process;
  Future<void>? _closing;
  Completer<void>? _connected;
  bool _closed = false;
  int _sequence = 0;
  String _buffer = '';
  static const _maxFrame = 16 * 1024 * 1024;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get isAlive => !_closed && _socket != null && _process != null;
  int? get pid => _process?.pid;
  String? homeDirectory;

  Future<void> start(
    String executable,
    String home, {
    List<String> argumentsBeforePort = const [],
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_closed || _connected != null) {
      throw StateError('Транспорт ядра уже использован');
    }
    homeDirectory = Directory(home).absolute.path;
    final connected = _connected = Completer<void>();
    // Attach the error listener before a child can exit during Process.start.
    final ready = connected.future.timeout(timeout);
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_accept, onError: _fail);
      final coreDir = File(executable).parent.path;
      _process = await Process.start(
        executable,
        [...argumentsBeforePort, '${_server!.port}'],
        workingDirectory: coreDir,
        environment: {...Platform.environment, 'SAFE_PATHS': '$home;$coreDir'},
        runInShell: false,
      );
      final child = _process!;
      if (_closed) {
        _process = null;
        child.kill();
        await child.exitCode;
        throw StateError('Запуск ядра отменён');
      }
      // Drain arbitrary process output without retaining credentials or logs.
      unawaited(child.stdout.drain<void>().catchError((Object _) {}));
      unawaited(child.stderr.drain<void>().catchError((Object _) {}));
      unawaited(
        child.exitCode.then((code) {
          if (_process == child) {
            _process = null;
            _fail(StateError('Ядро завершилось: $code'));
          }
        }),
      );
      await ready;
      if (!isAlive) throw StateError('Соединение с ядром потеряно');
    } catch (_) {
      // Also consume the startup future if spawning failed before awaiting it.
      if (!connected.isCompleted) connected.complete();
      await ready.catchError((Object _) {});
      await close();
      rethrow;
    }
  }

  void _accept(Socket client) {
    if (_socket != null || _closed) {
      client.destroy();
      return;
    }
    _socket = client;
    client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(
          _receive,
          onError: _fail,
          onDone: () => _fail(StateError('Соединение с ядром потеряно')),
        );
    if (!_connected!.isCompleted) _connected!.complete();
  }

  void _receive(String chunk) {
    _buffer += chunk;
    while (true) {
      final newline = _buffer.indexOf('\n');
      if (newline < 0) break;
      if (newline > _maxFrame) {
        _fail(const FormatException('Ответ ядра слишком велик'));
        return;
      }
      final line = _buffer.substring(0, newline).trim();
      _buffer = _buffer.substring(newline + 1);
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final message = Map<String, dynamic>.from(decoded);
        if (message['method'] == 'message') {
          if (!_events.isClosed) _events.add(message);
          continue;
        }
        final pending = _pending.remove(message['id']);
        if (pending == null) continue;
        if (message['code'] == -1) {
          pending.completeError(StateError(message['data'].toString()));
        } else {
          pending.complete(message['data']);
        }
      } on FormatException {
        // A malformed complete frame must not corrupt subsequent replies.
      }
    }
    if (_buffer.length > _maxFrame) {
      _fail(const FormatException('Ответ ядра слишком велик'));
    }
  }

  void _fail(Object error) {
    _socket?.destroy();
    _socket = null;
    _buffer = '';
    if (_connected != null && !_connected!.isCompleted) {
      _connected!.completeError(error);
    }
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pending.clear();
    if (!_closed) unawaited(close());
  }

  Future<dynamic> call(
    String method, [
    Object? data,
    Duration timeout = const Duration(seconds: 15),
  ]) async {
    if (_socket == null || _closed) throw StateError('Ядро не подключено');
    final id = '$method#${_sequence++}';
    final pending = Completer<dynamic>();
    _pending[id] = pending;
    try {
      _socket!.write(
        '${jsonEncode({'id': id, 'method': method, 'data': data})}\n',
      );
      return await pending.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('Таймаут $method', timeout),
      );
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    // Send shutdown before closing the transport; it can restore the core's TUN.
    try {
      if (_socket != null && !_closed) {
        await call('shutdown', null, const Duration(seconds: 2));
      }
    } catch (_) {}
    _closed = true;
    final child = _process;
    _process = null;
    _socket?.destroy();
    _socket = null;
    await _server?.close();
    _server = null;
    _fail(StateError('Ядро остановлено'));
    if (child != null) {
      try {
        await child.exitCode.timeout(const Duration(milliseconds: 600));
      } on TimeoutException {
        child.kill();
        await child.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () => -1,
        );
      }
    }
    await _events.close();
  }
}
