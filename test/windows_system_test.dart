import 'dart:convert';
import 'dart:io';

import 'package:dix/platform/windows_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late _FakeWindows windows;
  late WindowsProxyLease lease;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dix-proxy-test-');
    windows = _FakeWindows();
    lease = WindowsProxyLease(directory: directory, command: windows.call);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('restores exact snapshot including absent registry values', () async {
    final original = jsonEncode(windows.values);
    await lease.enable(17897);
    expect(windows.values, WindowsProxyLease.proxyValues(17897));
    expect(windows.actions, ['read', 'apply', 'watch']);
    expect(
      await File('${directory.path}/windows-proxy-lease.json').exists(),
      true,
    );
    await lease.restore();
    expect(jsonEncode(windows.values), original);
    expect(await directory.list().isEmpty, true);
  });

  test(
    'does not overwrite another application proxy after connecting',
    () async {
      await lease.enable(17897);
      windows.values = WindowsProxyLease.proxyValues(9999);
      await lease.restore();
      expect(windows.values, WindowsProxyLease.proxyValues(9999));
    },
  );

  test(
    'startup recovery requires dead owner and respects other apps',
    () async {
      final original = jsonEncode(windows.values);
      await lease.enable(17897);
      final recovered = WindowsProxyLease(
        directory: directory,
        command: windows.call,
      );
      windows.ownerAlive = true;
      await expectLater(recovered.recoverAbandoned(), throwsStateError);
      expect(windows.values, WindowsProxyLease.proxyValues(17897));
      windows.ownerAlive = false;
      expect(await recovered.recoverAbandoned(), true);
      expect(jsonEncode(windows.values), original);
      expect(await recovered.recoverAbandoned(), false);
    },
  );

  test('watcher launch failure rolls back before reporting failure', () async {
    final original = jsonEncode(windows.values);
    windows.failWatcher = true;
    await expectLater(lease.enable(17897), throwsStateError);
    expect(jsonEncode(windows.values), original);
    expect(await directory.list().isEmpty, true);
  });

  test('invalid ports never reach the system boundary', () async {
    await expectLater(lease.enable(0), throwsRangeError);
    await expectLater(lease.enable(65536), throwsRangeError);
    expect(windows.actions, isEmpty);
  });
}

class _FakeWindows {
  Map<String, dynamic> values = {
    'ProxyEnable': {'exists': true, 'kind': 'DWord', 'value': 0},
    'ProxyServer': {'exists': false},
    'ProxyOverride': {'exists': true, 'kind': 'String', 'value': 'custom'},
  };
  final actions = <String>[];
  bool ownerAlive = false;
  bool failWatcher = false;

  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
    final action = request['action'] as String;
    actions.add(action);
    switch (action) {
      case 'read':
        return {'values': values, 'ownerStart': '123456'};
      case 'apply':
        values = Map<String, dynamic>.from(request['expected'] as Map);
        return {'applied': true};
      case 'watch':
        if (failWatcher) throw StateError('watch helper failed');
        return {'watching': true};
      case 'restore':
        if (request['requireDeadOwner'] == true && ownerAlive) {
          return {'restored': false, 'ownerAlive': true};
        }
        if (jsonEncode(values) == jsonEncode(request['expected'])) {
          values = Map<String, dynamic>.from(request['previous'] as Map);
          return {'restored': true, 'ownerAlive': false};
        }
        return {'restored': false, 'ownerAlive': false};
      default:
        throw StateError('Unexpected fake Windows operation: $action');
    }
  }
}
