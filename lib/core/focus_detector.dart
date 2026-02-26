import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口失焦检测（Desktop）
///
/// 设计目标：
/// - 失焦超过 warningDelay：触发“枯萎警告”（UI 可变灰 + SnackBar 提示）
/// - 失焦超过 failureDelay：触发失败（枯萎/中断）
///
/// 注意：window_manager 仅在桌面端可用，本 Widget 在移动端/网页端会自动降级为“仅包裹 child”。
class FocusDetector extends StatefulWidget {
  const FocusDetector({
    super.key,
    required this.child,
    required this.enabled,
    required this.onWitherWarning,
    required this.onFailed,
    this.onFocusBack,
    this.warningDelay = const Duration(seconds: 3),
    this.failureDelay = const Duration(seconds: 10),
  });

  final Widget child;

  /// 是否启用检测（通常仅在计时 running 时启用）
  final bool enabled;

  /// 失焦超过 warningDelay 时触发
  final VoidCallback onWitherWarning;

  /// 失焦超过 failureDelay 时触发
  final VoidCallback onFailed;

  /// 重新聚焦时触发（用于取消枯萎状态）
  final VoidCallback? onFocusBack;

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
      TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS =>
        true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
    }
  }

  @override
  void didUpdateWidget(covariant FocusDetector oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果从 enabled -> disabled，清理所有定时器并重置状态
    if (oldWidget.enabled && !widget.enabled) {
      _clearTimers(resetWarned: true);
      widget.onFocusBack?.call();
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    _clearTimers(resetWarned: true);
    super.dispose();
  }

  @override
  void onWindowBlur() {
    if (!mounted) return;
    if (!widget.enabled) return;

    _clearTimers(resetWarned: false);

    // warningDelay：提示枯萎
    _warningTimer = Timer(widget.warningDelay, () {
      if (!mounted) return;
      if (!widget.enabled) return;
      _warned = true;
      widget.onWitherWarning();
    });

    // failureDelay：直接失败
    _failureTimer = Timer(widget.failureDelay, () {
      if (!mounted) return;
      if (!widget.enabled) return;
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

    // 重新聚焦后：如果之前已触发警告，通知 UI 恢复颜色。
    if (hadWarned) {
      widget.onFocusBack?.call();
    }
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

