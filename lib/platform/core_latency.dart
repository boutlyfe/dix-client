import 'dart:convert';
import 'core_selection.dart';

const latencyEndpoints = [
  'https://www.gstatic.com/generate_204',
  'https://cp.cloudflare.com/generate_204',
];

/// Measures application traffic through the named proxy; TCP reachability alone
/// must never appear as a successful VPN latency result.
Future<int?> measureProxyLatency(
  SelectionRpc call,
  String name, {
  int timeoutMs = 10000,
  bool Function()? cancelled,
}) async {
  for (final endpoint in latencyEndpoints) {
    if (cancelled?.call() == true) return null;
    try {
      dynamic reply = await call(
        'asyncTestDelay',
        jsonEncode({
          'proxy-name': name,
          'test-url': endpoint,
          'timeout': timeoutMs,
        }),
      );
      if (reply is String) reply = jsonDecode(reply);
      final raw = reply is Map ? reply['value'] : null;
      final value = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (value != null && value > 0) return value;
    } catch (_) {
      // A blocked probe endpoint is retried against an independent endpoint.
    }
  }
  return null;
}
