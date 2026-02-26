import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_monitor.dart';
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
  int _nextPomodoroRound = 1;
  String? _nextSpeciesOverride;

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
    final accumulatedSeconds = ref.watch(accumulatedSecondsProvider);

    final isRunning = timer.state == TimerState.running;
    final isPaused = timer.state == TimerState.paused;
    final isIdle = timer.state == TimerState.idle;
    final isCompleted = timer.state == TimerState.completed;
    final isFailed = timer.state == TimerState.failed;

    final treeState = switch (timer.state) {
      TimerState.completed => TreeVisualState.completed,
      TimerState.failed => TreeVisualState.dead,
      _ => TreeVisualState.growing,
    };

    // 累计进度：已累计秒数 + 当前段已过秒数（非休息时）
    final trees = ref.watch(treeSpeciesListProvider).asData?.value ?? [];
    final currentSpeciesData = trees.firstWhere(
      (t) => t.id == selectedSpecies,
      orElse: () => trees.isNotEmpty
          ? trees.first
          : const TreeSpecies(id: 'oak', name: '橡树', price: 0, unlockedByDefault: true, description: '', milestoneMinutes: 45),
    );
    final requiredSeconds = currentSpeciesData.milestoneMinutes * 60;
    final isBreakPhase = timer.mode == TimerMode.pomodoro && timer.isPomodoroBreak;
    final currentSegmentSeconds = (!isIdle && !isBreakPhase) ? timer.elapsed.inSeconds : 0;
    final totalAccumulated = accumulatedSeconds + currentSegmentSeconds;
    final treeProgress = requiredSeconds > 0
        ? (totalAccumulated % requiredSeconds) / requiredSeconds
        : 0.0;

    final displayDuration = switch (timer.mode) {
      TimerMode.stopwatch => timer.elapsed,
      _ => timer.remaining,
    };

    final sliderMin = settings.minFocusMinutes.toDouble();
    final sliderMax = settings.maxFocusMinutes.toDouble();

    final effectiveWorkMinutes =
        _selectedMode == TimerMode.pomodoro ? settings.pomodoroWorkMinutes : _selectedMinutes;

    final durationLabel = switch (_selectedMode) {
      TimerMode.stopwatch => '正计时 · 已累计 ${(totalAccumulated ~/ 60)} 分钟',
      TimerMode.pomodoro => timer.isPomodoroBreak
          ? (timer.isLongBreak ? '长休息 ${settings.pomodoroLongBreakMinutes} 分钟' : '休息 ${settings.pomodoroBreakMinutes} 分钟')
          : '番茄钟 第${timer.pomodoroRound}/${timer.pomodoroTotalRounds}个 · 已累计 ${(totalAccumulated ~/ 60)} 分钟 / ${currentSpeciesData.milestoneMinutes} 分钟',
      _ => '专注时长：$effectiveWorkMinutes 分钟 · 已累计 ${(totalAccumulated ~/ 60)} 分钟 / ${currentSpeciesData.milestoneMinutes} 分钟',
    };

    return Padding(
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
                              progress: isIdle ? 0.15 : treeProgress,
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
                            icon: const Icon(Icons.stop),
                            label: const Text('结束计时'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      timer.isPomodoroBreak ? '休息中：可自由离开应用' : '专注中',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],

                  if (isCompleted) ...[
                    _CompletedPanel(
                      isPomodoro: timer.mode == TimerMode.pomodoro,
                      isPomodoroBreak: timer.isPomodoroBreak,
                      pomodoroRound: timer.pomodoroRound,
                      pomodoroTotalRounds: timer.pomodoroTotalRounds,
                      isLongBreak: timer.isLongBreak,
                      onReset: () {
                        setState(() {
                          _nextPomodoroRound = 1;
                          _nextSpeciesOverride = null;
                        });
                        ref.read(timerServiceProvider).reset();
                      },
                      onSpeciesSelected: (id) => setState(() => _nextSpeciesOverride = id),
                      selectedSpeciesOverride: _nextSpeciesOverride,
                      onStartBreak: timer.mode == TimerMode.pomodoro && !timer.isPomodoroBreak
                          ? () {
                              final isLong = timer.isLongBreak;
                              final breakMinutes = isLong
                                  ? settings.pomodoroLongBreakMinutes
                                  : settings.pomodoroBreakMinutes;
                              ref.read(timerServiceProvider).startTimer(
                                    Duration(minutes: breakMinutes),
                                    TimerMode.pomodoro,
                                    isBreak: true,
                                    pomodoroRound: timer.pomodoroRound,
                                    pomodoroTotalRounds: timer.pomodoroTotalRounds,
                                  );
                            }
                          : null,
                      onStartNextWork: timer.mode == TimerMode.pomodoro && timer.isPomodoroBreak
                          ? () {
                              final nextRound = (timer.pomodoroRound % timer.pomodoroTotalRounds) + 1;
                              setState(() => _nextPomodoroRound = nextRound);
                              final String species = _nextSpeciesOverride ?? ref.read(selectedSpeciesProvider);
                              ref.read(timerServiceProvider).setCurrentSpecies(species);
                              ref.read(timerServiceProvider).startTimer(
                                    Duration(minutes: settings.pomodoroWorkMinutes),
                                    TimerMode.pomodoro,
                                    isBreak: false,
                                    pomodoroRound: nextRound,
                                    pomodoroTotalRounds: timer.pomodoroTotalRounds,
                                  );
                              setState(() => _nextSpeciesOverride = null);
                            }
                          : null,
                      breakMinutes: settings.pomodoroBreakMinutes,
                      longBreakMinutes: settings.pomodoroLongBreakMinutes,
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
    ref.read(timerServiceProvider).startTimer(
      duration,
      _selectedMode,
      isBreak: false,
      pomodoroRound: _nextPomodoroRound,
      pomodoroTotalRounds: settings.pomodoroRounds,
    );
    ref.read(appMonitorProvider).start(null);
  }

  Future<void> _confirmAbandon(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('结束计时？'),
          content: const Text('当前这棵树的进度会清零，不计入记录。之前种好的树不受影响。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('结束'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      ref.read(timerServiceProvider).reset();
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

class _CompletedPanel extends ConsumerWidget {
  const _CompletedPanel({
    required this.isPomodoro,
    required this.isPomodoroBreak,
    required this.pomodoroRound,
    required this.pomodoroTotalRounds,
    required this.isLongBreak,
    required this.onReset,
    required this.breakMinutes,
    required this.longBreakMinutes,
    required this.onSpeciesSelected,
    this.selectedSpeciesOverride,
    this.onStartBreak,
    this.onStartNextWork,
  });

  final bool isPomodoro;
  final bool isPomodoroBreak;
  final int pomodoroRound;
  final int pomodoroTotalRounds;
  final bool isLongBreak;
  final int breakMinutes;
  final int longBreakMinutes;
  final VoidCallback onReset;
  final ValueChanged<String> onSpeciesSelected;
  final String? selectedSpeciesOverride;
  final VoidCallback? onStartBreak;
  final VoidCallback? onStartNextWork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trees = ref.watch(treeSpeciesListProvider).asData?.value ?? [];
    final currentSpecies = ref.watch(selectedSpeciesProvider);
    final displaySpecies = selectedSpeciesOverride ?? currentSpecies;

    String title;
    if (isPomodoro && !isPomodoroBreak) {
      title = '第 $pomodoroRound/$pomodoroTotalRounds 棵树种下了';
    } else if (isPomodoro && isPomodoroBreak) {
      title = '休息结束';
    } else {
      title = '专注完成，树种下了';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            // 番茄钟工作段完成后显示树种选择
            if (isPomodoro && !isPomodoroBreak && trees.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('下一棵选什么？', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: trees.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final t = trees[i];
                    final selected = displaySpecies == t.id;
                    return GestureDetector(
                      onTap: () => onSpeciesSelected(t.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: selected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: selected
                              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)
                              : null,
                        ),
                        child: Text(
                          t.name,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: selected ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (isPomodoro && onStartBreak != null) ...[
              FilledButton(
                onPressed: onStartBreak,
                child: Text(isLongBreak ? '开始长休息 $longBreakMinutes 分钟' : '开始休息 $breakMinutes 分钟'),
              ),
              const SizedBox(height: 8),
            ],
            if (isPomodoro && onStartNextWork != null) ...[
              FilledButton(
                onPressed: onStartNextWork,
                child: const Text('开始下一轮专注'),
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
