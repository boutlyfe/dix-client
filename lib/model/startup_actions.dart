class StartupActions {
  bool _applied = false;
  Future<void> run(
    Map<String, dynamic> settings, {
    required Future<void> Function() connect,
    required Future<void> Function() checkUpdates,
    bool isolated = false,
    bool preview = false,
  }) async {
    if (_applied || isolated || preview) return;
    _applied = true;
    if (settings['flutterAutoConnect'] == true) await connect();
    if (settings['flutterCheckUpdates'] != false) await checkUpdates();
  }
}
