import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Injectable boundary: tests never need to read or modify the user's proxy.
typedef WindowsSystemCommand =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class WindowsSystem {
  static Future<bool> isAdministrator() async {
    if (!Platform.isWindows) return false;
    return (await command({'action': 'admin'}))['administrator'] == true;
  }

  /// The caller should close its window only after this returns true. UAC
  /// cancellation is reported as an error and leaves the current app running.
  static Future<bool> relaunchElevated() async {
    if (!Platform.isWindows) return false;
    final executable = Platform.resolvedExecutable;
    final result = await command({
      'action': 'elevate',
      'executable': executable,
      'directory': File(executable).parent.path,
    });
    return result['started'] == true;
  }

  static Future<Map<String, dynamic>> command(
    Map<String, dynamic> request,
  ) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows system settings are unavailable');
    }
    // The command text is constant. Paths, saved registry values and ports are
    // data on stdin, never interpolated into PowerShell source.
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final watcher = request['action'] == 'watch';
    final process = await Process.start(
      '$root/System32/WindowsPowerShell/v1.0/powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        _script,
      ],
      runInShell: false,
      mode: watcher
          ? ProcessStartMode.detachedWithStdio
          : ProcessStartMode.normal,
    );
    if (watcher) {
      final ready = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      unawaited(process.stderr.drain<void>());
      process.stdin.write(jsonEncode(request));
      await process.stdin.close();
      final response = await ready.timeout(const Duration(seconds: 10));
      return Map<String, dynamic>.from(jsonDecode(response) as Map);
    }
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(jsonEncode(request));
    await process.stdin.close();
    final int code;
    try {
      code = await process.exitCode.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      process.kill();
      rethrow;
    }
    final stdout = await output;
    final stderr = await errors;
    if (code != 0) {
      throw StateError(
        'Не удалось изменить системные настройки Windows: '
        '${stderr.trim()}',
      );
    }
    final result = jsonDecode(stdout.trim());
    if (result is! Map) throw const FormatException('Invalid Windows response');
    return Map<String, dynamic>.from(result);
  }
}

/// Owns only the three WinINET values that Dix writes. It restores their exact
/// previous contents only while all current values still match its lease.
/// WPAD/PAC and other registry values are deliberately preserved.
class WindowsProxyLease {
  WindowsProxyLease({
    required Directory directory,
    WindowsSystemCommand? command,
  }) : _journal = File('${directory.path}/windows-proxy-lease.json'),
       _command = command ?? WindowsSystem.command;

  final File _journal;
  final WindowsSystemCommand _command;
  Future<void> _queue = Future<void>.value();
  bool _owned = false;

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Run before starting a new core. Never recovers another running process's
  /// lease and never changes values another application replaced after a crash.
  Future<bool> recoverAbandoned() => _exclusive(() async {
    if (!await _journal.exists()) return false;
    final journal = await _readJournal();
    final result = await _command({
      'action': 'restore',
      'previous': journal['previous'],
      'expected': journal['expected'],
      'ownerPid': journal['ownerPid'],
      'ownerStart': journal['ownerStart'],
      'requireDeadOwner': true,
    });
    if (result['ownerAlive'] == true) {
      throw StateError('Другой экземпляр Dix использует системный прокси');
    }
    await _journal.delete();
    return result['restored'] == true;
  });

  Future<void> enable(int mixedPort) => _exclusive(() async {
    if (mixedPort < 1 || mixedPort > 65535) {
      throw RangeError.range(mixedPort, 1, 65535, 'mixedPort');
    }
    if (_owned || await _journal.exists()) {
      throw StateError('Сначала завершите прежний сеанс системного прокси');
    }
    final snapshot = await _command({'action': 'read', 'ownerPid': pid});
    final previous = snapshot['values'];
    final expected = proxyValues(mixedPort);
    final ownerStart = snapshot['ownerStart'];
    final leaseId = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    await _journal.parent.create(recursive: true);
    // Flush the recovery record before touching the registry. Exclusive create
    // prevents a second instance replacing an existing lease.
    await _journal.create(exclusive: true);
    await _journal.writeAsString(
      jsonEncode({
        'version': 1,
        'ownerPid': pid,
        'ownerStart': ownerStart,
        'leaseId': leaseId,
        'previous': previous,
        'expected': expected,
      }),
      flush: true,
    );
    try {
      await _command({
        'action': 'apply',
        'previous': previous,
        'expected': expected,
      });
      _owned = true;
      await _command({
        'action': 'watch',
        'journal': _journal.absolute.path,
        'leaseId': leaseId,
        'ownerPid': pid,
        'ownerStart': ownerStart,
      });
    } catch (_) {
      // A helper timeout may happen after the registry changed. Keep a journal
      // if rollback itself fails so startup recovery still has its snapshot.
      try {
        await _command({
          'action': 'restore',
          'previous': previous,
          'expected': expected,
          'requireDeadOwner': false,
        });
        await _journal.delete();
        _owned = false;
      } catch (_) {}
      rethrow;
    }
  });

  Future<void> restore() => _exclusive(() async {
    if (!_owned) return;
    final journal = await _readJournal();
    await _command({
      'action': 'restore',
      'previous': journal['previous'],
      'expected': journal['expected'],
      'requireDeadOwner': false,
    });
    await _journal.delete();
    _owned = false;
  });

  Future<Map<String, dynamic>> _readJournal() async {
    final decoded = jsonDecode(await _journal.readAsString());
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['ownerPid'] is! int ||
        decoded['ownerStart'] is! String ||
        decoded['leaseId'] is! String ||
        decoded['previous'] is! Map ||
        decoded['expected'] is! Map) {
      throw const FormatException('Повреждён журнал системного прокси Dix');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Map<String, dynamic> proxyValues(int mixedPort) => {
    'ProxyEnable': {'exists': true, 'kind': 'DWord', 'value': 1},
    'ProxyServer': {
      'exists': true,
      'kind': 'String',
      'value': '127.0.0.1:$mixedPort',
    },
    'ProxyOverride': {
      'exists': true,
      'kind': 'String',
      'value':
          '<local>;localhost;127.0.0.1;127.*;10.*;'
          '172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;'
          '172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;'
          '172.28.*;172.29.*;172.30.*;172.31.*;192.168.*',
    },
  };
}

const _script = r'''
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$request = [Console]::In.ReadToEnd() | ConvertFrom-Json
if ($request.action -eq 'admin') {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  @{administrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)} | ConvertTo-Json -Compress
  exit 0
}
if ($request.action -eq 'elevate') {
  $null = Start-Process -FilePath ([string]$request.executable) -WorkingDirectory ([string]$request.directory) -ArgumentList '--restarted-elevated' -WindowStyle Hidden -Verb RunAs -PassThru -ErrorAction Stop
  @{started=$true} | ConvertTo-Json -Compress
  exit 0
}
if ($request.action -eq 'startupRead' -or $request.action -eq 'startupSet') {
  $path = 'Software\Microsoft\Windows\CurrentVersion\Run'
  $entry = 'DixFlutter'
  $expected = '"' + [string]$request.executable + '" --autostart'
  if ($request.action -eq 'startupSet') {
    $runKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
    try {
      if ($request.enabled) { $runKey.SetValue($entry, $expected, [Microsoft.Win32.RegistryValueKind]::String) }
      else { $runKey.DeleteValue($entry, $false) }
      $runKey.Flush()
    } finally { $runKey.Dispose() }
  }
  $runKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path, $false)
  $enabled = $false
  try { if ($null -ne $runKey) { $enabled = [string]$runKey.GetValue($entry, '') -ceq $expected } }
  finally { if ($null -ne $runKey) { $runKey.Dispose() } }
  @{enabled=$enabled} | ConvertTo-Json -Compress
  exit 0
}
function Owner-Alive($ownerPid, $ownerStart) {
  $owner = Get-Process -Id ([int]$ownerPid) -ErrorAction SilentlyContinue
  if ($null -eq $owner) { return $false }
  try { return $owner.StartTime.ToUniversalTime().Ticks.ToString() -ceq [string]$ownerStart }
  catch { return $true }
}
$watching = $request.action -eq 'watch'
if ($watching) {
  # This detached helper survives a GUI crash. A replaced/deleted journal means
  # the session ended normally; the helper never acts on a later session.
  @{watching=$true} | ConvertTo-Json -Compress
  [Console]::Out.Flush()
  while ($true) {
    if (!(Test-Path -LiteralPath ([string]$request.journal))) { exit 0 }
    try { $record = Get-Content -LiteralPath ([string]$request.journal) -Raw | ConvertFrom-Json }
    catch { exit 0 }
    if ([string]$record.leaseId -cne [string]$request.leaseId) { exit 0 }
    if (!(Owner-Alive $request.ownerPid $request.ownerStart)) { break }
    Start-Sleep -Milliseconds 1000
  }
  $request = [pscustomobject]@{action='restore'; previous=$record.previous; expected=$record.expected; ownerPid=$record.ownerPid; ownerStart=$record.ownerStart; requireDeadOwner=$true; journal=$request.journal; leaseId=$request.leaseId}
}
$mutex = New-Object System.Threading.Mutex($false, 'Local\DixFlutterProxyRegistryLease')
$locked = $false
$key = $null
$names = @('ProxyEnable', 'ProxyServer', 'ProxyOverride')
function Read-Values {
  $values = @{}
  $present = $key.GetValueNames()
  foreach ($name in $names) {
    if ($present -contains $name) {
      $values[$name] = @{exists=$true; kind=$key.GetValueKind($name).ToString(); value=$key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
    } else { $values[$name] = @{exists=$false} }
  }
  return $values
}
function Same-Values($current, $wanted) {
  foreach ($name in $names) {
    $a = $current[$name]
    $b = $wanted.$name
    if ($null -eq $b -or $a.exists -ne $b.exists) { return $false }
    if ($a.exists -and ($a.kind -cne $b.kind -or [string]$a.value -cne [string]$b.value)) { return $false }
  }
  return $true
}
function Write-Values($values) {
  foreach ($name in $names) {
    $item = $values.$name
    if ($null -eq $item) { throw 'Missing proxy value in recovery journal' }
    if ($item.exists) {
      $kind = [Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$item.kind))
      $value = $item.value
      if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $value = [int]$value }
      $key.SetValue($name, $value, $kind)
    } else { $key.DeleteValue($name, $false) }
  }
  $key.Flush()
}
function Notify-WinInet {
  $source = '[System.Runtime.InteropServices.DllImport("wininet.dll",SetLastError=true)] public static extern bool InternetSetOption(System.IntPtr h,int o,System.IntPtr b,int l);'
  $type = Add-Type -MemberDefinition $source -Name InternetOptions -Namespace Dix -PassThru
  $null = $type::InternetSetOption([IntPtr]::Zero,39,[IntPtr]::Zero,0)
  $null = $type::InternetSetOption([IntPtr]::Zero,37,[IntPtr]::Zero,0)
}
try {
  try { $locked = $mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $locked = $true }
  if (!$locked) { throw 'Proxy settings are busy' }
  if ($watching) {
    if (!(Test-Path -LiteralPath ([string]$request.journal))) { exit 0 }
    $latest = Get-Content -LiteralPath ([string]$request.journal) -Raw | ConvertFrom-Json
    if ([string]$latest.leaseId -cne [string]$request.leaseId) { exit 0 }
  }
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Internet Settings', $true)
  if ($null -eq $key) { throw 'Internet Settings registry key is unavailable' }
  $current = Read-Values
  switch ($request.action) {
    'read' {
      $ownerStart = (Get-Process -Id ([int]$request.ownerPid)).StartTime.ToUniversalTime().Ticks.ToString()
      @{values=$current; ownerStart=$ownerStart} | ConvertTo-Json -Depth 8 -Compress
    }
    'apply' {
      if (!(Same-Values $current $request.previous)) { throw 'System proxy changed in another application. Try connecting again.' }
      try {
        Write-Values $request.expected
        Notify-WinInet
      } catch {
        Write-Values $request.previous
        Notify-WinInet
        throw
      }
      @{applied=$true} | ConvertTo-Json -Compress
    }
    'restore' {
      $alive = $false
      if ($request.requireDeadOwner) {
        $alive = Owner-Alive $request.ownerPid $request.ownerStart
      }
      $restored = $false
      if (!$alive -and (Same-Values $current $request.expected)) {
        Write-Values $request.previous
        Notify-WinInet
        $restored = $true
      }
      if (!$watching) { @{restored=$restored; ownerAlive=$alive} | ConvertTo-Json -Compress }
      if ($watching -and !$alive) {
        # Recheck the identity under the same mutex before deleting the record.
        try {
          $latest = Get-Content -LiteralPath ([string]$request.journal) -Raw | ConvertFrom-Json
          if ([string]$latest.leaseId -ceq [string]$request.leaseId) {
            Remove-Item -LiteralPath ([string]$request.journal) -Force
          }
        } catch {}
      }
    }
    default { throw 'Unknown Windows system operation' }
  }
} finally {
  if ($null -ne $key) { $key.Dispose() }
  if ($locked) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
''';
