import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app_monitor.dart';

/// 窗口失焦检测（Desktop）
///
/// - 失焦后检查前台应用是否在白名单，在则忽略
/// - 不在白名单：触发 onBlurWithUnknownApp（弹出"加入白名单"提示）
/// - 超过 warningDelay：触发枯萎警告
/// - 超过 failureDelay：触发失败
class FocusDetector extends StatefulWidget {
  const FocusDetector({
    super.key,
    required this.child,
    required this.enabled,
    required this.onWitherWarning,
    required this.onFailed,
    this.onFocusBack,
    this.whitelist = const [],
    this.blacklist = const [],
    this.warningDelay = const Duration(seconds: 3),
    this.failureDelay = const Duration(seconds: 10),
  });

  final Widget child;
  final bool enabled;
  final VoidCallback onWitherWarning;
  final VoidCallback onFailed;
  final VoidCallback? onFocusBack;

  /// 允许切换的进程名列表（小写）— 不触发失焦计时
  final List<String> whitelist;

  /// 黑名单进程名列表（小写）— 静默忽略，不触发任何回调
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

    // 检查前台应用是否在白名单或黑名单
    if (Platform.isWindows) {
      final app = getForegroundAppName()?.toLowerCase();
      if (app != null && app.isNotEmpty) {
        if (widget.whitelist.contains(app) || widget.blacklist.contains(app)) {
          return;
        }
      }
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
