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
          children: [
            CustomPaint(
              size: Size(w, h),
              painter: GraphPainter(t, isCrashed),
            ),
            Positioned(
              left: x - 24, // center the 48px icon
              top: y - 24,
              child: Transform.rotate(
                angle: planeAngle,
                child: Icon(
                  Icons.flight,
                  size: 48,
                  color: isCrashed ? Colors.red : Colors.redAccent,
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
