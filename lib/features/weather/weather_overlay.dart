import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'weather_type.dart';

/// 天气粒子/遮罩叠加层，包裹任意 child Widget
class WeatherOverlay extends StatefulWidget {
  const WeatherOverlay({
    super.key,
    required this.weather,
    required this.child,
  });

  final WeatherType weather;
  final Widget child;

  @override
  State<WeatherOverlay> createState() => _WeatherOverlayState();
}

class _WeatherOverlayState extends State<WeatherOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _particles = _genParticles(80);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static List<_Particle> _genParticles(int n) {
    final rng = math.Random(42);
    return List.generate(
      n,
      (_) => _Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        speed: 0.35 + rng.nextDouble() * 0.55,
        size: rng.nextDouble(),
        drift: (rng.nextDouble() - 0.5) * 0.6,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.weather;

    // 晴/风：无视觉遮罩，只靠树木摇摆体现
    if (w == WeatherType.sunny || w == WeatherType.windy) {
      return widget.child;
    }

    Widget overlay;
    if (w == WeatherType.cloudy) {
      overlay = const _CloudyOverlay();
    } else {
      overlay = AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: w == WeatherType.snowy
              ? _SnowPainter(_particles, _ctrl.value)
              : _RainPainter(
                  _particles,
                  _ctrl.value,
                  w == WeatherType.stormy,
                ),
        ),
      );
    }

    return Stack(
      children: [
        widget.child,
        Positioned.fill(child: IgnorePointer(child: overlay)),
      ],
    );
  }
}

// ── 粒子数据 ──────────────────────────────────────────────────────────────────

class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.drift,
  });

  final double x;     // 初始 x（相对画布宽度 0~1）
  final double y;     // 初始 y（相对画布高度 0~1）
  final double speed; // 下落速度（每周期经过的画布高度比）
  final double size;  // 0~1，影响粒子大小
  final double drift; // 横向漂移量（雪用）
}

// ── 阴天遮罩 ─────────────────────────────────────────────────────────────────

class _CloudyOverlay extends StatelessWidget {
  const _CloudyOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, 0.5),
          colors: [
            Colors.blueGrey.withValues(alpha: 0.22),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ── 雨线 ─────────────────────────────────────────────────────────────────────

class _RainPainter extends CustomPainter {
  const _RainPainter(this.particles, this.t, this.heavy);

  final List<_Particle> particles;
  final double t;
  final bool heavy;

  static const _angle = math.pi / 10.0; // ~18° 斜线

  @override
  void paint(Canvas canvas, Size size) {
    final count = heavy ? 70 : 40;
    final paint = Paint()
      ..color = const Color(0xFF90CAF9)
          .withValues(alpha: heavy ? 0.52 : 0.38)
      ..strokeWidth = heavy ? 1.5 : 1.0
      ..strokeCap = StrokeCap.round;

    final scale = (size.height / 400.0).clamp(0.5, 2.5);

    for (int i = 0; i < count && i < particles.length; i++) {
      final p = particles[i];
      final cy = (p.y + t * p.speed) % 1.0;
      // 斜向偏移让雨滴看起来是在飘落
      final cx = (p.x + cy * 0.10) % 1.0;
      final x = cx * size.width;
      final y = cy * size.height;
      final len = (8 + p.size * 9) * scale;

      canvas.drawLine(
        Offset(x - math.sin(_angle) * len, y - math.cos(_angle) * len),
        Offset(x, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => old.t != t || old.heavy != heavy;
}

// ── 雪花 ─────────────────────────────────────────────────────────────────────

class _SnowPainter extends CustomPainter {
  const _SnowPainter(this.particles, this.t);

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.78);
    final scale = (size.height / 400.0).clamp(0.5, 2.5);

    for (final p in particles) {
      // 雪比雨慢（speed * 0.22）
      final cy = (p.y + t * p.speed * 0.22) % 1.0;
      // 正弦横向漂移
      final driftX =
          math.sin(t * math.pi * 2 + p.x * 8.0) * p.drift * 0.04;
      final cx = ((p.x + driftX) % 1.0 + 1.0) % 1.0;
      final x = cx * size.width;
      final y = cy * size.height;
      final r = (1.5 + p.size * 2.5) * scale;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_SnowPainter old) => old.t != t;
}
