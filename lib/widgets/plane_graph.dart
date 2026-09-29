import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

class PlaneGraph extends StatelessWidget {
  final double multiplier;
  final bool isCrashed;

  const PlaneGraph({
    Key? key,
    required this.multiplier,
    required this.isCrashed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double norm = math.max(0.0, multiplier - 1.0);
        // Moderate progressive curve: reaches mid-screen comfortably at 2.0x, smooth asymptotic cruising
        double progress = 1.0 - (1.0 / (1.0 + norm * 0.95));
        progress = progress.clamp(0.0, 0.985);
        
        double w = constraints.maxWidth;
        double h = constraints.maxHeight;
        double t = progress;

        // P0: Runway origin (exact bottom-left corner of the box)
        // P1: Smooth horizontal ground acceleration along bottom runway
        // P2: Moderate upward curve passing comfortably below central multiplier text
        // P3: High altitude cruise plateau in the upper-right sky
        final p0 = Offset(0.0, h);
        final p1 = Offset(w * 0.28, h);
        final p2 = Offset(w * 0.58, h * 0.54);
        final p3 = Offset(w * 0.84, h * 0.22);

        // De Casteljau cubic subdivision for exact mathematical curve point & tangent
        final double oneMinusT = 1.0 - t;
        final p01 = Offset(oneMinusT * p0.dx + t * p1.dx, oneMinusT * p0.dy + t * p1.dy);
        final p12 = Offset(oneMinusT * p1.dx + t * p2.dx, oneMinusT * p1.dy + t * p2.dy);
        final p23 = Offset(oneMinusT * p2.dx + t * p3.dx, oneMinusT * p2.dy + t * p3.dy);

        final p012 = Offset(oneMinusT * p01.dx + t * p12.dx, oneMinusT * p01.dy + t * p12.dy);
        final p123 = Offset(oneMinusT * p12.dx + t * p23.dx, oneMinusT * p12.dy + t * p23.dy);

        final p0123 = Offset(oneMinusT * p012.dx + t * p123.dx, oneMinusT * p012.dy + t * p123.dy);

        // Plane position and natural pitch angle following tangent vector
        final double posX = p0123.dx;
        final double posY = p0123.dy;
        final double planeAngle = math.atan2(p0123.dy - p012.dy, p0123.dx - p012.dx) + (math.pi / 2);

        // Subtle, lightweight aerodynamic float normalized to linear elapsed time
        // Prevents violent high-frequency oscillation at high multipliers (e.g. 60x+)
        final double airborneFactor = math.min(1.0, t * 2.5);
        final double elapsedSec = math.log(math.max(1.0, multiplier)) / 0.095;
        final double floatOffset = math.sin(elapsedSec * 2.0) * 1.8 * airborneFactor;
        final double finalX = posX;
        final double finalY = (posY + floatOffset).clamp(h * 0.16, h * 0.98);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: Size(w, h),
              painter: GraphPainter(t, isCrashed),
            ),
            Positioned(
              left: finalX - 80,
              top: finalY - 80,
              child: SizedBox(
                width: 160,
                height: 160,
                child: isCrashed
                    ? CrashExplosion(planeAngle: planeAngle)
                    : Center(
                        child: Transform.rotate(
                          angle: planeAngle,
                          child: const Icon(
                            Icons.flight,
                            size: 48,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      }
    );
  }
}

class GraphPainter extends CustomPainter {
  final double t;
  final bool isCrashed;

  GraphPainter(this.t, this.isCrashed);

  @override
  void paint(Canvas canvas, Size size) {
    double w = size.width;
    double h = size.height;

    // Fixed control points anchored to bottom-left corner
    final p0 = Offset(0.0, h);
    final p1 = Offset(w * 0.28, h);
    final p2 = Offset(w * 0.58, h * 0.54);
    final p3 = Offset(w * 0.84, h * 0.22);

    final double oneMinusT = 1.0 - t;
    final p01 = Offset(oneMinusT * p0.dx + t * p1.dx, oneMinusT * p0.dy + t * p1.dy);
    final p12 = Offset(oneMinusT * p1.dx + t * p2.dx, oneMinusT * p1.dy + t * p2.dy);
    final p23 = Offset(oneMinusT * p2.dx + t * p3.dx, oneMinusT * p2.dy + t * p3.dy);

    final p012 = Offset(oneMinusT * p01.dx + t * p12.dx, oneMinusT * p01.dy + t * p12.dy);
    final p123 = Offset(oneMinusT * p12.dx + t * p23.dx, oneMinusT * p12.dy + t * p23.dy);

    final p0123 = Offset(oneMinusT * p012.dx + t * p123.dx, oneMinusT * p012.dy + t * p123.dy);

    final path = Path();
    path.moveTo(p0.dx, p0.dy);
    path.cubicTo(p01.dx, p01.dy, p012.dx, p012.dy, p0123.dx, p0123.dy);

    // 1. Soft red gradient fill underneath the curve (gentle slope fade)
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, p0123.dy),
        Offset(0, h),
        [
          (isCrashed ? const Color(0xFFDC2626) : const Color(0xFFEF4444)).withOpacity(0.28),
          (isCrashed ? const Color(0xFF991B1B) : const Color(0xFFB91C1C)).withOpacity(0.01),
        ],
      )
      ..style = PaintingStyle.fill;
      
    final fillPath = Path();
    fillPath.moveTo(p0.dx, h);
    fillPath.lineTo(p0.dx, p0.dy);
    fillPath.cubicTo(p01.dx, p01.dy, p012.dx, p012.dy, p0123.dx, p0123.dy);
    fillPath.lineTo(p0123.dx, h);
    fillPath.close();
    
    canvas.drawPath(fillPath, fillPaint);

    // 2. Ambient soft neon glow stroke (zero-overhead lightweight GPU vector)
    final glowPaint = Paint()
      ..color = (isCrashed ? const Color(0xFFEF4444) : const Color(0xFFF87171)).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7.0;
    canvas.drawPath(path, glowPaint);

    // 3. Core crisp flight line
    final strokePaint = Paint()
      ..color = isCrashed ? const Color(0xFFEF4444).withValues(alpha: 0.9) : const Color(0xFFEF4444)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;
    canvas.drawPath(path, strokePaint);

    // 4. Glowing 3D Terminal Sphere at the exact end of the red line when crashed / flew away
    if (isCrashed) {
      final Offset endPoint = p0123;

      // Layer 1: Ambient soft neon glow halo
      final haloPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.40)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(endPoint, 9.0, haloPaint);

      // Layer 2: Radiant bright crimson aura
      final auraPaint = Paint()
        ..color = const Color(0xFFF87171).withValues(alpha: 0.75)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(endPoint, 6.0, auraPaint);

      // Layer 3: Solid vibrant 3D red core sphere
      final corePaint = Paint()
        ..color = const Color(0xFFDC2626)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(endPoint, 4.2, corePaint);

      // Layer 4: Specular white reflection dot for 3D glossy sphere look
      final specularPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(endPoint.dx - 1.2, endPoint.dy - 1.2), 1.5, specularPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.isCrashed != isCrashed;
  }
}

class CrashExplosion extends StatefulWidget {
  final double planeAngle;

  const CrashExplosion({Key? key, required this.planeAngle}) : super(key: key);

  @override
  State<CrashExplosion> createState() => _CrashExplosionState();
}

class _CrashExplosionState extends State<CrashExplosion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 3.2 second lifecycle: instant impact burst -> rich lingering billowing smoke cloud
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double progress = _controller.value;

        // Plane shrink: fades and scales to 0 within the first 350ms (progress: 0.0 -> 0.11)
        final double planeProgress = (progress / 0.11).clamp(0.0, 1.0);
        final double planeScale =
            (1.0 - Curves.easeInBack.transform(planeProgress)).clamp(0.0, 1.0);
        final double planeOpacity = (1.0 - planeProgress).clamp(0.0, 1.0);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Ultra-lightweight GPU vector smoke plume & fiery flash
            CustomPaint(
              size: const Size(160, 160),
              painter: _SmokeCloudPainter(progress: progress),
            ),
            // Shrinking plane disappearing into the smoke
            if (planeProgress < 1.0)
              Opacity(
                opacity: planeOpacity,
                child: Transform.scale(
                  scale: planeScale,
                  child: Transform.rotate(
                    angle: widget.planeAngle,
                    child: const Icon(
                      Icons.flight,
                      size: 48,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PuffData {
  final double dx;
  final double dy;
  final double baseRadius;
  final double maxRadius;
  final double startT;
  final Color color;
  final double maxOpacity;

  const _PuffData({
    required this.dx,
    required this.dy,
    required this.baseRadius,
    required this.maxRadius,
    required this.startT,
    required this.color,
    required this.maxOpacity,
  });
}

class _SmokeCloudPainter extends CustomPainter {
  final double progress;

  _SmokeCloudPainter({required this.progress});

  // Deterministic specifications for organic, multi-layered billowing smoke ("දුම් ගොඩ")
  static const List<_PuffData> _puffs = [
    // Core dark charcoal cloud
    _PuffData(dx: -4, dy: -6, baseRadius: 18, maxRadius: 42, startT: 0.04, color: Color(0xFF1F2937), maxOpacity: 0.85),
    // Upper rising puffs (natural thermal updraft)
    _PuffData(dx: -16, dy: -26, baseRadius: 16, maxRadius: 38, startT: 0.08, color: Color(0xFF374151), maxOpacity: 0.78),
    _PuffData(dx: 14, dy: -22, baseRadius: 15, maxRadius: 36, startT: 0.10, color: Color(0xFF4B5563), maxOpacity: 0.72),
    _PuffData(dx: -28, dy: -14, baseRadius: 14, maxRadius: 35, startT: 0.12, color: Color(0xFF374151), maxOpacity: 0.70),
    // Billowing outer plume (expanding and softening)
    _PuffData(dx: 22, dy: -12, baseRadius: 14, maxRadius: 34, startT: 0.14, color: Color(0xFF4B5563), maxOpacity: 0.65),
    _PuffData(dx: -12, dy: -42, baseRadius: 15, maxRadius: 44, startT: 0.18, color: Color(0xFF4B5563), maxOpacity: 0.60),
    _PuffData(dx: 10, dy: -40, baseRadius: 14, maxRadius: 38, startT: 0.20, color: Color(0xFF6B7280), maxOpacity: 0.55),
    _PuffData(dx: -32, dy: -36, baseRadius: 13, maxRadius: 36, startT: 0.24, color: Color(0xFF6B7280), maxOpacity: 0.50),
    // Faint atmospheric outer mist
    _PuffData(dx: -4, dy: -56, baseRadius: 12, maxRadius: 46, startT: 0.28, color: Color(0xFF9CA3AF), maxOpacity: 0.40),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);

    // 1. Initial fiery flash / spark burst (0.0 to 0.18 of progress, ~550ms)
    if (progress < 0.18) {
      final double burstT = progress / 0.18;
      final double burstScale = 0.5 + 2.0 * Curves.easeOutCirc.transform(burstT);
      final double burstOpacity = (1.0 - Curves.easeInQuad.transform(burstT)).clamp(0.0, 1.0);

      final Paint burstPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.amber.withOpacity(burstOpacity * 0.9),
            Colors.deepOrangeAccent.withOpacity(burstOpacity * 0.6),
            Colors.redAccent.withOpacity(0.0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: 28 * burstScale));

      canvas.drawCircle(center, 28 * burstScale, burstPaint);
    }

    // 2. Billowing smoke puffs ("දුම් ගොඩ")
    for (final puff in _puffs) {
      if (progress < puff.startT) continue;

      final double puffT = ((progress - puff.startT) / (1.0 - puff.startT)).clamp(0.0, 1.0);

      // Expansion with ease-out cubic
      final double expandFactor = Curves.easeOutCubic.transform(puffT);
      final double currentRadius = puff.baseRadius + (puff.maxRadius - puff.baseRadius) * expandFactor;

      // Position: drifting along the thermal updraft and airflow
      final double driftFactor = Curves.easeOutQuad.transform(puffT);
      final Offset puffCenter = Offset(
        center.dx + puff.dx * driftFactor,
        center.dy + puff.dy * driftFactor,
      );

      // Opacity: rapid bloom (first 25%), steady hold (25%-55%), gentle dissipation (55%-100%)
      double currentOpacity;
      if (puffT < 0.25) {
        currentOpacity = (puffT / 0.25) * puff.maxOpacity;
      } else if (puffT <= 0.55) {
        currentOpacity = puff.maxOpacity;
      } else {
        currentOpacity = puff.maxOpacity * (1.0 - ((puffT - 0.55) / 0.45));
      }
      currentOpacity = currentOpacity.clamp(0.0, 1.0);

      // Soft vapor radial gradient: zero expensive gaussian blurs, 100% 60fps GPU performance
      final Paint puffPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            puff.color.withOpacity(currentOpacity),
            puff.color.withOpacity(currentOpacity * 0.55),
            puff.color.withOpacity(0.0),
          ],
          stops: const [0.0, 0.60, 1.0],
        ).createShader(Rect.fromCircle(center: puffCenter, radius: currentRadius));

      canvas.drawCircle(puffCenter, currentRadius, puffPaint);
    }

    // 3. Hot ember core inside the smoke (0.04 to 0.40 of progress, ~1.2s)
    if (progress >= 0.04 && progress < 0.40) {
      final double emberT = (progress - 0.04) / 0.36;
      final double emberOpacity = (1.0 - Curves.easeInQuad.transform(emberT)) * 0.65;
      final Paint emberPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFF97316).withOpacity(emberOpacity),
            const Color(0xFFEA580C).withOpacity(emberOpacity * 0.4),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: 24));

      canvas.drawCircle(center, 24, emberPaint);
    }

    // 4. Subtle floating spark embers rising into the smoke
    if (progress >= 0.05 && progress < 0.50) {
      final double sparkT = (progress - 0.05) / 0.45;
      final double sparkOpacity = (1.0 - sparkT).clamp(0.0, 1.0);
      final Paint sparkPaint = Paint()
        ..color = const Color(0xFFFBBF24).withOpacity(sparkOpacity * 0.8)
        ..style = PaintingStyle.fill;

      // 4 deterministic spark positions
      canvas.drawCircle(Offset(center.dx - 12 - 15 * sparkT, center.dy - 10 - 35 * sparkT), 1.8, sparkPaint);
      canvas.drawCircle(Offset(center.dx + 8 + 10 * sparkT, center.dy - 8 - 40 * sparkT), 1.5, sparkPaint);
      canvas.drawCircle(Offset(center.dx - 4 - 8 * sparkT, center.dy - 16 - 48 * sparkT), 1.6, sparkPaint);
      canvas.drawCircle(Offset(center.dx + 16 + 6 * sparkT, center.dy - 14 - 32 * sparkT), 1.4, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmokeCloudPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
