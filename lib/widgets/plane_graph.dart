import 'package:flutter/material.dart';
import 'dart:math' as math;

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
        // Asymptotic progress so it never quite hits 1.0 but gets very close.
        double progress = 1.0 - (1.0 / (1.0 + (multiplier - 1.0) * 0.15));
        if (progress < 0) progress = 0;
        if (progress > 1.0) progress = 1.0;
        
        double w = constraints.maxWidth;
        double h = constraints.maxHeight;
        double t = progress;

        // Use a fixed quadratic bezier curve for the flight path.
        // P0 = (0, h), P1 = (w * 0.8, h), P2 = (w, 0)
        // x(t) = (1-t)^2 * 0 + 2(1-t)t * (w * 0.8) + t^2 * w
        // y(t) = (1-t)^2 * h + 2(1-t)t * h + t^2 * 0 = h * (1 - t^2)
        
        double x = 2 * (1 - t) * t * (w * 0.8) + (t * t * w);
        double y = h * (1 - t * t);

        // Calculate tangent (derivative) at t
        // dx/dt = 1.6 * w * (1 - 2t) + 2 * t * w = w * (1.6 - 1.2 * t)
        // dy/dt = -2 * t * h
        double dx = w * (1.6 - 1.2 * t);
        double dy = -2 * t * h;
        
        // Icons.flight default points straight UP.
        // We add pi/2 (90 degrees) to the computed angle so the plane's nose points along the tangent.
        double planeAngle = math.atan2(dy, dx) + (math.pi / 2);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: Size(w, h),
              painter: GraphPainter(t, isCrashed),
            ),
            Positioned(
              left: x - 80,
              top: y - 80,
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
    final paint = Paint()
      ..color = isCrashed ? Colors.red.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    double w = size.width;
    double h = size.height;

    final path = Path();
    path.moveTo(0, h);
    
    // Draw the curve up to t
    // We can't just draw the full bezier, we must draw a segment from 0 to t.
    // The control points for the sub-curve from 0 to t of a quadratic bezier are:
    // Q0 = P0
    // Q1 = (1-t)*P0 + t*P1
    // Q2 = B(t)
    
    double p1x = w * 0.8;
    double p1y = h;
    
    double q1x = (1 - t) * 0 + t * p1x;
    double q1y = (1 - t) * h + t * p1y; // Since P0y and P1y are both h, Q1y is just h.
    
    double q2x = 2 * (1 - t) * t * p1x + (t * t * w);
    double q2y = h * (1 - t * t);
    
    path.quadraticBezierTo(q1x, q1y, q2x, q2y);

    canvas.drawPath(path, paint);

    // Fill underneath the curve
    final fillPaint = Paint()
      ..color = isCrashed ? Colors.red.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2)
      ..style = PaintingStyle.fill;
      
    final fillPath = Path.from(path);
    fillPath.lineTo(q2x, h);
    fillPath.lineTo(0, h);
    fillPath.close();
    
    canvas.drawPath(fillPath, fillPaint);
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
