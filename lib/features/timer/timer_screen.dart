import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/focus_detector.dart';
import '../../core/timer_service.dart';
import '../../data/models/tag_model.dart';
import '../settings/settings_screen.dart';
import 'timer_provider.dart';
import 'tree_painter.dart';

class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({super.key});

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen> {
  int _selectedMinutes = 25;
  TimerMode _selectedMode = TimerMode.countdown;
  TagModel? _selectedTag;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = ref.read(settingsControllerProvider);

    // 根据设置修正默认值与范围
    final minM = settings.minFocusMinutes;
    final maxM = settings.maxFocusMinutes;
    if (_selectedMinutes < minM) _selectedMinutes = minM;
    if (_selectedMinutes > maxM) _selectedMinutes = maxM;
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(timerServiceProvider);
    final settings = ref.watch(settingsControllerProvider);
    final coinsAsync = ref.watch(totalCoinsProvider);

    final isRunning = timer.state == TimerState.running;
    final isPaused = timer.state == TimerState.paused;
    final isIdle = timer.state == TimerState.idle;
    final isCompleted = timer.state == TimerState.completed;
    final isFailed = timer.state == TimerState.failed;

    final focusGuardEnabled =
        isRunning && !(timer.mode == TimerMode.pomodoro && timer.isPomodoroBreak);

    final treeState = switch (timer.state) {
      TimerState.completed => TreeVisualState.completed,
      TimerState.failed => TreeVisualState.dead,
      _ => timer.withering ? TreeVisualState.withering : TreeVisualState.growing,
    };

    final displayDuration = switch (timer.mode) {
      TimerMode.stopwatch => timer.elapsed,
      _ => timer.remaining,
    };

    final coinsText = coinsAsync.when(
      data: (v) => v.toString(),
      loading: () => '…',
      error: (_, __) => '0',
    );

    final sliderMin = settings.minFocusMinutes.toDouble();
    final sliderMax = settings.maxFocusMinutes.toDouble();

    final effectiveWorkMinutes =
        _selectedMode == TimerMode.pomodoro ? settings.pomodoroWorkMinutes : _selectedMinutes;

    final durationLabel = switch (_selectedMode) {
      TimerMode.stopwatch => '正计时：无限制',
      TimerMode.pomodoro => '番茄钟工作：$effectiveWorkMinutes 分钟',
      _ => '专注时长：$effectiveWorkMinutes 分钟',
    };

    // 为了保证“先警告、后失败”，失败阈值至少为 10 秒，
    // 且不小于 warningDelay + 7 秒（默认 warning=3 → failure=10）。
    final failureSeconds = (settings.focusWarningSeconds + 7);
    final failureDelay = Duration(seconds: failureSeconds < 10 ? 10 : failureSeconds);

    return FocusDetector(
      enabled: focusGuardEnabled,
      warningDelay: Duration(seconds: settings.focusWarningSeconds),
      failureDelay: failureDelay,
      onWitherWarning: () {
        ref.read(timerServiceProvider).setWithering(true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('检测到窗口失焦：请回到应用，否则树会枯萎…')),
          );
        }
      },
      onFocusBack: () {
        ref.read(timerServiceProvider).setWithering(false);
      },
      onFailed: () {
        // 失焦超过阈值：直接判定失败
        ref.read(timerServiceProvider).abandonTimer();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('失焦过久：本次专注失败，树枯萎了')),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左栏：树动画
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.monetization_on_outlined),
                      const SizedBox(width: 8),
                      Text(
                        '金币：$coinsText',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: AnimatedTree(
                          progress: isIdle ? 0.15 : timer.progress,
                          state: treeState,
                          seed: 1,
                          speciesId: 'oak',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 24),
            const VerticalDivider(),
            const SizedBox(width: 24),

            // 右栏：计时控制
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ModeToggle(
                    mode: _selectedMode,
                    enabled: isIdle,
                    onChanged: (m) => setState(() => _selectedMode = m),
                  ),
                  const SizedBox(height: 12),
                  if (isIdle)
                    _TagSelector(
                      selected: _selectedTag,
                      onChanged: (t) => setState(() => _selectedTag = t),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    _formatDuration(displayDuration),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    durationLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),

                  if (isIdle) ...[
                    Slider(
                      value: _selectedMinutes.toDouble().clamp(sliderMin, sliderMax),
                      min: sliderMin,
                      max: sliderMax,
                      divisions: (sliderMax - sliderMin).round(),
                      label: '$_selectedMinutes 分钟',
                      onChanged: (_selectedMode == TimerMode.pomodoro || _selectedMode == TimerMode.stopwatch)
                          ? null
                          : (v) => setState(() => _selectedMinutes = v.round()),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _onStartPressed(settings),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始专注'),
                    ),
                  ],

                  if (!isIdle && !isCompleted && !isFailed) ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isRunning
                                ? () => ref.read(timerServiceProvider).pauseTimer()
                                : isPaused
                                    ? () => ref.read(timerServiceProvider).resumeTimer()
                                    : null,
                            icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
                            label: Text(isRunning ? '暂停' : '继续'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmAbandon(context),
                            icon: const Icon(Icons.close),
                            label: const Text('放弃'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedMode == TimerMode.pomodoro
                          ? (timer.isPomodoroBreak ? '休息中：可自由离开应用' : '工作中：请保持专注（失焦会枯萎）')
                          : '专注中：请保持专注（失焦会枯萎）',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],

                  if (isCompleted) ...[
                    _CompletedPanel(
                      coinsEarned: timer.calculateCoinsForDuration(timer.targetDuration),
                      isPomodoro: timer.mode == TimerMode.pomodoro,
                      onReset: () => ref.read(timerServiceProvider).reset(),
                      onStartBreak: timer.mode == TimerMode.pomodoro && !timer.isPomodoroBreak
                          ? () {
                              final breakMinutes = settings.pomodoroBreakMinutes;
                              ref.read(timerServiceProvider).startTimer(
                                    Duration(minutes: breakMinutes),
                                    TimerMode.pomodoro,
                                    isBreak: true,
                                  );
                            }
                          : null,
                      breakMinutes: settings.pomodoroBreakMinutes,
                    ),
                  ],

                  if (isFailed) ...[
                    _FailedPanel(
                      lostCoins: timer.calculateCoinsForDuration(timer.elapsed),
                      onReset: () => ref.read(timerServiceProvider).reset(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onStartPressed(SettingsState settings) {
    final duration = switch (_selectedMode) {
      TimerMode.pomodoro => Duration(minutes: settings.pomodoroWorkMinutes),
      TimerMode.stopwatch => const Duration(hours: 24),
      _ => Duration(minutes: _selectedMinutes),
    };

    ref.read(timerServiceProvider).setCurrentTag(_selectedTag);
    ref
        .read(timerServiceProvider)
        .startTimer(duration, _selectedMode, isBreak: false);
  }

  Future<void> _confirmAbandon(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('放弃本次专注？'),
          content: const Text('放弃会导致树枯萎，并记为失败记录。确定要放弃吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确定放弃'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      ref.read(timerServiceProvider).abandonTimer();
    }
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final TimerMode mode;
  final bool enabled;
  final ValueChanged<TimerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TimerMode>(
      segments: const [
        ButtonSegment(value: TimerMode.stopwatch, label: Text('正计时')),
        ButtonSegment(value: TimerMode.countdown, label: Text('倒计时')),
        ButtonSegment(value: TimerMode.pomodoro, label: Text('番茄钟')),
      ],
      selected: {mode},
      onSelectionChanged: enabled
          ? (set) {
              if (set.isEmpty) return;
              onChanged(set.first);
            }
          : null,
      showSelectedIcon: false,
    );
  }
}

class _CompletedPanel extends StatelessWidget {
  const _CompletedPanel({
    required this.coinsEarned,
    required this.isPomodoro,
    required this.onReset,
    required this.breakMinutes,
    this.onStartBreak,
  });

  final int coinsEarned;
  final bool isPomodoro;
  final int breakMinutes;
  final VoidCallback onReset;
  final VoidCallback? onStartBreak;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '完成！获得 $coinsEarned 金币',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (isPomodoro && onStartBreak != null) ...[
              FilledButton(
                onPressed: onStartBreak,
                child: Text('开始休息 $breakMinutes 分钟'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: onReset,
              child: const Text('回到首页'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedPanel extends StatelessWidget {
  const _FailedPanel({
    required this.lostCoins,
    required this.onReset,
  });

  final int lostCoins;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '专注失败，树枯萎了',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '未获得金币（损失潜在 $lostCoins 金币）',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onReset,
              child: const Text('再试一次'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 标签选择器 ────────────────────────────────────────────────────────────────

class _TagSelector extends ConsumerWidget {
  const _TagSelector({required this.selected, required this.onChanged});

  final TagModel? selected;
  final ValueChanged<TagModel?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsStreamProvider);

    final tags = tagsAsync.valueOrNull ?? const [];

    return Row(
      children: [
        const Icon(Icons.label_outline, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButton<TagModel?>(
            value: tags.contains(selected) ? selected : null,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            hint: const Text('无标签'),
            items: [
              const DropdownMenuItem<TagModel?>(
                value: null,
                child: Text('无标签'),
              ),
              ...tags.map(
                (t) => DropdownMenuItem<TagModel?>(
                  value: t,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(t.name),
                    ],
                  ),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
