import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 树的视觉状态
enum TreeVisualState {
  growing,
  withering,
  dead,
  completed,
}

/// 每个树种的视觉参数
class _TreeStyle {
  const _TreeStyle({
    required this.trunkColor,
    required this.leafColor,
    required this.spread,
    required this.trunkWidthRatio,
    required this.leafRadiusRatio,
    this.isBamboo = false,
    this.leafOpacity = 0.92,
  });

  final Color trunkColor;
  final Color leafColor;
  final double spread;        // 分叉角度（弧度）
  final double trunkWidthRatio;
  final double leafRadiusRatio;
  final bool isBamboo;
  final double leafOpacity;
}

const _kStyles = <String, _TreeStyle>{
  'oak': _TreeStyle(
    trunkColor: Color(0xFF5D4037),
    leafColor: Color(0xFF43A047),
    spread: 0.55,
    trunkWidthRatio: 0.065,
    leafRadiusRatio: 0.022,
  ),
  'pine': _TreeStyle(
    trunkColor: Color(0xFF4E342E),
    leafColor: Color(0xFF1B5E20),
    spread: 0.32,
    trunkWidthRatio: 0.048,
    leafRadiusRatio: 0.016,
    leafOpacity: 0.95,
  ),
  'cherry': _TreeStyle(
    trunkColor: Color(0xFF8D6E63),
    leafColor: Color(0xFFE91E63),
    spread: 0.65,
    trunkWidthRatio: 0.055,
    leafRadiusRatio: 0.026,
    leafOpacity: 0.88,
  ),
  'bamboo': _TreeStyle(
    trunkColor: Color(0xFF558B2F),
    leafColor: Color(0xFF8BC34A),
    spread: 0.22,
    trunkWidthRatio: 0.045,
    leafRadiusRatio: 0.018,
    isBamboo: true,
  ),
  'maple': _TreeStyle(
    trunkColor: Color(0xFF4E342E),
    leafColor: Color(0xFFFF5722),
    spread: 0.68,
    trunkWidthRatio: 0.062,
    leafRadiusRatio: 0.024,
    leafOpacity: 0.90,
  ),
};

_TreeStyle _styleFor(String speciesId) =>
    _kStyles[speciesId] ?? _kStyles['oak']!;

/// CustomPainter：树生长动画
///
/// - [progress]: 0.0 ~ 1.0
/// - [state]: growing / withering / dead / completed
/// - [speciesId]: oak / pine / cherry / bamboo / maple
/// - [swayAngle]: 摇摆偏移角度（弧度，由外部动画驱动）
class TreePainter extends CustomPainter {
  TreePainter({
    required this.progress,
    required this.state,
    this.seed = 1,
    this.speciesId = 'oak',
    this.swayAngle = 0.0,
  });

  final double progress;
  final TreeVisualState state;
  final int seed;
  final String speciesId;
  final double swayAngle; // -0.08 ~ 0.08 弧度

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    final nowT = (DateTime.now().millisecondsSinceEpoch % 2000) / 2000.0;
    final style = _styleFor(speciesId);

    // 枯萎/死亡时覆盖颜色
    final trunkColor = switch (state) {
      TreeVisualState.withering => const Color(0xFF8D6E63),
      TreeVisualState.dead => const Color(0xFF5D4037),
      _ => style.trunkColor,
    };
    final leafColor = switch (state) {
      TreeVisualState.withering => const Color(0xFF9E9E9E),
      TreeVisualState.dead => const Color(0xFF757575),
      _ => style.leafColor,
    };

    final centerX = size.width / 2;
    final groundY = size.height * 0.92;

    // 地面阴影
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(state == TreeVisualState.completed ? 0.15 : 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, groundY + 6),
        width: size.width * 0.35,
        height: 18,
      ),
      shadowPaint,
    );

    if (style.isBamboo) {
      _drawBamboo(canvas, size, p, trunkColor, leafColor, centerX, groundY, nowT);
      return;
    }

    // 树干
    final trunkWidth = size.width * style.trunkWidthRatio;
    final maxTrunkHeight = size.height * 0.52;
    final trunkHeight = maxTrunkHeight * (0.15 + 0.85 * p);

    final trunkRect = Rect.fromLTWH(
      centerX - trunkWidth / 2,
      groundY - trunkHeight,
      trunkWidth,
      trunkHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(trunkRect, Radius.circular(trunkWidth / 2)),
      Paint()..color = trunkColor,
    );

    // 完成光晕
    if (state == TreeVisualState.completed) {
      canvas.drawCircle(
        Offset(centerX, groundY - trunkHeight),
        size.width * 0.18,
        Paint()
          ..color = const Color(0xFFFFD54F).withOpacity(0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
      );
    }

    // 树枝（带摇摆）
    final maxDepth = speciesId == 'pine' ? 7 : 6;
    final rng = math.Random(seed);
    final branchBaseLen = size.height * 0.17;
    final start = Offset(centerX, groundY - trunkHeight);

    canvas.save();
    canvas.translate(centerX, groundY - trunkHeight);
    canvas.rotate(swayAngle);
    canvas.translate(-centerX, -(groundY - trunkHeight));

    _drawBranch(
      canvas: canvas,
      start: start,
      length: branchBaseLen,
      angle: -math.pi / 2,
      depth: 0,
      maxDepth: maxDepth,
      progress: p,
      rng: rng,
      trunkColor: trunkColor,
      spread: style.spread,
    );

    // 叶子
    if (p > 0.28 && state != TreeVisualState.dead) {
      final leaves = <Offset>[];
      _collectLeafPoints(
        start: start,
        length: branchBaseLen,
        angle: -math.pi / 2,
        depth: 0,
        maxDepth: maxDepth,
        progress: p,
        rng: math.Random(seed),
        out: leaves,
        spread: style.spread,
      );

      final appearT = ((p - 0.28) / 0.72).clamp(0.0, 1.0);
      final leafRadius = size.shortestSide * style.leafRadiusRatio;
      final leafPaint = Paint()..color = leafColor.withOpacity(style.leafOpacity);

      for (var i = 0; i < leaves.length; i++) {
        final pt = leaves[i];
        final drop = switch (state) {
          TreeVisualState.withering => 10 + 28 * nowT,
          _ => 0.0,
        };
        final jitterX = math.sin(i * 1.7 + nowT * math.pi * 2) * 2.5;
        final alpha = (0.35 + 0.65 * appearT) * style.leafOpacity;
        canvas.drawCircle(
          Offset(pt.dx + jitterX, pt.dy + drop),
          leafRadius * (0.55 + 0.45 * appearT),
          leafPaint..color = leafColor.withOpacity(alpha),
        );
      }
    }

    canvas.restore();
  }

  // ── 竹子专用绘制 ────────────────────────────────────────────────────────────

  void _drawBamboo(
    Canvas canvas,
    Size size,
    double p,
    Color trunkColor,
    Color leafColor,
    double centerX,
    double groundY,
    double nowT,
  ) {
    final trunkWidth = size.width * 0.045;
    final maxHeight = size.height * 0.70 * (0.15 + 0.85 * p);
    final segmentCount = 6;
    final segH = maxHeight / segmentCount;
    final paint = Paint()..color = trunkColor;
    final nodePaint = Paint()..color = trunkColor.withOpacity(0.6);

    canvas.save();
    canvas.translate(centerX, groundY);
    canvas.rotate(swayAngle * 0.7);

    for (var i = 0; i < segmentCount; i++) {
      final y0 = -i * segH;
      final y1 = -(i + 1) * segH;
      if (y1 > 0) continue;
      canvas.drawRRect(
        RRect.fromLTRBR(
          -trunkWidth / 2, y1, trunkWidth / 2, y0,
          Radius.circular(trunkWidth * 0.3),
        ),
        paint,
      );
      // 节点
      canvas.drawRect(
        Rect.fromLTWH(-trunkWidth / 2 - 2, y0 - 3, trunkWidth + 4, 5),
        nodePaint,
      );
    }

    // 竹叶（顶部）
    if (p > 0.3 && state != TreeVisualState.dead) {
      final appearT = ((p - 0.3) / 0.7).clamp(0.0, 1.0);
      final leafPaint = Paint()..color = leafColor.withOpacity(0.88 * appearT);
      final topY = -maxHeight;
      final rng = math.Random(seed);
      for (var i = 0; i < 8; i++) {
        final angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * math.pi * 1.2;
        final len = size.width * (0.12 + rng.nextDouble() * 0.10);
        final drop = state == TreeVisualState.withering ? 8 * nowT : 0.0;
        final ex = math.cos(angle) * len;
        final ey = math.sin(angle) * len + drop;
        canvas.drawLine(
          Offset(0, topY),
          Offset(ex, topY + ey),
          leafPaint..strokeWidth = 3..strokeCap = StrokeCap.round,
        );
      }
    }

    canvas.restore();
  }

  // ── 通用树枝递归 ─────────────────────────────────────────────────────────────

  void _drawBranch({
    required Canvas canvas,
    required Offset start,
    required double length,
    required double angle,
    required int depth,
    required int maxDepth,
    required double progress,
    required math.Random rng,
    required Color trunkColor,
    required double spread,
  }) {
    final threshold = depth <= 1
        ? depth * 0.08
        : 0.16 + (depth - 2) * (0.84 / (maxDepth - 1));
    if (progress < threshold) return;

    final effectiveLen = length * (0.85 + 0.15 * progress) * math.pow(0.72, depth).toDouble();
    final dx = math.cos(angle) * effectiveLen;
    final dy = math.sin(angle) * effectiveLen;
    final end = Offset(start.dx + dx, start.dy + dy);

    final width = (6.0 * math.pow(0.72, depth)).clamp(1.5, 6.0).toDouble();
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = trunkColor.withOpacity(0.95)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );

    if (depth >= maxDepth) return;

    final jitter = (rng.nextDouble() - 0.5) * 0.25;
    _drawBranch(
      canvas: canvas, start: end, length: length,
      angle: angle - spread + jitter, depth: depth + 1,
      maxDepth: maxDepth, progress: progress, rng: rng,
      trunkColor: trunkColor, spread: spread,
    );
    _drawBranch(
      canvas: canvas, start: end, length: length,
      angle: angle + spread + jitter, depth: depth + 1,
      maxDepth: maxDepth, progress: progress, rng: rng,
      trunkColor: trunkColor, spread: spread,
    );
  }

  void _collectLeafPoints({
    required Offset start,
    required double length,
    required double angle,
    required int depth,
    required int maxDepth,
    required double progress,
    required math.Random rng,
    required List<Offset> out,
    required double spread,
  }) {
    final threshold = depth <= 1
        ? depth * 0.08
        : 0.16 + (depth - 2) * (0.84 / (maxDepth - 1));
    if (progress < threshold) return;

    final effectiveLen = length * math.pow(0.72, depth).toDouble();
    final end = Offset(
      start.dx + math.cos(angle) * effectiveLen,
      start.dy + math.sin(angle) * effectiveLen,
    );

    if (depth >= maxDepth - 1) {
      out.add(end);
      return;
    }

    final jitter = (rng.nextDouble() - 0.5) * 0.25;
    _collectLeafPoints(
      start: end, length: length, angle: angle - spread + jitter,
      depth: depth + 1, maxDepth: maxDepth, progress: progress,
      rng: rng, out: out, spread: spread,
    );
    _collectLeafPoints(
      start: end, length: length, angle: angle + spread + jitter,
      depth: depth + 1, maxDepth: maxDepth, progress: progress,
      rng: rng, out: out, spread: spread,
    );
  }

  @override
  bool shouldRepaint(covariant TreePainter old) {
    if (state == TreeVisualState.withering) return true;
    return old.progress != progress ||
        old.state != state ||
        old.seed != seed ||
        old.speciesId != speciesId ||
        old.swayAngle != swayAngle;
  }
}

/// 带摇摆动效的树 Widget
class AnimatedTree extends StatefulWidget {
  const AnimatedTree({
    super.key,
    required this.progress,
    required this.state,
    this.seed = 1,
    this.speciesId = 'oak',
  });

  final double progress;
  final TreeVisualState state;
  final int seed;
  final String speciesId;

  @override
  State<AnimatedTree> createState() => _AnimatedTreeState();
}

class _AnimatedTreeState extends State<AnimatedTree>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _sway;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _sway = Tween<double>(begin: -0.04, end: 0.04).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sway,
      builder: (_, __) => CustomPaint(
        painter: TreePainter(
          progress: widget.progress,
          state: widget.state,
          seed: widget.seed,
          speciesId: widget.speciesId,
          swayAngle: widget.state == TreeVisualState.dead ? 0.0 : _sway.value,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
