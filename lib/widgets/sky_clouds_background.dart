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
    // Continuous loop for infinite parallax flight
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
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
              isPlaying: widget.isPlaying,
              multiplier: widget.multiplier,
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
  final bool isWisp;

  const _CloudSpec({
    required this.normalizedX,
    required this.normalizedY,
    required this.scale,
    required this.speed,
    required this.opacity,
    this.isWisp = false,
  });
}

class _CloudsPainter extends CustomPainter {
  final double animationValue;
  final bool isPlaying;
  final double multiplier;

  _CloudsPainter({
    required this.animationValue,
    required this.isPlaying,
    required this.multiplier,
  });

  // Pre-configured cloud formations for natural parallax distribution
  static const List<_CloudSpec> _clouds = [
    // Distant slow clouds (Layer 1 - deep background)
    _CloudSpec(normalizedX: 0.10, normalizedY: 0.16, scale: 0.75, speed: 0.7, opacity: 0.040),
    _CloudSpec(normalizedX: 0.55, normalizedY: 0.28, scale: 0.85, speed: 0.8, opacity: 0.045),
    _CloudSpec(normalizedX: 0.85, normalizedY: 0.72, scale: 0.70, speed: 0.7, opacity: 0.038),
    
    // Altitude speed wisps (Thin aerodynamic streamlines)
    _CloudSpec(normalizedX: 0.30, normalizedY: 0.22, scale: 1.00, speed: 1.6, opacity: 0.035, isWisp: true),
    _CloudSpec(normalizedX: 0.75, normalizedY: 0.60, scale: 1.20, speed: 1.8, opacity: 0.040, isWisp: true),

    // Mid-ground clouds (Layer 2)
    _CloudSpec(normalizedX: 0.35, normalizedY: 0.48, scale: 1.15, speed: 1.1, opacity: 0.055),
    _CloudSpec(normalizedX: 0.70, normalizedY: 0.82, scale: 1.05, speed: 1.2, opacity: 0.050),

    // Foreground clouds (Layer 3 - faster, slightly more defined)
    _CloudSpec(normalizedX: 0.20, normalizedY: 0.88, scale: 1.35, speed: 1.5, opacity: 0.065),
    _CloudSpec(normalizedX: 0.90, normalizedY: 0.38, scale: 1.40, speed: 1.4, opacity: 0.060),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;
    if (width <= 0 || height <= 0) return;

    // Flight speed multiplier: gentle drift when waiting, picking up speed during active flight
    final double speedFactor = isPlaying
        ? (1.3 + (multiplier.clamp(1.0, 10.0) - 1.0) * 0.08)
        : 0.6;

    for (final cloud in _clouds) {
      final double cloudWidth = 140.0 * cloud.scale;
      final double totalSpan = width + cloudWidth * 2;
      
      // Parallax travel: right to left (simulating forward flight towards top-right)
      final double travel = (cloud.normalizedX * totalSpan) -
          (animationValue * totalSpan * cloud.speed * speedFactor);
      
      // Seamless wrap-around modulo
      final double currentX = (travel % totalSpan) - cloudWidth;
      final double currentY = cloud.normalizedY * height;

      if (cloud.isWisp) {
        _drawWindWisp(canvas, currentX, currentY, cloud.scale, cloud.opacity);
      } else {
        _drawCloud(canvas, currentX, currentY, cloud.scale, cloud.opacity);
      }
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

  void _drawWindWisp(Canvas canvas, double x, double y, double scale, double opacity) {
    final paint = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0 * scale;

    final double wispLength = 110.0 * scale;
    canvas.drawLine(
      Offset(x - wispLength / 2, y),
      Offset(x + wispLength / 2, y),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CloudsPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.multiplier != multiplier;
  }
}
