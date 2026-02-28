import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 叶子归一化位置缓存：key="$speciesId-$seed"，value=以 start 为原点、branchBaseLen 为单位的偏移列表
/// 森林页所有完成树 progress=1.0，形状固定，可安全缓存
final Map<String, List<Offset>> kLeafOffsetCache = {};

/// 树的视觉状态
enum TreeVisualState {
  growing,
  withering,
  dead,
  completed,
}

/// 每个树种的视觉参数
class TreeStyle {
  const TreeStyle({
    required this.trunkColor,
    required this.leafColor,
    this.leafHighlightColor = const Color(0x00FFFFFF),
    required this.spread,
    required this.trunkWidthRatio,
    required this.leafRadiusRatio,
    this.trunkHeightRatio = 1.0, // 相对松树的现实高度倍率
    this.crownRatio = 1.0, // 树冠枝条基准长度倍率
    this.isBamboo = false,
    this.leafOpacity = 0.92,
  });

  final Color trunkColor;
  final Color leafColor;
  final Color leafHighlightColor;
  final double spread;
  final double trunkWidthRatio;
  final double leafRadiusRatio;
  final double trunkHeightRatio;
  final double crownRatio;
  final bool isBamboo;
  final double leafOpacity;
}

const _kStyles = <String, TreeStyle>{
  // 橡树 ~22 m：中等高度，宽圆冠
  'oak': TreeStyle(
    trunkColor: Color(0xFF8D7B74),
    leafColor: Color(0xFF7A9E7E),
    leafHighlightColor: Color(0x00000000),
    spread: 0.60,
    trunkWidthRatio: 0.065,
    leafRadiusRatio: 0.022,
    trunkHeightRatio: 0.80,
    crownRatio: 1.20,
  ),
  // 松树 ~30 m：最高，窄锥形冠
  'pine': TreeStyle(
    trunkColor: Color(0xFF6B5550),
    leafColor: Color(0xFF4A7A52),
    leafHighlightColor: Color(0xFFA5D6A7),
    spread: 0.32,
    trunkWidthRatio: 0.048,
    leafRadiusRatio: 0.016,
    leafOpacity: 0.95,
    trunkHeightRatio: 1.0,
    crownRatio: 0.65,
  ),
  // 樱花 ~9 m：矮，短干宽伞冠（标志性矮宽）
  'cherry': TreeStyle(
    trunkColor: Color(0xFF9E8880),
    leafColor: Color(0xFFC4899E),
    leafHighlightColor: Color(0xFFFCE4EC),
    spread: 0.68,
    trunkWidthRatio: 0.055,
    leafRadiusRatio: 0.028,
    leafOpacity: 0.88,
    trunkHeightRatio: 0.48,
    crownRatio: 1.6,
  ),
  // 竹 ~18 m：高而极细，小顶冠
  'bamboo': TreeStyle(
    trunkColor: Color(0xFF7E9160),
    leafColor: Color(0xFF8EAA72),
    leafHighlightColor: Color(0xFFDCEDC8),
    spread: 0.22,
    trunkWidthRatio: 0.045,
    leafRadiusRatio: 0.018,
    isBamboo: true,
    trunkHeightRatio: 0.70,
  ),
  // 枫树 ~15 m：中等，宽展冠
  'maple': TreeStyle(
    trunkColor: Color(0xFF8D7063),
    leafColor: Color(0xFFC47A5A),
    leafHighlightColor: Color(0xFFFFE0B2),
    spread: 0.68,
    trunkWidthRatio: 0.062,
    leafRadiusRatio: 0.024,
    leafOpacity: 0.90,
    trunkHeightRatio: 0.63,
    crownRatio: 1.30,
  ),
  // 白杨 ~27 m：高挺，极窄柱状冠（标志性）
  'poplar': TreeStyle(
    trunkColor: Color(0xFFA8A8A8),
    leafColor: Color(0xFF90AE92),
    leafHighlightColor: Color(0xFFE8F5E9),
    spread: 0.22,
    trunkWidthRatio: 0.048,
    leafRadiusRatio: 0.020,
    trunkHeightRatio: 0.93,
    crownRatio: 0.55,
  ),
  // 柳树 ~12 m：矮干宽冠，淡黄绿垂柳色
  'willow': TreeStyle(
    trunkColor: Color(0xFF8FA4AD),
    leafColor: Color(0xFFA0B88A),
    leafHighlightColor: Color(0xFFF1F8E9),
    spread: 0.72,
    trunkWidthRatio: 0.055,
    leafRadiusRatio: 0.018,
    leafOpacity: 0.90,
    trunkHeightRatio: 0.55,
    crownRatio: 1.20,
  ),
  // 银杏 ~24 m：中高，锥形偏窄冠
  'ginkgo': TreeStyle(
    trunkColor: Color(0xFF9A8070),
    leafColor: Color(0xFFC9A84C),
    leafHighlightColor: Color(0xFFFFFDE7),
    spread: 0.42,
    trunkWidthRatio: 0.060,
    leafRadiusRatio: 0.025,
    trunkHeightRatio: 0.85,
    crownRatio: 0.88,
  ),
  // 梅花 ~6 m：最矮，稀疏小冠，老枝苍劲
  'plum': TreeStyle(
    trunkColor: Color(0xFF8D7B74),
    leafColor: Color(0xFFB8899E),
    leafHighlightColor: Color(0xFFFCE4EC),
    spread: 0.50,
    trunkWidthRatio: 0.055,
    leafRadiusRatio: 0.020,
    leafOpacity: 0.88,
    trunkHeightRatio: 0.40,
    crownRatio: 0.75,
  ),
  // 榕树 ~20 m：中等高度，最宽最大冠幅
  'banyan': TreeStyle(
    trunkColor: Color(0xFF7A6259),
    leafColor: Color(0xFF527A5A),
    leafHighlightColor: Color(0xFFA5D6A7),
    spread: 0.80,
    trunkWidthRatio: 0.075,
    leafRadiusRatio: 0.025,
    trunkHeightRatio: 0.75,
    crownRatio: 1.80,
  ),
};

TreeStyle treeStyleFor(String speciesId) =>
    _kStyles[speciesId] ?? _kStyles['oak']!;

/// CustomPainter：树生长动画
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
  final double swayAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    final nowT = (DateTime.now().millisecondsSinceEpoch % 2000) / 2000.0;
    final style = treeStyleFor(speciesId);

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
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, groundY + 6),
        width: size.width * 0.38,
        height: 13,
      ),
      shadowPaint,
    );

    if (style.isBamboo) {
      _drawBamboo(canvas, size, p, trunkColor, leafColor, centerX, groundY,
          nowT, style.trunkHeightRatio);
      return;
    }

    // 树干（高度按树种现实比例缩放）
    final trunkWidth = size.width * style.trunkWidthRatio;
    final maxTrunkHeight = size.height * 0.52 * style.trunkHeightRatio;
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
        size.width * 0.15,
        Paint()
          ..color = const Color(0xFFE8C97A).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
      );
    }

    // 树枝（带摇摆，枝长按树冠倍率缩放）
    final maxDepth = speciesId == 'pine' ? 7 : 6;
    final rng = math.Random(seed);
    final branchBaseLen = size.height * 0.17 * style.crownRatio;
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
      // 尝试从缓存获取归一化叶子偏移，完成树（progress=1.0）形状固定可复用
      final cacheKey = '$speciesId-$seed';
      List<Offset> leaves;
      final cached = kLeafOffsetCache[cacheKey];
      if (cached != null) {
        // 将归一化偏移还原为当前尺寸下的绝对坐标
        leaves = cached
            .map((n) => Offset(
                  start.dx + n.dx * branchBaseLen,
                  start.dy + n.dy * branchBaseLen,
                ))
            .toList(growable: false);
      } else {
        final raw = <Offset>[];
        _collectLeafPoints(
          start: start,
          length: branchBaseLen,
          angle: -math.pi / 2,
          depth: 0,
          maxDepth: maxDepth,
          progress: p,
          rng: math.Random(seed),
          out: raw,
          spread: style.spread,
        );
        leaves = raw;
        // 仅在 progress≈1.0 时缓存（森林页，形状稳定）
        if (branchBaseLen > 0 && p > 0.99) {
          kLeafOffsetCache[cacheKey] = raw
              .map((pt) => Offset(
                    (pt.dx - start.dx) / branchBaseLen,
                    (pt.dy - start.dy) / branchBaseLen,
                  ))
              .toList(growable: false);
        }
      }

      final appearT = ((p - 0.28) / 0.72).clamp(0.0, 1.0);
      final leafRadius = size.shortestSide * style.leafRadiusRatio;
      final leafPaint = Paint()
        ..color = leafColor.withValues(alpha: style.leafOpacity);

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
          leafPaint..color = leafColor.withValues(alpha: alpha),
        );
      }
    }

    canvas.restore();
  }

  void _drawBamboo(
    Canvas canvas,
    Size size,
    double p,
    Color trunkColor,
    Color leafColor,
    double centerX,
    double groundY,
    double nowT,
    double trunkHeightRatio,
  ) {
    final trunkWidth = size.width * 0.045;
    final maxHeight = size.height * 0.70 * trunkHeightRatio * (0.15 + 0.85 * p);
    const segmentCount = 6;
    final segH = maxHeight / segmentCount;
    final segmentGradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [trunkColor, trunkColor.withValues(alpha: 0.8)],
    );
    final nodePaint = Paint()..color = const Color(0x33FFFFFF);

    canvas.save();
    canvas.translate(centerX, groundY);
    canvas.rotate(swayAngle * 0.7);

    for (var i = 0; i < segmentCount; i++) {
      final y0 = -i * segH;
      final y1 = -(i + 1) * segH;
      if (y1 > 0) continue;
      final segmentRect =
          Rect.fromLTRB(-trunkWidth / 2, y1, trunkWidth / 2, y0);
      final segmentPaint = Paint()
        ..shader = segmentGradient.createShader(segmentRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(segmentRect, Radius.circular(trunkWidth * 0.3)),
        segmentPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(-trunkWidth / 2 - 1, y0 - 2, trunkWidth + 2, 4),
        nodePaint,
      );
    }

    if (p > 0.3 && state != TreeVisualState.dead) {
      final appearT = ((p - 0.3) / 0.7).clamp(0.0, 1.0);
      final topY = -maxHeight;
      final rng = math.Random(seed);
      for (var i = 0; i < 12; i++) {
        final angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * math.pi * 1.2;
        final len = size.width * (0.12 + rng.nextDouble() * 0.10);
        final drop = state == TreeVisualState.withering ? 8 * nowT : 0.0;
        final ex = math.cos(angle) * len;
        final ey = math.sin(angle) * len + drop;
        final leafAlpha = ((0.5 + 0.5 * (i / 12)) * appearT).clamp(0.0, 1.0);
        final leafStrokeWidth = 2 + rng.nextDouble() * 2;
        canvas.drawLine(
          Offset(0, topY),
          Offset(ex, topY + ey),
          Paint()
            ..color = leafColor.withValues(alpha: leafAlpha.toDouble())
            ..strokeWidth = leafStrokeWidth
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    canvas.restore();
  }

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

    final effectiveLen =
        length * (0.85 + 0.15 * progress) * math.pow(0.72, depth).toDouble();
    final dx = math.cos(angle) * effectiveLen;
    final dy = math.sin(angle) * effectiveLen;
    final end = Offset(start.dx + dx, start.dy + dy);

    final width = (6.0 * math.pow(0.72, depth)).clamp(1.5, 6.0).toDouble();
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = trunkColor.withValues(alpha: 0.95)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );

    if (depth >= maxDepth) return;

    final jitter = (rng.nextDouble() - 0.5) * 0.25;
    _drawBranch(
      canvas: canvas,
      start: end,
      length: length,
      angle: angle - spread + jitter,
      depth: depth + 1,
      maxDepth: maxDepth,
      progress: progress,
      rng: rng,
      trunkColor: trunkColor,
      spread: spread,
    );
    _drawBranch(
      canvas: canvas,
      start: end,
      length: length,
      angle: angle + spread + jitter,
      depth: depth + 1,
      maxDepth: maxDepth,
      progress: progress,
      rng: rng,
      trunkColor: trunkColor,
      spread: spread,
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
      start: end,
      length: length,
      angle: angle - spread + jitter,
      depth: depth + 1,
      maxDepth: maxDepth,
      progress: progress,
      rng: rng,
      out: out,
      spread: spread,
    );
    _collectLeafPoints(
      start: end,
      length: length,
      angle: angle + spread + jitter,
      depth: depth + 1,
      maxDepth: maxDepth,
      progress: progress,
      rng: rng,
      out: out,
      spread: spread,
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
    this.windFactor = 0.0,
  });

  final double progress;
  final TreeVisualState state;
  final int seed;
  final String speciesId;

  /// 风力倍率（0.0=无风，1.0=强风，2.0=暴风）
  final double windFactor;

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
      duration: const Duration(milliseconds: 4200),
    )..repeat(reverse: true);

    _sway = Tween<double>(begin: -0.028, end: 0.028).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
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
          swayAngle: widget.state == TreeVisualState.dead
              ? 0.0
              : _sway.value * (1.0 + widget.windFactor * 2.0),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}


