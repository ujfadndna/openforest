import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/tag_model.dart';
import '../../data/repositories/tag_repository.dart';
import '../timer/timer_provider.dart';

/// 设置状态（SharedPreferences 持久化）
class SettingsState {
  const SettingsState({
    required this.minFocusMinutes,
    required this.maxFocusMinutes,
    required this.pomodoroWorkMinutes,
    required this.pomodoroBreakMinutes,
    required this.focusWarningSeconds,
    required this.themeMode,
    required this.loaded,
  });

  final int minFocusMinutes; // 10-30
  final int maxFocusMinutes; // 60-180
  final int pomodoroWorkMinutes; // 默认 25
  final int pomodoroBreakMinutes; // 默认 5
  final int focusWarningSeconds; // 3-30
  final ThemeMode themeMode; // 浅色/深色/跟随系统
  final bool loaded; // 是否已从本地加载

  SettingsState copyWith({
    int? minFocusMinutes,
    int? maxFocusMinutes,
    int? pomodoroWorkMinutes,
    int? pomodoroBreakMinutes,
    int? focusWarningSeconds,
    ThemeMode? themeMode,
    bool? loaded,
  }) {
    return SettingsState(
      minFocusMinutes: minFocusMinutes ?? this.minFocusMinutes,
      maxFocusMinutes: maxFocusMinutes ?? this.maxFocusMinutes,
      pomodoroWorkMinutes: pomodoroWorkMinutes ?? this.pomodoroWorkMinutes,
      pomodoroBreakMinutes: pomodoroBreakMinutes ?? this.pomodoroBreakMinutes,
      focusWarningSeconds: focusWarningSeconds ?? this.focusWarningSeconds,
      themeMode: themeMode ?? this.themeMode,
      loaded: loaded ?? this.loaded,
    );
  }
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  return SettingsController()..ensureLoaded();
});

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController()
      : super(
          const SettingsState(
            minFocusMinutes: 10,
            maxFocusMinutes: 120,
            pomodoroWorkMinutes: 25,
            pomodoroBreakMinutes: 5,
            focusWarningSeconds: 3,
            themeMode: ThemeMode.system,
            loaded: false,
          ),
        );

  SharedPreferences? _prefs;

  static const _kMinFocus = 'min_focus_minutes';
  static const _kMaxFocus = 'max_focus_minutes';
  static const _kPomodoroWork = 'pomodoro_work_minutes';
  static const _kPomodoroBreak = 'pomodoro_break_minutes';
  static const _kFocusWarn = 'focus_warning_seconds';
  static const _kThemeMode = 'theme_mode';

  Future<void> ensureLoaded() async {
    if (state.loaded) return;
    _prefs ??= await SharedPreferences.getInstance();

    final minFocus = _prefs?.getInt(_kMinFocus) ?? state.minFocusMinutes;
    final maxFocus = _prefs?.getInt(_kMaxFocus) ?? state.maxFocusMinutes;
    final work = _prefs?.getInt(_kPomodoroWork) ?? state.pomodoroWorkMinutes;
    final rest = _prefs?.getInt(_kPomodoroBreak) ?? state.pomodoroBreakMinutes;
    final warn = _prefs?.getInt(_kFocusWarn) ?? state.focusWarningSeconds;
    final themeIdx = _prefs?.getInt(_kThemeMode) ?? 0;

    final themeMode = switch (themeIdx) {
      1 => ThemeMode.light,
      2 => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    // 兜底修正范围与关系
    final fixed = _fixRanges(
      minFocusMinutes: minFocus,
      maxFocusMinutes: maxFocus,
      pomodoroWorkMinutes: work,
      pomodoroBreakMinutes: rest,
      focusWarningSeconds: warn,
    );

    state = state.copyWith(
      minFocusMinutes: fixed.minFocusMinutes,
      maxFocusMinutes: fixed.maxFocusMinutes,
      pomodoroWorkMinutes: fixed.pomodoroWorkMinutes,
      pomodoroBreakMinutes: fixed.pomodoroBreakMinutes,
      focusWarningSeconds: fixed.focusWarningSeconds,
      themeMode: themeMode,
      loaded: true,
    );
  }

  Future<void> setMinFocusMinutes(int v) async {
    await ensureLoaded();
    final fixed = _fixRanges(minFocusMinutes: v, maxFocusMinutes: state.maxFocusMinutes);
    state = state.copyWith(
      minFocusMinutes: fixed.minFocusMinutes,
      maxFocusMinutes: fixed.maxFocusMinutes,
    );
    await _prefs?.setInt(_kMinFocus, state.minFocusMinutes);
    await _prefs?.setInt(_kMaxFocus, state.maxFocusMinutes);
  }

  Future<void> setMaxFocusMinutes(int v) async {
    await ensureLoaded();
    final fixed = _fixRanges(minFocusMinutes: state.minFocusMinutes, maxFocusMinutes: v);
    state = state.copyWith(
      minFocusMinutes: fixed.minFocusMinutes,
      maxFocusMinutes: fixed.maxFocusMinutes,
    );
    await _prefs?.setInt(_kMinFocus, state.minFocusMinutes);
    await _prefs?.setInt(_kMaxFocus, state.maxFocusMinutes);
  }

  Future<void> setPomodoroWorkMinutes(int v) async {
    await ensureLoaded();
    final fixed = _fixRanges(pomodoroWorkMinutes: v);
    state = state.copyWith(pomodoroWorkMinutes: fixed.pomodoroWorkMinutes);
    await _prefs?.setInt(_kPomodoroWork, state.pomodoroWorkMinutes);
  }

  Future<void> setPomodoroBreakMinutes(int v) async {
    await ensureLoaded();
    final fixed = _fixRanges(pomodoroBreakMinutes: v);
    state = state.copyWith(pomodoroBreakMinutes: fixed.pomodoroBreakMinutes);
    await _prefs?.setInt(_kPomodoroBreak, state.pomodoroBreakMinutes);
  }

  Future<void> setFocusWarningSeconds(int v) async {
    await ensureLoaded();
    final fixed = _fixRanges(focusWarningSeconds: v);
    state = state.copyWith(focusWarningSeconds: fixed.focusWarningSeconds);
    await _prefs?.setInt(_kFocusWarn, state.focusWarningSeconds);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await ensureLoaded();
    state = state.copyWith(themeMode: mode);
    final idx = switch (mode) {
      ThemeMode.light => 1,
      ThemeMode.dark => 2,
      _ => 0,
    };
    await _prefs?.setInt(_kThemeMode, idx);
  }

  _FixedRanges _fixRanges({
    int? minFocusMinutes,
    int? maxFocusMinutes,
    int? pomodoroWorkMinutes,
    int? pomodoroBreakMinutes,
    int? focusWarningSeconds,
  }) {
    var minF = (minFocusMinutes ?? state.minFocusMinutes).clamp(10, 30);
    var maxF = (maxFocusMinutes ?? state.maxFocusMinutes).clamp(60, 180);
    if (minF >= maxF) {
      // 保证 min < max（简单处理：拉开 10 分钟）
      if (maxF - 10 >= 60) {
        minF = (maxF - 10).clamp(10, 30);
      } else {
        maxF = (minF + 10).clamp(60, 180);
      }
    }

    final work = (pomodoroWorkMinutes ?? state.pomodoroWorkMinutes).clamp(15, 60);
    final rest = (pomodoroBreakMinutes ?? state.pomodoroBreakMinutes).clamp(3, 30);
    final warn = (focusWarningSeconds ?? state.focusWarningSeconds).clamp(3, 30);
    return _FixedRanges(
      minFocusMinutes: minF,
      maxFocusMinutes: maxF,
      pomodoroWorkMinutes: work,
      pomodoroBreakMinutes: rest,
      focusWarningSeconds: warn,
    );
  }
}

class _FixedRanges {
  const _FixedRanges({
    required this.minFocusMinutes,
    required this.maxFocusMinutes,
    required this.pomodoroWorkMinutes,
    required this.pomodoroBreakMinutes,
    required this.focusWarningSeconds,
  });

  final int minFocusMinutes;
  final int maxFocusMinutes;
  final int pomodoroWorkMinutes;
  final int pomodoroBreakMinutes;
  final int focusWarningSeconds;
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text(
              '设置',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            if (!settings.loaded)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左列
            Expanded(
              child: Column(
                children: [
                  _SectionCard(
                    title: '专注时长范围',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LabeledSlider(
                          label: '最短专注时间：${settings.minFocusMinutes} 分钟',
                          value: settings.minFocusMinutes.toDouble(),
                          min: 10,
                          max: 30,
                          divisions: 20,
                          onChanged: (v) => unawaited(controller.setMinFocusMinutes(v.round())),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: '最长专注时间：${settings.maxFocusMinutes} 分钟',
                          value: settings.maxFocusMinutes.toDouble(),
                          min: 60,
                          max: 180,
                          divisions: 120,
                          onChanged: (v) => unawaited(controller.setMaxFocusMinutes(v.round())),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: '主题',
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('系统')),
                        ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                        ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (set) {
                        if (set.isEmpty) return;
                        unawaited(controller.setThemeMode(set.first));
                      },
                      showSelectedIcon: false,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _TagManagerCard(),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // 右列
            Expanded(
              child: Column(
                children: [
                  _SectionCard(
                    title: '番茄钟',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LabeledSlider(
                          label: '工作时长：${settings.pomodoroWorkMinutes} 分钟',
                          value: settings.pomodoroWorkMinutes.toDouble(),
                          min: 15,
                          max: 60,
                          divisions: 45,
                          onChanged: (v) => unawaited(controller.setPomodoroWorkMinutes(v.round())),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: '休息时长：${settings.pomodoroBreakMinutes} 分钟',
                          value: settings.pomodoroBreakMinutes.toDouble(),
                          min: 3,
                          max: 30,
                          divisions: 27,
                          onChanged: (v) => unawaited(controller.setPomodoroBreakMinutes(v.round())),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: '失焦检测（桌面端）',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LabeledSlider(
                          label: '失焦警告延迟：${settings.focusWarningSeconds} 秒',
                          value: settings.focusWarningSeconds.toDouble(),
                          min: 3,
                          max: 30,
                          divisions: 27,
                          onChanged: (v) => unawaited(controller.setFocusWarningSeconds(v.round())),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '失焦超过警告延迟会变灰提示；超过警告延迟 + 7 秒（至少 10 秒）将判定失败。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─── 预设颜色（20个）───────────────────────────────────────────────────────────

const _kPresetColors = <int>[
  0xFFEF5350, // 红
  0xFFEC407A, // 粉
  0xFFFF7043, // 深橙
  0xFFFF9800, // 橙
  0xFFFFCA28, // 黄
  0xFFD4E157, // 黄绿
  0xFF66BB6A, // 绿
  0xFF26A69A, // 青绿
  0xFF26C6DA, // 青
  0xFF29B6F6, // 浅蓝
  0xFF42A5F5, // 蓝
  0xFF5C6BC0, // 靛蓝
  0xFF7E57C2, // 紫
  0xFFAB47BC, // 紫红
  0xFF8D6E63, // 棕
  0xFFB71C1C, // 深红
  0xFF880E4F, // 深粉
  0xFF1B5E20, // 深绿
  0xFF0D47A1, // 深蓝
  0xFF4A148C, // 深紫
];

// ─── 标签管理卡片 ──────────────────────────────────────────────────────────────

class _TagManagerCard extends ConsumerWidget {
  const _TagManagerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsStreamProvider);

    return _SectionCard(
      title: '标签管理',
      child: tagsAsync.when(
        loading: () => const SizedBox(height: 32, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => Text('加载失败：$e'),
        data: (tags) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('暂无标签', style: Theme.of(context).textTheme.bodySmall),
              )
            else
              for (final tag in tags)
                _TagRow(
                  tag: tag,
                  allTags: tags,
                  onDelete: () => unawaited(ref.read(tagRepositoryProvider).deleteTag(tag.id!)),
                ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showTagDialog(context, ref, null, tags),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建标签'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTagDialog(
    BuildContext context,
    WidgetRef ref,
    TagModel? editing,
    List<TagModel> allTags,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _TagDialog(
        editing: editing,
        allTags: allTags,
        tagRepo: ref.read(tagRepositoryProvider),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tag, required this.allTags, required this.onDelete});

  final TagModel tag;
  final List<TagModel> allTags;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(tag.name)),
          Consumer(
            builder: (ctx, ref, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showDialog<void>(
                    context: ctx,
                    builder: (_) => _TagDialog(
                      editing: tag,
                      allTags: allTags,
                      tagRepo: ref.read(tagRepositoryProvider),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 新建/编辑标签 Dialog ──────────────────────────────────────────────────────

class _TagDialog extends StatefulWidget {
  const _TagDialog({
    required this.editing,
    required this.allTags,
    required this.tagRepo,
  });

  final TagModel? editing;
  final List<TagModel> allTags;
  final TagRepository tagRepo;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late final TextEditingController _nameCtrl;
  int? _selectedColor;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.editing?.name ?? '');
    _selectedColor = widget.editing?.colorValue;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Set<int> get _usedColors => widget.allTags
      .where((t) => t.id != widget.editing?.id)
      .map((t) => t.colorValue)
      .toSet();

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '标签名不能为空');
      return;
    }
    if (_selectedColor == null) {
      setState(() => _error = '请选择颜色');
      return;
    }
    try {
      if (widget.editing == null) {
        await widget.tagRepo.addTag(name, _selectedColor!);
      } else {
        await widget.tagRepo.updateTag(widget.editing!.id!, name, _selectedColor!);
      }
      if (mounted) Navigator.of(context).pop();
    } on TagException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usedColors = _usedColors;
    final isEdit = widget.editing != null;

    return AlertDialog(
      title: Text(isEdit ? '编辑标签' : '新建标签'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '标签名'),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 16),
            Text('选择颜色', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kPresetColors.map((c) {
                final disabled = usedColors.contains(c);
                final selected = _selectedColor == c;
                return GestureDetector(
                  onTap: disabled ? null : () => setState(() {
                    _selectedColor = c;
                    _error = null;
                  }),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: disabled ? Colors.grey.shade300 : Color(c),
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2.5)
                          : null,
                    ),
                    child: disabled
                        ? const Icon(Icons.block, size: 14, color: Colors.grey)
                        : null,
                  ),
                );
              }).toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: Text(isEdit ? '保存' : '创建')),
      ],
    );
  }
}
