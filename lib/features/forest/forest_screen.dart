import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/session.dart';
import '../timer/timer_provider.dart';
import '../timer/tree_painter.dart';
import '../weather/weather_overlay.dart';
import '../weather/weather_provider.dart';
import '../weather/weather_selector.dart';
import '../weather/weather_type.dart';

const _kPixelsPerHour = 80.0; // x轴：每小时宽度
const _kRowHeight = 60.0; // y轴：每日行高
const _kYAxisWidth = 72.0; // Y轴标签面板宽度（固定）
const _kXAxisHeight = 36.0; // X轴标签面板高度（固定）
const _kJitterX = 18.0; // 时间抖动（像素）
const _kJitterY = 18.0; // 日期行内垂直抖动（像素）
const _kCanvasTopPadding = 50.0; // 画布顶部留白，防止远处树木被裁剪
const _kCanvasLeftPadding = 80.0; // 画布左侧留白，防止深夜/凌晨树木被裁剪

// ── Provider ──────────────────────────────────────────────────────────────────

final forestSessionsProvider =
    FutureProvider<List<FocusSessionModel>>((ref) async {
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
              sessionsAsync
                      .whenData((s) => Text(
                            '${s.length} 棵树',
                            style: Theme.of(context).textTheme.bodySmall,
                          ))
                      .valueOrNull ??
                  const SizedBox.shrink(),
              const WeatherSelector(),
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
              final weather = ref.watch(effectiveWeatherProvider);
              return _ForestView(sessions: sessions, weather: weather);
            },
          ),
        ),
      ],
    );
  }
}

// ── ForestView ────────────────────────────────────────────────────────────────

class _ForestView extends StatefulWidget {
  const _ForestView({required this.sessions, required this.weather});
  final List<FocusSessionModel> sessions;
  final WeatherType weather;

  @override
  State<_ForestView> createState() => _ForestViewState();
}

class _ForestViewState extends State<_ForestView>
    with TickerProviderStateMixin {
  static const _swayRatio = 0.30; // 30% 的树摇摆

  late AnimationController _globalSwayCtrl;
  late List<double> _phaseOffsets;
  late List<double> _swayAmplitudes;
  late List<bool> _isSway;
  int? _hoveredIndex;

  late TransformationController _transformCtrl;
  late List<DateTime> _sortedDates;
  DateTime? _selectedDate;
  bool _viewInitialized = false;
  // 缓存 viewport 尺寸，供 postFrameCallback 使用
  double _cachedViewportW = 0;
  double _cachedViewportH = 0;

  late List<_TreePlacement> _placements;
  late List<int> _sortedIndices;
  late List<int> _staticSortedIndices; // 无摇摆树（70%），仅在视口变化时重建
  late List<int> _swaySortedIndices; // 摇摆树（30%），每帧重建

  // 环境粒子
  late AnimationController _ambientCtrl;
  late List<_AmbientParticle> _ambientParticles;

  void _onTransformChanged() {
    if (_hoveredIndex != null) {
      setState(() => _hoveredIndex = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _transformCtrl = TransformationController();
    _buildAnimations(); // 内部会调用 _buildPlacements，从而构建 _sortedDates
    _selectedDate = _resolveInitialDate();
  }

  @override
  void didUpdateWidget(_ForestView old) {
    super.didUpdateWidget(old);
    if (old.sessions.length != widget.sessions.length) {
      _globalSwayCtrl.dispose();
      _buildAnimations();
      if (_selectedDate != null && !_sortedDates.contains(_selectedDate)) {
        _selectedDate = _resolveInitialDate();
      }
    }
  }

  void _buildAnimations() {
    final n = widget.sessions.length;
    final rng = math.Random(12345);

    final swayCount = (n * _swayRatio).round();
    final swayIndices = <int>{};
    while (swayIndices.length < swayCount && swayIndices.length < n) {
      swayIndices.add(rng.nextInt(n));
    }

    _isSway = List.generate(n, (i) => swayIndices.contains(i));
    _phaseOffsets = List.generate(n, (_) => rng.nextDouble());
    _swayAmplitudes = List.generate(
      n,
      (i) => _isSway[i] ? 0.04 + rng.nextDouble() * 0.03 : 0.0,
    );

    _globalSwayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _transformCtrl
      ..removeListener(_onTransformChanged)
      ..addListener(_onTransformChanged);

    _hoveredIndex = null;
    _placements = _buildPlacements(widget.sessions);
    _sortedIndices = List.generate(n, (i) => i)
      ..sort((a, b) => _placements[a].y.compareTo(_placements[b].y));
    _staticSortedIndices = _sortedIndices.where((i) => !_isSway[i]).toList();
    _swaySortedIndices = _sortedIndices.where((i) => _isSway[i]).toList();

    // 环境粒子
    final arng = math.Random(777);
    _ambientParticles = List.generate(18, (_) => _AmbientParticle(
      x: arng.nextDouble(),
      y: arng.nextDouble(),
      speed: 0.08 + arng.nextDouble() * 0.12,
      size: 1.2 + arng.nextDouble() * 1.4,
      phase: arng.nextDouble(),
    ));
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  // 透视行 y 坐标公式（统一出口，避免各处重复计算）
  double _perspectiveRowY(int dateIndex, int numDates) {
    final t = numDates > 1
        ? (numDates - 1 - dateIndex) / (numDates - 1).toDouble()
        : 1.0;
    // t=1(最新/近)→ 画布底部; t=0(最旧/远)→ _kCanvasTopPadding 处
    return _kCanvasTopPadding +
        numDates.toDouble() * _kRowHeight * math.pow(t, 2.0);
  }

  List<_TreePlacement> _buildPlacements(List<FocusSessionModel> sessions) {
    final n = sessions.length;
    final rng = math.Random(42);

    // 1. 按日期分组（normalize 到 midnight）
    final dateSet = <DateTime>{};
    for (final s in sessions) {
      final d = DateTime(s.startTime.year, s.startTime.month, s.startTime.day);
      dateSet.add(d);
    }

    // 2. 降序排列（最近日期 index=0）
    _sortedDates = dateSet.toList()..sort((a, b) => b.compareTo(a));
    final numDates = _sortedDates.length;

    const virtualW = 24.0 * _kPixelsPerHour;

    final placements = <_TreePlacement>[];
    for (var i = 0; i < n; i++) {
      final st = sessions[i].startTime;
      final hour = st.hour + st.minute / 60.0;
      final jitterX = (rng.nextDouble() - 0.5) * 2 * _kJitterX;
      final x = (_kCanvasLeftPadding + hour / 24.0 * virtualW + jitterX)
          .clamp(0.0, virtualW + _kCanvasLeftPadding);

      final date = DateTime(st.year, st.month, st.day);
      final dateIndex = _sortedDates.indexOf(date);
      final perspectiveT = numDates > 1
          ? (numDates - 1 - dateIndex) / (numDates - 1).toDouble()
          : 1.0;
      final rowBaseY = _perspectiveRowY(dateIndex, numDates);
      final rowScale = ui.lerpDouble(0.30, 1.0, perspectiveT)!;
      final localVariance = (rng.nextDouble() - 0.5) * 0.10;
      final scale = (rowScale + localVariance).clamp(0.20, 1.1);
      final depthOpacity = ui.lerpDouble(0.55, 1.0, perspectiveT)!;

      final effectiveJitter = _kJitterY * math.max(perspectiveT, 0.15);
      final jitterY = (rng.nextDouble() - 0.5) * effectiveJitter;
      final y = rowBaseY + jitterY;

      placements.add(_TreePlacement(
        x: x,
        y: y,
        scale: scale,
        seed: rng.nextInt(9999) + 1,
        dateIndex: dateIndex,
        depthOpacity: depthOpacity,
      ));
    }
    return placements;
  }

  DateTime? _resolveInitialDate() {
    if (_sortedDates.isEmpty) return null;
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    if (_sortedDates.contains(todayMidnight)) return todayMidnight;
    return _sortedDates.first; // 最近有记录的日期
  }

  @override
  void dispose() {
    _globalSwayCtrl.dispose();
    _ambientCtrl.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final skyColors = isDark
        ? const [Color(0xFF0D1B2A), Color(0xFF162535), Color(0xFF2C1A0E), Color(0xFF120905)]
        : const [Color(0xFFD6EAF8), Color(0xFFFDEBD0), Color(0xFFD4A574), Color(0xFF8B5E3C)];
    const skyStops = [0.0, 0.38, 0.72, 1.0];

    const virtualW = 24.0 * _kPixelsPerHour;
    const canvasW = virtualW + _kCanvasLeftPadding;
    final virtualH = math.max(1, _sortedDates.length).toDouble() * _kRowHeight +
        _kCanvasTopPadding;

    return WeatherOverlay(
      weather: widget.weather,
      child: ClipRect(
        child: Stack(
          children: [
            // 土壤渐变（固定背景）
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: skyColors,
                    stops: skyStops,
                  ),
                ),
              ),
            ),

            // 主画布区域（左侧留出Y轴，底部留出X轴）
            Positioned(
              left: _kYAxisWidth,
              top: 0,
              right: 0,
              bottom: _kXAxisHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportW = constraints.maxWidth;
                  final viewportH = constraints.maxHeight;

                  // 缓存 viewport 尺寸
                  if (_cachedViewportW != viewportW ||
                      _cachedViewportH != viewportH) {
                    _cachedViewportW = viewportW;
                    _cachedViewportH = viewportH;
                  }

                  // 首次 build 时设定初始变换（滚动到选中日期+当前时刻）
                  // 直接捕获当前帧的 viewportW/H，避免依赖缓存导致滚动失效
                  if (!_viewInitialized && _sortedDates.isNotEmpty &&
                      viewportW > 0 && viewportH > 0) {
                    _viewInitialized = true;
                    final capturedW = viewportW;
                    final capturedH = viewportH;
                    const capturedCanvasW = canvasW;
                    final capturedVirtualH = virtualH;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final now = DateTime.now();
                      final currentHour = now.hour + now.minute / 60.0;
                      final selectedIdx = _selectedDate != null
                          ? _sortedDates.indexOf(_selectedDate!)
                          : 0;
                      final numDates = _sortedDates.length;

                      final minX = math.min(-(capturedCanvasW - capturedW), 0.0);
                      final minY = math.min(-(capturedVirtualH - capturedH), 0.0);

                      final xOffset = (-(_kCanvasLeftPadding +
                              currentHour / 24.0 * virtualW -
                              capturedW / 2))
                          .clamp(minX, 0.0);
                      final selectedVirtualY =
                          _perspectiveRowY(selectedIdx, numDates);
                      final yOffset =
                          (-(selectedVirtualY - capturedH / 2))
                              .clamp(minY, 0.0);
                      _transformCtrl.value =
                          Matrix4.translationValues(xOffset, yOffset, 0);
                    });
                  }

                  return InteractiveViewer(
                    transformationController: _transformCtrl,
                    constrained: false,
                    scaleEnabled: true,
                    minScale: 0.3,
                    maxScale: 5.0,
                    panEnabled: true,
                    boundaryMargin: EdgeInsets.zero,
                    child: SizedBox(
                      width: canvasW,
                      height: virtualH,
                      child: Stack(
                        children: [
                          // 静态树木层（无摇摆，约70%）：仅在视口平移/缩放时重建
                          AnimatedBuilder(
                            animation: _transformCtrl,
                            builder: (_, __) {
                              final visRect =
                                  _computeVisibleRect(viewportW, viewportH);
                              return CustomPaint(
                                size: Size(canvasW, virtualH),
                                painter: _StaticForestPainter(
                                  sessions: widget.sessions,
                                  placements: _placements,
                                  indices: _staticSortedIndices,
                                  viewportW: viewportW,
                                  visRect: visRect,
                                ),
                              );
                            },
                          ),
                          // 摇摆树 painter（每帧重绘，单次 paint 覆盖所有摇摆树）
                          AnimatedBuilder(
                            animation: _globalSwayCtrl,
                            builder: (_, __) {
                              final visRect =
                                  _computeVisibleRect(viewportW, viewportH);
                              return CustomPaint(
                                size: Size(canvasW, virtualH),
                                painter: _SwayForestPainter(
                                  sessions: widget.sessions,
                                  placements: _placements,
                                  indices: _swaySortedIndices,
                                  phaseOffsets: _phaseOffsets,
                                  swayAmplitudes: _swayAmplitudes,
                                  globalSwayValue: _globalSwayCtrl.value,
                                  windFactor: widget.weather.windFactor,
                                  viewportW: viewportW,
                                  visRect: visRect,
                                ),
                              );
                            },
                          ),
                          // 交互层：轻量 per-tree 透明 hit target（无 CustomPaint）
                          for (final i in _sortedIndices)
                            _buildInteractionWidget(i, viewportW, canvasW),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Y 轴（固定左侧，标签跟随纵向平移）
            Positioned(
              left: 0,
              top: 0,
              width: _kYAxisWidth,
              bottom: _kXAxisHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedBuilder(
                    animation: _transformCtrl,
                    builder: (context, __) {
                      final yOffset = _transformCtrl.value.getTranslation().y;
                      return _buildYAxis(
                          constraints.maxHeight, yOffset, isDark);
                    },
                  );
                },
              ),
            ),

            // X 轴（固定底部，标签跟随横向平移）
            Positioned(
              left: _kYAxisWidth,
              bottom: 0,
              right: 0,
              height: _kXAxisHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedBuilder(
                    animation: _transformCtrl,
                    builder: (context, __) {
                      final xOffset = _transformCtrl.value.getTranslation().x;
                      return _buildXAxis(constraints.maxWidth, xOffset, isDark);
                    },
                  );
                },
              ),
            ),

            // 草地地面渐变（视口底部，营造落地感）
            Positioned(
              left: _kYAxisWidth,
              right: 0,
              bottom: _kXAxisHeight,
              height: 72,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDark
                          ? [Colors.transparent, const Color(0xCC1A0C06)]
                          : [Colors.transparent, const Color(0xCC7A5C30)],
                    ),
                  ),
                ),
              ),
            ),

            // 远景薄雾（视口顶部，营造时间纵深感）
            Positioned(
              left: _kYAxisWidth,
              top: 0,
              right: 0,
              height: 100,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDark
                          ? [const Color(0x550D1B2A), Colors.transparent]
                          : [const Color(0x66D6EAF8), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),

            // 环境萤光粒子
            Positioned(
              left: _kYAxisWidth,
              top: 0,
              right: 0,
              bottom: _kXAxisHeight,
              child: AnimatedBuilder(
                animation: _ambientCtrl,
                builder: (_, __) => IgnorePointer(
                  child: CustomPaint(
                    painter: _AmbientParticlesPainter(
                      _ambientParticles,
                      _ambientCtrl.value,
                      isDark,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYAxis(double viewportH, double yOffset, bool isDark) {
    final labelColor = isDark ? Colors.white70 : Colors.black54;
    final selectedColor = isDark ? Colors.white : Colors.black87;
    final numDates = _sortedDates.length;

    return ClipRect(
      child: Stack(
        children: [
          // 半透明背景
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white)
                    .withValues(alpha: 0.05),
              ),
            ),
          ),
          for (var i = 0; i < numDates; i++)
            Builder(builder: (context) {
              final rowCenterY = _perspectiveRowY(i, numDates);
              final viewportY = rowCenterY + yOffset;
              if (viewportY < -_kRowHeight ||
                  viewportY > viewportH + _kRowHeight) {
                return const SizedBox.shrink();
              }
              final date = _sortedDates[i];
              final isSelected = date == _selectedDate;
              final label =
                  '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
              return Positioned(
                top: viewportY - 20,
                left: 0,
                right: 0,
                height: 40,
                child: GestureDetector(
                  onTap: () => setState(() => _selectedDate = date),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w400,
                        color: isSelected ? selectedColor : labelColor,
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildXAxis(double viewportW, double xOffset, bool isDark) {
    final labelColor = isDark ? Colors.white70 : Colors.black54;
    const virtualW = 24.0 * _kPixelsPerHour;

    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white)
                    .withValues(alpha: 0.05),
              ),
            ),
          ),
          for (var hour = 0; hour < 24; hour += 3)
            Builder(builder: (context) {
              final virtualX = _kCanvasLeftPadding + hour / 24.0 * virtualW;
              final viewportX = virtualX + xOffset;
              if (viewportX < -60 || viewportX > viewportW + 60) {
                return const SizedBox.shrink();
              }
              return Positioned(
                left: viewportX - 20,
                top: 0,
                width: 40,
                bottom: 0,
                child: Center(
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: TextStyle(fontSize: 10, color: labelColor),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  /// 计算当前视口在虚拟画布中的可见矩形（含 120px 安全边距防止 pop-in）
  Rect _computeVisibleRect(double viewportW, double viewportH) {
    final matrix = _transformCtrl.value;
    final scale = math.max(matrix.getMaxScaleOnAxis(), 0.01);
    final t = matrix.getTranslation();
    const pad = 120.0;
    return Rect.fromLTWH(
      -t.x / scale - pad,
      -t.y / scale - pad,
      viewportW / scale + pad * 2,
      viewportH / scale + pad * 2,
    );
  }

  Widget _buildInteractionWidget(int i, double viewportW, double canvasW) {
    final session = widget.sessions[i];
    final p = _placements[i];
    final treeSize = viewportW * 0.22 * p.scale;

    return Positioned(
      left: p.x - treeSize / 2,
      top: p.y - treeSize * 0.85,
      width: treeSize,
      height: treeSize,
      child: GestureDetector(
        onTap: () => setState(() => _selectedDate = _sortedDates[p.dateIndex]),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hoveredIndex = i),
          onExit: (_) {
            if (_hoveredIndex == i) setState(() => _hoveredIndex = null);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const SizedBox.expand(), // 透明 hit target
              if (_hoveredIndex == i)
                Positioned(
                  bottom: treeSize * 0.9,
                  left: p.x < canvasW / 2 ? 0 : null,
                  right: p.x >= canvasW / 2 ? 0 : null,
                  child: _TreeTooltip(session: session),
                ),
            ],
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
    required this.dateIndex,
    required this.depthOpacity,
  });

  final double x; // 虚拟画布绝对 x（时间轴坐标，像素）
  final double y; // 虚拟画布绝对 y（日期轴坐标，像素）
  final double scale; // 0.35~0.85（由 jitterY 决定深度感）
  final int seed;
  final int dateIndex; // 所属日期在 _sortedDates 中的索引
  final double depthOpacity; // 0.40~1.0
}

// ── Tag 颜色映射 ─────────────────────────────────────────────────────────────

const _kTagColors = <Color>[
  Color(0xFFEF5350),
  Color(0xFF42A5F5),
  Color(0xFF66BB6A),
  Color(0xFFFFCA28),
  Color(0xFFAB47BC),
  Color(0xFF26C6DA),
  Color(0xFFFF7043),
  Color(0xFF8D6E63),
];

Color _tagColorFor(String tag) {
  final hash = tag.codeUnits.fold(0, (a, b) => a + b);
  return _kTagColors[hash % _kTagColors.length];
}

// ── 悬浮信息卡 ────────────────────────────────────────────────────────────────

const _kSpeciesNames = <String, String>{
  'oak': '橡树',
  'pine': '松树',
  'cherry': '樱花树',
  'bamboo': '竹子',
  'maple': '枫树',
  'poplar': '白杨',
  'willow': '柳树',
  'ginkgo': '银杏',
  'plum': '梅花',
  'banyan': '榕树',
};

class _TreeTooltip extends StatelessWidget {
  const _TreeTooltip({required this.session});
  final FocusSessionModel session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final st = session.startTime;
    final dateStr =
        '${st.year}/${st.month.toString().padLeft(2, '0')}/${st.day.toString().padLeft(2, '0')}';
    final speciesName =
        _kSpeciesNames[session.treeSpecies] ?? session.treeSpecies;

    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                speciesName,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (session.tag != null) ...[
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _tagColorFor(session.tag!),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  session.tag!,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: _tagColorFor(session.tag!)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
          ),
          Text(
            '专注 ${session.durationMinutes} 分钟',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

// ── 森林绘树辅助函数（文件级，供两大 Painter 共用） ─────────────────────────────

/// 在整个虚拟画布坐标系中绘制一棵完成树
void _paintForestTree(
  Canvas canvas,
  FocusSessionModel session,
  _TreePlacement p,
  double viewportW,
  double swayAngle,
) {
  final style = treeStyleFor(session.treeSpecies);
  final treeSize = viewportW * 0.22 * p.scale;
  final opacity = p.depthOpacity.clamp(0.0, 1.0);
  canvas.save();
  canvas.translate(p.x - treeSize / 2, p.y - treeSize * 0.85);
  _paintTreeLocal(canvas, Size(treeSize, treeSize), session.treeSpecies,
      p.seed, style, opacity, swayAngle);
  canvas.restore();
}

/// 在 (0,0)~size 局部坐标系内绘制树
void _paintTreeLocal(
  Canvas canvas,
  Size size,
  String speciesId,
  int seed,
  TreeStyle style,
  double opacity,
  double swayAngle,
) {
  final centerX = size.width / 2;
  final groundY = size.height * 0.92;

  // 地面阴影
  canvas.drawOval(
    Rect.fromCenter(
        center: Offset(centerX, groundY + 6),
        width: size.width * 0.38,
        height: 13),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.15 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
  );

  final trunkColor =
      style.trunkColor.withValues(alpha: style.trunkColor.a * opacity);
  final leafColor =
      style.leafColor.withValues(alpha: style.leafColor.a * opacity);

  if (style.isBamboo) {
    _paintBambooLocal(canvas, size, style, trunkColor, leafColor, seed, opacity,
        swayAngle);
    return;
  }

  // 树干
  final trunkWidth = size.width * style.trunkWidthRatio;
  final trunkHeight = size.height * 0.52 * style.trunkHeightRatio;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX - trunkWidth / 2, groundY - trunkHeight,
          trunkWidth, trunkHeight),
      Radius.circular(trunkWidth / 2),
    ),
    Paint()..color = trunkColor,
  );

  // 完成光晕
  canvas.drawCircle(
    Offset(centerX, groundY - trunkHeight),
    size.width * 0.15,
    Paint()
      ..color = const Color(0xFFE8C97A).withValues(alpha: 0.35 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
  );

  // 树冠（含摇摆旋转）
  final maxDepth = speciesId == 'pine' ? 7 : 6;
  final rng = math.Random(seed);
  final branchBaseLen = size.height * 0.17 * style.crownRatio;
  final start = Offset(centerX, groundY - trunkHeight);

  canvas.save();
  canvas.translate(centerX, groundY - trunkHeight);
  canvas.rotate(swayAngle);
  canvas.translate(-centerX, -(groundY - trunkHeight));

  _fPaintBranches(canvas, start, branchBaseLen, -math.pi / 2, 0, maxDepth,
      rng, trunkColor, style.spread);

  // 叶子：批量 drawPoints（kLeafOffsetCache 共享）
  final cacheKey = '$speciesId-$seed';
  List<Offset> leaves;
  final cached = kLeafOffsetCache[cacheKey];
  if (cached != null) {
    leaves = cached
        .map((n) => Offset(start.dx + n.dx * branchBaseLen,
            start.dy + n.dy * branchBaseLen))
        .toList(growable: false);
  } else {
    final raw = <Offset>[];
    _fCollectLeafPts(raw, start, branchBaseLen, -math.pi / 2, 0, maxDepth,
        math.Random(seed), style.spread);
    leaves = raw;
    if (branchBaseLen > 0) {
      kLeafOffsetCache[cacheKey] = raw
          .map((pt) => Offset((pt.dx - start.dx) / branchBaseLen,
              (pt.dy - start.dy) / branchBaseLen))
          .toList(growable: false);
    }
  }

  final leafRadius = size.shortestSide * style.leafRadiusRatio;
  canvas.drawPoints(
    ui.PointMode.points,
    leaves,
    Paint()
      ..color = leafColor.withValues(alpha: style.leafOpacity * opacity)
      ..strokeWidth = leafRadius * 2
      ..strokeCap = StrokeCap.round,
  );

  canvas.restore(); // 树冠旋转
}

/// 竹子绘制
void _paintBambooLocal(Canvas canvas, Size size, TreeStyle style,
    Color trunkColor, Color leafColor, int seed, double opacity,
    double swayAngle) {
  final trunkWidth = size.width * 0.045;
  final maxHeight = size.height * 0.70 * style.trunkHeightRatio;
  const segmentCount = 6;
  final segH = maxHeight / segmentCount;
  final centerX = size.width / 2;
  final groundY = size.height * 0.92;

  canvas.save();
  canvas.translate(centerX, groundY);
  canvas.rotate(swayAngle * 0.7);

  final nodePaint = Paint()..color = const Color(0x33FFFFFF);
  for (var i = 0; i < segmentCount; i++) {
    final y0 = -i * segH;
    final y1 = -(i + 1) * segH;
    if (y1 > 0) continue;
    final segRect = Rect.fromLTRB(-trunkWidth / 2, y1, trunkWidth / 2, y0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(segRect, Radius.circular(trunkWidth * 0.3)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [trunkColor, trunkColor.withValues(alpha: trunkColor.a * 0.8)],
        ).createShader(segRect),
    );
    canvas.drawRect(
        Rect.fromLTWH(-trunkWidth / 2 - 1, y0 - 2, trunkWidth + 2, 4),
        nodePaint);
  }

  final topY = -maxHeight;
  final rng = math.Random(seed);
  for (var i = 0; i < 12; i++) {
    final angle =
        -math.pi / 2 + (rng.nextDouble() - 0.5) * math.pi * 1.2;
    final len = size.width * (0.12 + rng.nextDouble() * 0.10);
    final leafAlpha =
        ((0.5 + 0.5 * (i / 12)) * opacity).clamp(0.0, 1.0);
    canvas.drawLine(
      Offset(0, topY),
      Offset(math.cos(angle) * len, topY + math.sin(angle) * len),
      Paint()
        ..color = leafColor.withValues(alpha: leafAlpha)
        ..strokeWidth = 2 + rng.nextDouble() * 2
        ..strokeCap = StrokeCap.round,
    );
  }
  canvas.restore();
}

/// 递归枝条（progress 固定 1.0）
void _fPaintBranches(
    Canvas canvas,
    Offset start,
    double length,
    double angle,
    int depth,
    int maxDepth,
    math.Random rng,
    Color trunkColor,
    double spread) {
  final threshold =
      depth <= 1 ? depth * 0.08 : 0.16 + (depth - 2) * (0.84 / (maxDepth - 1));
  if (1.0 < threshold) return;
  final effectiveLen = length * 1.0 * math.pow(0.72, depth).toDouble();
  final end = Offset(start.dx + math.cos(angle) * effectiveLen,
      start.dy + math.sin(angle) * effectiveLen);
  canvas.drawLine(
    start,
    end,
    Paint()
      ..color = trunkColor.withValues(alpha: 0.95)
      ..strokeWidth = (6.0 * math.pow(0.72, depth)).clamp(1.5, 6.0).toDouble()
      ..strokeCap = StrokeCap.round,
  );
  if (depth >= maxDepth) return;
  final jitter = (rng.nextDouble() - 0.5) * 0.25;
  _fPaintBranches(canvas, end, length, angle - spread + jitter, depth + 1,
      maxDepth, rng, trunkColor, spread);
  _fPaintBranches(canvas, end, length, angle + spread + jitter, depth + 1,
      maxDepth, rng, trunkColor, spread);
}

/// 收集叶子坐标（progress 固定 1.0）
void _fCollectLeafPts(List<Offset> out, Offset start, double length,
    double angle, int depth, int maxDepth, math.Random rng, double spread) {
  final threshold =
      depth <= 1 ? depth * 0.08 : 0.16 + (depth - 2) * (0.84 / (maxDepth - 1));
  if (1.0 < threshold) return;
  final effectiveLen = length * math.pow(0.72, depth).toDouble();
  final end = Offset(start.dx + math.cos(angle) * effectiveLen,
      start.dy + math.sin(angle) * effectiveLen);
  if (depth >= maxDepth - 1) {
    out.add(end);
    return;
  }
  final jitter = (rng.nextDouble() - 0.5) * 0.25;
  _fCollectLeafPts(out, end, length, angle - spread + jitter, depth + 1,
      maxDepth, rng, spread);
  _fCollectLeafPts(out, end, length, angle + spread + jitter, depth + 1,
      maxDepth, rng, spread);
}

// ── 两大 Forest Painter ────────────────────────────────────────────

/// 静态树 Painter：无摇摆树，pan/zoom 时重绘，单次 paint 覆盖所有静态树
class _StaticForestPainter extends CustomPainter {
  _StaticForestPainter({
    required this.sessions,
    required this.placements,
    required this.indices,
    required this.viewportW,
    required this.visRect,
  });

  final List<FocusSessionModel> sessions;
  final List<_TreePlacement> placements;
  final List<int> indices;
  final double viewportW;
  final Rect visRect;

  @override
  void paint(Canvas canvas, Size size) {
    for (final i in indices) {
      final p = placements[i];
      final treeSize = viewportW * 0.22 * p.scale;
      if (p.x + treeSize / 2 < visRect.left ||
          p.x - treeSize / 2 > visRect.right ||
          p.y < visRect.top ||
          p.y - treeSize * 0.85 > visRect.bottom) { continue; }
      _paintForestTree(canvas, sessions[i], p, viewportW, 0.0);
    }
  }

  @override
  bool shouldRepaint(_StaticForestPainter old) =>
      old.sessions != sessions ||
      old.placements != placements ||
      old.viewportW != viewportW ||
      old.visRect != visRect;
}

/// 摇摆树 Painter：每帧重绘，单次 paint 覆盖所有摇摆树
class _SwayForestPainter extends CustomPainter {
  _SwayForestPainter({
    required this.sessions,
    required this.placements,
    required this.indices,
    required this.phaseOffsets,
    required this.swayAmplitudes,
    required this.globalSwayValue,
    required this.windFactor,
    required this.viewportW,
    required this.visRect,
  });

  final List<FocusSessionModel> sessions;
  final List<_TreePlacement> placements;
  final List<int> indices;
  final List<double> phaseOffsets;
  final List<double> swayAmplitudes;
  final double globalSwayValue;
  final double windFactor;
  final double viewportW;
  final Rect visRect;

  @override
  void paint(Canvas canvas, Size size) {
    final windBase = windFactor * 0.05;
    for (final i in indices) {
      final p = placements[i];
      final treeSize = viewportW * 0.22 * p.scale;
      if (p.x + treeSize / 2 < visRect.left ||
          p.x - treeSize / 2 > visRect.right ||
          p.y < visRect.top ||
          p.y - treeSize * 0.85 > visRect.bottom) { continue; }
      final swayAngle = math.sin(
              (globalSwayValue + phaseOffsets[i]) * 2 * math.pi) *
          (swayAmplitudes[i] * (1.0 + windFactor) + windBase);
      _paintForestTree(canvas, sessions[i], p, viewportW, swayAngle);
    }
  }

  @override
  bool shouldRepaint(_SwayForestPainter old) =>
      old.globalSwayValue != globalSwayValue ||
      old.windFactor != windFactor ||
      old.viewportW != viewportW ||
      old.visRect != visRect;
}

// ── 环境萤光粒子 ──────────────────────────────────────────────────────────────

class _AmbientParticle {
  const _AmbientParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.phase,
  });
  final double x;
  final double y;
  final double speed;
  final double size;
  final double phase;
}

class _AmbientParticlesPainter extends CustomPainter {
  _AmbientParticlesPainter(this.particles, this.t, this.isDark);
  final List<_AmbientParticle> particles;
  final double t;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final phase = (t + p.phase) % 1.0;
      final cy = ((p.y - phase * p.speed) % 1.0 + 1.0) % 1.0;
      final driftX = math.sin(phase * math.pi * 2 + p.x * 5) * 0.015;
      final cx = ((p.x + driftX) % 1.0 + 1.0) % 1.0;
      final alpha = math.sin(phase * math.pi).clamp(0.0, 1.0) * 0.45;
      canvas.drawCircle(
        Offset(cx * size.width, cy * size.height),
        p.size,
        Paint()
          ..color = (isDark
                  ? const Color(0xFFFFE082)
                  : const Color(0xFF9CCC65))
              .withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientParticlesPainter old) => old.t != t;
}
