import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/tag_model.dart';

/// 计时模式
enum TimerMode {
  /// 倒计时（常规专注）
  countdown,

  /// 正计时（本 MVP 暂未在 UI 暴露，但核心逻辑支持）
  stopwatch,

  /// 番茄钟（工作/休息）
  pomodoro,
}

/// 计时器状态
enum TimerState {
  idle,
  running,
  paused,
  completed,
  failed,
}

/// 计时服务（核心逻辑）
///
/// - 倒计时 / 正计时 / 番茄钟
/// - 完成回调：onComplete(coinsEarned)
/// - 失败回调：onFailed()
/// - 金币规则：每分钟 1 金币，最少 10 分钟才给金币
class TimerService extends ChangeNotifier {
  TimerService();

  TimerMode _mode = TimerMode.countdown;
  TimerState _state = TimerState.idle;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;

  Duration _targetDuration = const Duration(minutes: 25);
  Duration _remaining = const Duration(minutes: 25);
  Duration _elapsed = Duration.zero;

  DateTime? _startTime;
  DateTime? _endTime;

  // 番茄钟：是否处于“休息阶段”
  bool _isPomodoroBreak = false;

  // 失焦枯萎警告状态（用于树动画变灰）
  bool _withering = false;

  // 当前选中标签
  TagModel? _currentTag;

  /// 完成回调（UI/Provider 可注册）
  Future<void> Function(int coinsEarned)? onComplete;

  /// 失败回调（UI/Provider 可注册）
  Future<void> Function()? onFailed;

  TimerMode get mode => _mode;
  TimerState get state => _state;
  Duration get targetDuration => _targetDuration;
  Duration get remaining => _remaining;
  Duration get elapsed => _elapsed;
  DateTime? get startTime => _startTime;
  DateTime? get endTime => _endTime;
  bool get isPomodoroBreak => _isPomodoroBreak;
  bool get withering => _withering;
  TagModel? get currentTag => _currentTag;

  void setCurrentTag(TagModel? tag) {
    _currentTag = tag;
    notifyListeners();
  }

  /// 进度 0.0 ~ 1.0（倒计时/番茄钟阶段有效）
  double get progress {
    if (_mode == TimerMode.stopwatch) return 0.0;
    final totalMs = _targetDuration.inMilliseconds;
    if (totalMs <= 0) return 0.0;
    final p = _elapsed.inMilliseconds / totalMs;
    return p.clamp(0.0, 1.0);
  }

  /// 开始计时
  ///
  /// - [duration]：目标时长
  /// - [mode]：计时模式
  /// - 番茄钟可通过 [isBreak] 指定阶段（工作/休息）
  void startTimer(
    Duration duration,
    TimerMode mode, {
    bool isBreak = false,
  }) {
    _cancelTicker();

    _mode = mode;
    _state = TimerState.running;
    _withering = false;

    _targetDuration = duration;
    _isPomodoroBreak = mode == TimerMode.pomodoro ? isBreak : false;

    _startTime = DateTime.now();
    _endTime = null;

    _stopwatch
      ..reset()
      ..start();

    _elapsed = Duration.zero;
    _remaining = _mode == TimerMode.stopwatch ? Duration.zero : _targetDuration;

    // 每秒刷新一次 UI
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    notifyListeners();
  }

  void pauseTimer() {
    if (_state != TimerState.running) return;
    _state = TimerState.paused;
    _stopwatch.stop();
    _cancelTicker();
    notifyListeners();
  }

  void resumeTimer() {
    if (_state != TimerState.paused) return;
    _state = TimerState.running;
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    notifyListeners();
  }

  /// 放弃/中断（触发枯萎）
  void abandonTimer() {
    if (!isActive) return;

    _withering = true;
    _state = TimerState.failed;
    _endTime = DateTime.now();

    _stopwatch.stop();
    _cancelTicker();

    notifyListeners();
    unawaited(onFailed?.call());
  }

  /// 设置枯萎状态（用于失焦警告时变灰）
  void setWithering(bool value) {
    if (_withering == value) return;
    _withering = value;
    notifyListeners();
  }

  /// 重置回 Idle
  void reset() {
    _cancelTicker();
    _stopwatch.stop();
    _stopwatch.reset();

    _state = TimerState.idle;
    _withering = false;
    _elapsed = Duration.zero;
    _remaining = _targetDuration;
    _startTime = null;
    _endTime = null;
    _isPomodoroBreak = false;
    _currentTag = null;
    notifyListeners();
  }

  bool get isActive =>
      _state == TimerState.running || _state == TimerState.paused;

  int calculateCoinsForDuration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 10) return 0;
    // 每分钟 1 金币
    return minutes;
  }

  void _onTick() {
    if (_state != TimerState.running) return;

    _elapsed = _stopwatch.elapsed;

    if (_mode == TimerMode.stopwatch) {
      // 正计时：持续增长，不自动完成
      notifyListeners();
      return;
    }

    final remain = _targetDuration - _elapsed;
    _remaining = remain.isNegative ? Duration.zero : remain;

    if (_remaining == Duration.zero) {
      _complete();
      return;
    }

    notifyListeners();
  }

  void _complete() {
    _state = TimerState.completed;
    _endTime = DateTime.now();

    _stopwatch.stop();
    _cancelTicker();

    // 休息阶段不产出金币
    final coins =
        (_mode == TimerMode.pomodoro && _isPomodoroBreak) ? 0 : calculateCoinsForDuration(_targetDuration);

    notifyListeners();
    unawaited(onComplete?.call(coins));
  }

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _cancelTicker();
    _stopwatch.stop();
    super.dispose();
  }
}

