import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_monitor.dart';
import '../../core/focus_detector.dart';
import '../../core/timer_service.dart';
import '../../data/models/tag_model.dart';
import '../../data/models/tree_species.dart';
import '../settings/settings_screen.dart';
import '../shop/shop_provider.dart';
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
  void dispose() {
    super.dispose();
  }

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
    final selectedSpecies = ref.watch(selectedSpeciesProvider);

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

    final sliderMin = settings.minFocusMinutes.toDouble();
    final sliderMax = settings.maxFocusMinutes.toDouble();

    final effectiveWorkMinutes =
        _selectedMode == TimerMode.pomodoro ? settings.pomodoroWorkMinutes : _selectedMinutes;

    final durationLabel = switch (_selectedMode) {
      TimerMode.stopwatch => timer.milestoneMinutes > 0
          ? '正计时·里程碑 ${timer.milestoneMinutes} 分钟（已完成 ${timer.milestonesCompleted} 棵）'
          : '正计时：无限制',
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
      whitelist: settings.focusWhitelist,
      blacklist: settings.focusBlacklist,
      onWitherWarning: () {
        ref.read(timerServiceProvider).setWithering(true);
      },
      onFocusBack: () {
        ref.read(timerServiceProvider).setWithering(false);
      },
      onFailed: () {
        // 失焦超时：保持枯萎状态，计时器继续运行，回来聚焦可救活
        ref.read(timerServiceProvider).setWithering(true);
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
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          children: [
                            AnimatedTree(
                              progress: isIdle ? 0.15 : timer.progress,
                              state: treeState,
                              seed: 1,
                              speciesId: selectedSpecies,
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: CustomPaint(
                                size: const Size(double.infinity, 12),
                                painter: _SoilLinePainter(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 当前树种名
                  Builder(builder: (context) {
                    final trees = ref.watch(treeSpeciesListProvider).asData?.value ?? [];
                    final name = trees.firstWhere(
                      (t) => t.id == selectedSpecies,
                      orElse: () => trees.isNotEmpty ? trees.first
                          : const TreeSpecies(id: '', name: '', price: 0, unlockedByDefault: true, description: '', milestoneMinutes: 90),
                    ).name;
                    return Text(
                      name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
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
                  if (isIdle) ...[
                    _TagSelector(
                      selected: _selectedTag,
                      onChanged: (t) => setState(() => _selectedTag = t),
                    ),
                  ],
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
    ref.read(timerServiceProvider).setCurrentSpecies(ref.read(selectedSpeciesProvider));

    // 正计时模式：从树种数据里取里程碑时长
    if (_selectedMode == TimerMode.stopwatch) {
      final trees = ref.read(treeSpeciesListProvider).asData?.value ?? [];
      final species = trees.firstWhere(
        (t) => t.id == ref.read(selectedSpeciesProvider),
        orElse: () => trees.isNotEmpty
            ? trees.first
            : const TreeSpecies(
                id: 'oak',
                name: '橡树',
                price: 0,
                unlockedByDefault: true,
                description: '',
                milestoneMinutes: 90,
              ),
      );
      ref.read(timerServiceProvider).setMilestoneMinutes(species.milestoneMinutes);
    } else {
      ref.read(timerServiceProvider).setMilestoneMinutes(0);
    }
    ref.read(timerServiceProvider).startTimer(duration, _selectedMode, isBreak: false);
    ref.read(appMonitorProvider).start(null); // sessionId 在完成后更新
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
      unawaited(ref.read(appMonitorProvider).stop());
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
    required this.isPomodoro,
    required this.onReset,
    required this.breakMinutes,
    this.onStartBreak,
  });

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
              '专注完成，树种下了',
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
  const _FailedPanel({required this.onReset});

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

// ─── 土壤线 ───────────────────────────────────────────────────────────────────

class _SoilLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5D4037).withOpacity(0.45)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final y = size.height * 0.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(_SoilLinePainter old) => false;
}
