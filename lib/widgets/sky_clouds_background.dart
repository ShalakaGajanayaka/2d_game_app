import 'package:flutter/material.dart';

/// Ultra-lightweight, 60fps GPU-accelerated moving clouds background for the game arena.
/// Uses pure vector primitives (zero images, zero network overhead) to simulate altitude and forward flight.
class SkyCloudsBackground extends StatefulWidget {
  final bool isPlaying;
  final double multiplier;

  const SkyCloudsBackground({
    Key? key,
    required this.isPlaying,
    this.multiplier = 1.0,
  }) : super(key: key);

  @override
  State<SkyCloudsBackground> createState() => _SkyCloudsBackgroundState();
}

class _SkyCloudsBackgroundState extends State<SkyCloudsBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Continuous loop for gentle, infinite ambient cloud drift
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 65),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _CloudsPainter(
              animationValue: _controller.value,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _CloudSpec {
  final double normalizedX;
  final double normalizedY;
  final double scale;
  final double speed;
  final double opacity;

  const _CloudSpec({
    required this.normalizedX,
    required this.normalizedY,
    required this.scale,
    required this.speed,
    required this.opacity,
  });
}

class _CloudsPainter extends CustomPainter {
  final double animationValue;

  _CloudsPainter({
    required this.animationValue,
  });

  // Calm, organic cloud distribution with gentle parallax speeds
  static const List<_CloudSpec> _clouds = [
    // Distant slow clouds (Layer 1 - deep background, ultra-gentle drift)
    _CloudSpec(normalizedX: 0.10, normalizedY: 0.16, scale: 0.75, speed: 0.32, opacity: 0.040),
    _CloudSpec(normalizedX: 0.55, normalizedY: 0.28, scale: 0.85, speed: 0.38, opacity: 0.045),
    _CloudSpec(normalizedX: 0.85, normalizedY: 0.72, scale: 0.70, speed: 0.34, opacity: 0.038),

    // Mid-ground clouds (Layer 2 - natural depth)
    _CloudSpec(normalizedX: 0.35, normalizedY: 0.48, scale: 1.15, speed: 0.48, opacity: 0.055),
    _CloudSpec(normalizedX: 0.70, normalizedY: 0.82, scale: 1.05, speed: 0.52, opacity: 0.050),

    // Foreground clouds (Layer 3 - subtle, slightly larger silhouettes)
    _CloudSpec(normalizedX: 0.20, normalizedY: 0.88, scale: 1.35, speed: 0.62, opacity: 0.065),
    _CloudSpec(normalizedX: 0.90, normalizedY: 0.38, scale: 1.40, speed: 0.58, opacity: 0.060),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;
    if (width <= 0 || height <= 0) return;

    // Steady, serene ambient drift: zero acceleration during game rounds
    for (final cloud in _clouds) {
      final double cloudWidth = 140.0 * cloud.scale;
      final double totalSpan = width + cloudWidth * 2;
      
      // Parallax travel: right to left (constant, peaceful pace)
      final double travel = (cloud.normalizedX * totalSpan) -
          (animationValue * totalSpan * cloud.speed);
      
      // Seamless wrap-around modulo
      final double currentX = (travel % totalSpan) - cloudWidth;
      final double currentY = cloud.normalizedY * height;

      _drawCloud(canvas, currentX, currentY, cloud.scale, cloud.opacity);
    }
  }

  void _drawCloud(Canvas canvas, double x, double y, double scale, double opacity) {
    final double baseWidth = 95.0 * scale;
    final double baseHeight = 28.0 * scale;

    // Bounds with margin for soft vapor blur
    final Rect cloudBounds = Rect.fromCenter(
      center: Offset(x, y - 5 * scale),
      width: baseWidth + 60.0 * scale,
      height: baseHeight + 50.0 * scale,
    );

    // Single-pass composited layer with uniform opacity and subtle atmospheric edge blur
    canvas.saveLayer(
      cloudBounds,
      Paint()
        ..color = Colors.white.withOpacity(opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * scale),
    );

    // 100% solid white paint inside the layer: overlapping circles merge with zero visible seams!
    final solidPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;

    // Aerodynamic rounded cloud base
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, y), width: baseWidth, height: baseHeight),
      Radius.circular(baseHeight / 2),
    );
    canvas.drawRRect(rrect, solidPaint);

    // Fluffy cloud domes merging seamlessly into a unified cloud
    canvas.drawCircle(Offset(x - 20 * scale, y - 8 * scale), 18 * scale, solidPaint);
    canvas.drawCircle(Offset(x + 2 * scale, y - 13 * scale), 17 * scale, solidPaint);
    canvas.drawCircle(Offset(x + 22 * scale, y - 7 * scale), 15 * scale, solidPaint);
    canvas.drawCircle(Offset(x + 36 * scale, y - 3 * scale), 11 * scale, solidPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CloudsPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
