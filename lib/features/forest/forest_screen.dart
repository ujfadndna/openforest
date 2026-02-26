import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/session.dart';
import '../timer/timer_provider.dart';
import '../timer/tree_painter.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final forestSessionsProvider = FutureProvider<List<FocusSessionModel>>((ref) async {
  ref.watch(timerServiceProvider); // 专注完成后自动刷新
  final repo = ref.read(sessionRepositoryProvider);
  return repo.getAllCompleted();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ForestScreen extends ConsumerWidget {
  const ForestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(forestSessionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text('森林', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              sessionsAsync.whenData((s) => Text(
                    '${s.length} 棵树',
                    style: Theme.of(context).textTheme.bodySmall,
                  )).valueOrNull ??
                  const SizedBox.shrink(),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: sessionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败：$e')),
            data: (sessions) {
              if (sessions.isEmpty) {
                return const Center(
                  child: Text(
                    '完成一次专注，就会种下一棵树。\n坚持下去，这里会长成一片森林。',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return _ForestView(sessions: sessions);
            },
          ),
        ),
      ],
    );
  }
}

// ── ForestView ────────────────────────────────────────────────────────────────

class _ForestView extends StatefulWidget {
  const _ForestView({required this.sessions});
  final List<FocusSessionModel> sessions;

  @override
  State<_ForestView> createState() => _ForestViewState();
}

class _ForestViewState extends State<_ForestView> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<AnimationController> _swayControllers;
  late List<Animation<double>> _progresses;
  late List<Animation<double>> _sways;
  late List<_TreePlacement> _placements;

  @override
  void initState() {
    super.initState();
    _buildAnimations();
  }

  @override
  void didUpdateWidget(_ForestView old) {
    super.didUpdateWidget(old);
    if (old.sessions.length != widget.sessions.length) {
      for (final c in _controllers) c.dispose();
      for (final c in _swayControllers) c.dispose();
      _buildAnimations();
    }
  }

  void _buildAnimations() {
    final n = widget.sessions.length;

    _controllers = List.generate(n, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (mounted) c.forward();
      });
      return c;
    });

    _progresses = _controllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOutCubic))
        .toList();

    // 摇摆动画：保存 controller 引用以便 dispose
    _swayControllers = List.generate(n, (i) => AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 2600 + (i % 5) * 200),
    )..repeat(reverse: true));

    _sways = _swayControllers.map((sway) =>
      Tween<double>(begin: -0.06, end: 0.06).animate(
        CurvedAnimation(parent: sway, curve: Curves.easeInOut),
      ),
    ).toList();

    _placements = _buildPlacements(n);
  }

  List<_TreePlacement> _buildPlacements(int n) {
    final rng = math.Random(42);
    final placements = <_TreePlacement>[];
    // 分层：前景/中景/背景，y 越大越靠前，树越大
    for (var i = 0; i < n; i++) {
      final layer = i % 3; // 0=背景 1=中景 2=前景
      final yBase = switch (layer) {
        0 => 0.35 + rng.nextDouble() * 0.15,
        1 => 0.52 + rng.nextDouble() * 0.15,
        _ => 0.68 + rng.nextDouble() * 0.15,
      };
      final scale = switch (layer) {
        0 => 0.45 + rng.nextDouble() * 0.1,
        1 => 0.60 + rng.nextDouble() * 0.1,
        _ => 0.75 + rng.nextDouble() * 0.12,
      };
      placements.add(_TreePlacement(
        x: 0.04 + rng.nextDouble() * 0.92,
        y: yBase,
        scale: scale,
        seed: rng.nextInt(9999) + 1,
        layer: layer,
      ));
    }
    // 按 y 排序，y 小的先画（背景在后）
    placements.sort((a, b) => a.y.compareTo(b.y));
    return placements;
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final c in _swayControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final skyTop = isDark ? const Color(0xFF1A237E) : const Color(0xFFBBDEFB);
    final skyBot = isDark ? const Color(0xFF263238) : const Color(0xFFE8F5E9);
    final groundColor = isDark ? const Color(0xFF2E7D32) : const Color(0xFF66BB6A);

    return ClipRect(
      child: Stack(
        children: [
          // 天空渐变背景
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [skyTop, skyBot],
                ),
              ),
            ),
          ),
          // 地面
          Positioned(
            left: 0, right: 0, bottom: 0,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [groundColor.withOpacity(0.0), groundColor],
                ),
              ),
            ),
          ),
          // 树
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final n = widget.sessions.length;

              return Stack(
                children: [
                  for (var i = 0; i < n; i++)
                    _buildTree(i, w, h),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTree(int i, double w, double h) {
    final session = widget.sessions[i];
    final p = _placements[i];
    final treeSize = w * 0.22 * p.scale;
    final left = w * p.x - treeSize / 2;
    final top = h * p.y - treeSize * 0.85;

    return Positioned(
      left: left,
      top: top,
      width: treeSize,
      height: treeSize,
      child: AnimatedBuilder(
        animation: Listenable.merge([_progresses[i], _sways[i]]),
        builder: (_, __) => CustomPaint(
          painter: TreePainter(
            progress: _progresses[i].value,
            state: TreeVisualState.completed,
            speciesId: session.treeSpecies,
            seed: p.seed,
            swayAngle: _sways[i].value,
          ),
        ),
      ),
    );
  }
}

class _TreePlacement {
  const _TreePlacement({
    required this.x,
    required this.y,
    required this.scale,
    required this.seed,
    required this.layer,
  });

  final double x;     // 0.0 ~ 1.0，相对宽度
  final double y;     // 0.0 ~ 1.0，相对高度（树根位置）
  final double scale; // 树的大小系数
  final int seed;
  final int layer;    // 0=背景 1=中景 2=前景
}
