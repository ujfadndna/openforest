import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app_monitor.dart';

/// 窗口失焦检测（Desktop）
///
/// - 切到黑名单应用 → 触发枯萎
/// - 切到其他应用 → 忽略
/// - 暂停（enabled=false）→ 不触发任何回调
class FocusDetector extends StatefulWidget {
  const FocusDetector({
    super.key,
    required this.child,
    required this.enabled,
    required this.onWitherWarning,
    required this.onFailed,
    this.onFocusBack,
    this.blacklist = const [],
    this.warningDelay = const Duration(seconds: 3),
    this.failureDelay = const Duration(seconds: 10),
  });

  final Widget child;
  final bool enabled;
  final VoidCallback onWitherWarning;
  final VoidCallback onFailed;
  final VoidCallback? onFocusBack;

  /// 黑名单进程名列表（小写）— 切到这些应用触发枯萎
  final List<String> blacklist;

  final Duration warningDelay;
  final Duration failureDelay;

  @override
  State<FocusDetector> createState() => _FocusDetectorState();
}

class _FocusDetectorState extends State<FocusDetector> with WindowListener {
  Timer? _warningTimer;
  Timer? _failureTimer;
  bool _warned = false;

  bool get _isDesktop {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
  }

  @override
  void didUpdateWidget(covariant FocusDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _clearTimers(resetWarned: true);
      widget.onFocusBack?.call();
    }
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    _clearTimers(resetWarned: true);
    super.dispose();
  }

  @override
  void onWindowBlur() {
    if (!mounted || !widget.enabled) return;

    // 只有切到黑名单应用才触发枯萎
    if (Platform.isWindows) {
      final app = getForegroundAppName()?.toLowerCase();
      if (app == null || app.isEmpty) return;
      if (!widget.blacklist.contains(app)) return;
    } else {
      // 非 Windows 平台不触发
      return;
    }

    _clearTimers(resetWarned: false);

    _warningTimer = Timer(widget.warningDelay, () {
      if (!mounted || !widget.enabled) return;
      _warned = true;
      widget.onWitherWarning();
    });

    _failureTimer = Timer(widget.failureDelay, () {
      if (!mounted || !widget.enabled) return;
      widget.onFailed();
    });
  }

  @override
  void onWindowFocus() {
    if (!mounted) return;
    if (!widget.enabled) {
      _clearTimers(resetWarned: true);
      return;
    }
    final hadWarned = _warned;
    _clearTimers(resetWarned: true);
    if (hadWarned) widget.onFocusBack?.call();
  }

  void _clearTimers({required bool resetWarned}) {
    _warningTimer?.cancel();
    _failureTimer?.cancel();
    _warningTimer = null;
    _failureTimer = null;
    if (resetWarned) _warned = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
