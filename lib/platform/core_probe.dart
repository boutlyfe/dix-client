import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'core_rpc.dart';
import 'core_session.dart';
import 'core_selection.dart';

/// No external endpoints, TUN, DNS server, registry or user profiles are touched.
Future<Map<String, dynamic>> probeCore(
  String executable,
  String directory, {
  Future<void> Function(int pid)? supervise,
}) async {
  final rpc = CoreRpc();
  final home = Directory(directory).absolute;
  await home.create(recursive: true);
  final sockets = <Socket>{};
  var received = 0, outboundConnections = 0;
  final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  target.listen((request) {
    received++;
    if (request.uri.path == '/hold') {
      request.response.write('held');
      unawaited(request.response.flush());
      return;
    }
    request.response.write('dix-core-ok');
    unawaited(request.response.close());
  });
  final outbound = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  outbound.listen((socket) {
    sockets.add(socket);
    var header = <int>[], ready = false;
    Socket? upstream;
    late StreamSubscription<List<int>> sub;
    sub = socket.listen(
      (bytes) async {
        if (ready) {
          upstream?.add(bytes);
          return;
        }
        header.addAll(bytes);
        final text = latin1.decode(header);
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        sub.pause();
        if (!text.startsWith('CONNECT 127.0.0.1:${target.port} ')) {
          socket.destroy();
          return;
        }
        try {
          upstream = await Socket.connect('127.0.0.1', target.port);
          sockets.add(upstream!);
          outboundConnections++;
          socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
          ready = true;
          if (header.length > end + 4) upstream!.add(header.sublist(end + 4));
          header = [];
          upstream!.listen(
            socket.add,
            onDone: socket.destroy,
            onError: (Object _) => socket.destroy(),
          );
          sub.resume();
        } catch (_) {
          socket.destroy();
        }
      },
      onDone: () => upstream?.destroy(),
      onError: (Object _) => upstream?.destroy(),
    );
  });
  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = reservation.port;
  await reservation.close();
  Future<String> request() async {
    final client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$port';
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${target.port}/'),
      );
      request.persistentConnection = false;
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  final result = <String, dynamic>{
    'scope':
        'isolated loopback HTTP only; TUN disabled; system proxy unchanged',
  };
  try {
    await rpc.start(File(executable).absolute.path, home.path);
    if (supervise != null) {
      await supervise(rpc.pid!);
      result['windowsJobAttached'] = true;
    }
    result['initialized'] = await rpc.call(
      'initClash',
      jsonEncode({'home-dir': home.path, 'version': 20}),
    );
    var invalidRuleRejected = false;
    try {
      await applyCoreProfile(rpc, {
        'mixed-port': port,
        'mode': 'rule',
        'tun': {'enable': false},
        'proxies': [],
        'proxy-groups': [],
        'rule': ['DOMAIN,example.com,MissingTarget', 'MATCH,DIRECT'],
      }, tun: false);
    } on FormatException {
      invalidRuleRejected = true;
    }
    if (!invalidRuleRejected) {
      throw StateError('Invalid rule target was accepted');
    }
    result['invalidRuleRejected'] = true;
    await applyCoreProfile(
      rpc,
      {
        'mixed-port': port,
        'mode': 'rule',
        'log-level': 'silent',
        'dns': {'enable': false},
        'tun': {'enable': false},
        'proxies': [
          {
            'name': 'Local tunnel',
            'type': 'http',
            'server': '127.0.0.1',
            'port': outbound.port,
          },
          {
            'name': 'Local tunnel 2',
            'type': 'http',
            'server': '127.0.0.1',
            'port': outbound.port,
          },
        ],
        'proxy-groups': [
          {
            'name': 'Test route',
            'type': 'select',
            'proxies': ['Local tunnel', 'Local tunnel 2', 'DIRECT', 'REJECT'],
          },
        ],
        'rule': ['MATCH,Test route'],
      },
      tun: false,
      selected: {'Test route': 'Local tunnel'},
    );
    result['configurationApplied'] = true;
    if (await request() != 'dix-core-ok' || outboundConnections == 0) {
      throw StateError('Selected proxy route did not reach loopback fixture');
    }
    result['selectedProxyRouted'] = true;
    await selectRuntimeServer(
      (method, data) => rpc.call(method, data),
      preferredGroup: 'Imported group no longer exists',
      rootGroup: 'Test route',
      server: 'Local tunnel 2',
    );
    if (await request() != 'dix-core-ok') {
      throw StateError('Runtime server switch failed');
    }
    result['runtimeGroupSwitchVerified'] = true;
    final connectionsBefore = outboundConnections;
    final directResult = await rpc.call(
      'changeProxy',
      jsonEncode({'group-name': 'Test route', 'proxy-name': 'DIRECT'}),
    );
    result['changeProxyReply'] = directResult;
    if (await request() != 'dix-core-ok' ||
        outboundConnections != connectionsBefore) {
      throw StateError('DIRECT route did not bypass the selected proxy');
    }
    result['directRouted'] = true;
    final requestsBefore = received;
    await rpc.call(
      'changeProxy',
      jsonEncode({'group-name': 'Test route', 'proxy-name': 'REJECT'}),
    );
    var blocked = false;
    try {
      blocked = await request() != 'dix-core-ok';
    } catch (_) {
      blocked = true;
    }
    if (!blocked || received != requestsBefore) {
      throw StateError('REJECT failed to block request');
    }
    result['rejectBlocked'] = true;
    final traffic = await rpc.call('getTraffic');
    result['trafficReadable'] =
        (traffic is String ? jsonDecode(traffic) : traffic) is Map;
    await rpc.call(
      'changeProxy',
      jsonEncode({'group-name': 'Test route', 'proxy-name': 'Local tunnel'}),
    );
    final heldClient = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$port';
    try {
      final held = await (await heldClient.getUrl(
        Uri.parse('http://127.0.0.1:${target.port}/hold'),
      )).close().timeout(const Duration(seconds: 4));
      final dropped = Completer<void>();
      held.listen(
        (_) {},
        onDone: () {
          if (!dropped.isCompleted) dropped.complete();
        },
        onError: (Object _) {
          if (!dropped.isCompleted) dropped.complete();
        },
      );
      dynamic connections = await rpc.call('getConnections', null);
      if (connections is String) connections = jsonDecode(connections);
      if (connections is! Map ||
          (connections['connections'] as List? ?? []).isEmpty) {
        throw StateError('Held connection missing');
      }
      await rpc.call('closeConnections', null);
      await dropped.future.timeout(const Duration(seconds: 4));
      result['closeConnectionsVerified'] = true;
    } finally {
      heldClient.close(force: true);
    }
  } finally {
    for (final method in ['stopTun', 'stopListener']) {
      try {
        await rpc.call(method, null, const Duration(seconds: 2));
      } catch (_) {
        /* Already stopped. */
      }
    }
    await rpc.close();
    await target.close(force: true);
    await outbound.close();
    for (final socket in sockets) {
      socket.destroy();
    }
  }
  result['closed'] = !rpc.isAlive;
  return result;
}
