import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../data/models/app_usage_model.dart';
import '../data/repositories/app_usage_repository.dart';

// ── Win32 FFI 绑定 ────────────────────────────────────────────────────────────

final _user32 = Platform.isWindows ? DynamicLibrary.open('user32.dll') : null;
final _kernel32 = Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;
final _psapi = Platform.isWindows ? DynamicLibrary.open('psapi.dll') : null;

typedef _GetForegroundWindowNative = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();

typedef _GetWindowTextWNative = Int32 Function(IntPtr hwnd, Pointer<Utf16> buf, Int32 nMaxCount);
typedef _GetWindowTextWDart = int Function(int hwnd, Pointer<Utf16> buf, int nMaxCount);

typedef _GetWindowThreadProcessIdNative = Int32 Function(IntPtr hwnd, Pointer<Uint32> lpdwProcessId);
typedef _GetWindowThreadProcessIdDart = int Function(int hwnd, Pointer<Uint32> lpdwProcessId);

typedef _OpenProcessNative = IntPtr Function(Uint32 dwAccess, Int32 bInherit, Uint32 dwPid);
typedef _OpenProcessDart = int Function(int dwAccess, int bInherit, int dwPid);

typedef _QueryFullProcessImageNameWNative = Int32 Function(
    IntPtr hProcess, Uint32 dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize);
typedef _QueryFullProcessImageNameWDart = int Function(
    int hProcess, int dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize);

typedef _CloseHandleNative = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

_GetForegroundWindowDart? _getForegroundWindow;
_GetWindowTextWDart? _getWindowTextW;
_GetWindowThreadProcessIdDart? _getWindowThreadProcessId;
_OpenProcessDart? _openProcess;
_QueryFullProcessImageNameWDart? _queryFullProcessImageNameW;
_CloseHandleDart? _closeHandle;

void _initFfi() {
  if (!Platform.isWindows) return;
  _getForegroundWindow = _user32!
      .lookupFunction<_GetForegroundWindowNative, _GetForegroundWindowDart>('GetForegroundWindow');
  _getWindowTextW = _user32!
      .lookupFunction<_GetWindowTextWNative, _GetWindowTextWDart>('GetWindowTextW');
  _getWindowThreadProcessId = _user32!
      .lookupFunction<_GetWindowThreadProcessIdNative, _GetWindowThreadProcessIdDart>(
          'GetWindowThreadProcessId');
  _openProcess = _kernel32!
      .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
  _queryFullProcessImageNameW = _kernel32!
      .lookupFunction<_QueryFullProcessImageNameWNative, _QueryFullProcessImageNameWDart>(
          'QueryFullProcessImageNameW');
  _closeHandle = _kernel32!
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
}

bool _ffiReady = false;

/// 获取当前前台窗口的进程名（如 chrome.exe），失败返回 null
String? getForegroundAppName() {
  if (!Platform.isWindows) return null;
  if (!_ffiReady) {
    _initFfi();
    _ffiReady = true;
  }
  try {
    final hwnd = _getForegroundWindow!();
    if (hwnd == 0) return null;

    final pidPtr = calloc<Uint32>();
    _getWindowThreadProcessId!(hwnd, pidPtr);
    final pid = pidPtr.value;
    calloc.free(pidPtr);

    if (pid == 0) return null;

    // PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    final hProcess = _openProcess!(0x1000, 0, pid);
    if (hProcess == 0) return null;

    final buf = calloc<Uint16>(512);
    final sizePtr = calloc<Uint32>()..value = 512;
    final result = _queryFullProcessImageNameW!(hProcess, 0, buf.cast<Utf16>(), sizePtr);
    _closeHandle!(hProcess);

    if (result == 0 || sizePtr.value == 0) {
      calloc.free(buf);
      calloc.free(sizePtr);
      return null;
    }

    final fullPath = buf.cast<Utf16>().toDartString();
    calloc.free(buf);
    calloc.free(sizePtr);

    if (fullPath.isEmpty) return null;
    // 只取文件名部分
    return fullPath.split(r'\').last;
  } catch (_) {
    return null;
  }
}

// EnumProcesses FFI 绑定
typedef _EnumProcessesNative = Int32 Function(
    Pointer<Uint32> lpidProcess, Uint32 cb, Pointer<Uint32> lpcbNeeded);
typedef _EnumProcessesDart = int Function(
    Pointer<Uint32> lpidProcess, int cb, Pointer<Uint32> lpcbNeeded);

_EnumProcessesDart? _enumProcesses;

void _initEnumProcesses() {
  if (_enumProcesses != null) return;
  if (!Platform.isWindows) return;
  if (!_ffiReady) {
    _initFfi();
    _ffiReady = true;
  }
  _enumProcesses = _psapi!
      .lookupFunction<_EnumProcessesNative, _EnumProcessesDart>('EnumProcesses');
}

/// 获取当前所有运行中的进程名列表（去重，排除系统进程和自身）
List<String> getRunningProcesses() {
  if (!Platform.isWindows) return [];
  _initEnumProcesses();
  try {
    const maxProcesses = 1024;
    final pids = calloc<Uint32>(maxProcesses);
    final needed = calloc<Uint32>();

    _enumProcesses!(pids, maxProcesses * 4, needed);
    final count = needed.value ~/ 4;
    calloc.free(needed);

    final names = <String>{};
    for (var i = 0; i < count; i++) {
      final pid = pids[i];
      if (pid == 0) continue;
      final hProcess = _openProcess!(0x1000, 0, pid);
      if (hProcess == 0) continue;

      final buf = calloc<Uint16>(512);
      final sizePtr = calloc<Uint32>()..value = 512;
      final result = _queryFullProcessImageNameW!(hProcess, 0, buf.cast<Utf16>(), sizePtr);
      _closeHandle!(hProcess);

      if (result == 0 || sizePtr.value == 0) {
        calloc.free(buf);
        calloc.free(sizePtr);
        continue;
      }

      final fullPath = buf.cast<Utf16>().toDartString();
      calloc.free(buf);
      calloc.free(sizePtr);

      if (fullPath.isEmpty) continue;
      final name = fullPath.split(r'\').last.toLowerCase();
      if (name == _kSelfName) continue;
      if (name.isEmpty) continue;
      names.add(name);
    }
    calloc.free(pids);
    return names.toList()..sort();
  } catch (_) {
    return [];
  }
}

// ── AppMonitor ────────────────────────────────────────────────────────────────

const _kPollInterval = Duration(seconds: 3);
const _kSelfName = 'openforest.exe';

class AppMonitor {
  AppMonitor(this._repo);

  final AppUsageRepository _repo;

  Timer? _ticker;
  String? _currentApp;
  DateTime? _appStartTime;
  int? _sessionId;
  bool _running = false;

  void start(int? sessionId) {
    if (!Platform.isWindows) return;
    _sessionId = sessionId;
    _running = true;
    _currentApp = null;
    _appStartTime = null;
    _ticker = Timer.periodic(_kPollInterval, (_) => _onTick());
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _ticker?.cancel();
    _ticker = null;
    await _flush();
    _currentApp = null;
    _appStartTime = null;
  }

  void updateSessionId(int sessionId) {
    _sessionId = sessionId;
  }

  void _onTick() {
    final app = getForegroundAppName();
    if (app == null || app.toLowerCase() == _kSelfName) {
      // 自身窗口或无法获取，不记录
      return;
    }

    if (_currentApp == null) {
      _currentApp = app;
      _appStartTime = DateTime.now();
      return;
    }

    if (app != _currentApp) {
      // 应用切换，flush 上一条
      unawaited(_flushCurrent().catchError((_) {}));
      _currentApp = app;
      _appStartTime = DateTime.now();
    }
  }

  Future<void> _flush() async {
    if (_currentApp != null && _appStartTime != null) {
      await _flushCurrent();
    }
  }

  Future<void> _flushCurrent() async {
    final app = _currentApp;
    final start = _appStartTime;
    if (app == null || start == null) return;

    final duration = DateTime.now().difference(start).inSeconds;
    if (duration < 1) return;

    await _repo.addUsage(AppUsageModel(
      sessionId: _sessionId,
      appName: app,
      durationSeconds: duration,
      recordedAt: start,
    ));
  }
}

