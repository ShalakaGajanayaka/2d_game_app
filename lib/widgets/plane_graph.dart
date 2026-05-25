import 'package:flutter/material.dart';

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
        // This simulates the graph "zooming out" as multiplier gets larger.
        double progress = 1.0 - (1.0 / (1.0 + (multiplier - 1.0) * 0.15));
        if (progress < 0) progress = 0;
        if (progress > 1.0) progress = 1.0;
        
        // Calculate curve position (linear interpolation of the asymptotic progress)
        double x = constraints.maxWidth * progress;
        double y = constraints.maxHeight - (constraints.maxHeight * progress);

        return Stack(
          children: [
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: GraphPainter(progress, isCrashed),
            ),
            Positioned(
              left: x - 24, // center the 48px icon
              top: y - 24,
              child: Transform.rotate(
                angle: -0.5, // slightly tilted up
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
  final double progress;
  final bool isCrashed;

  GraphPainter(this.progress, this.isCrashed);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isCrashed ? Colors.red.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    final path = Path();
    path.moveTo(0, size.height);
    
    // Draw a curved path up to current progress
    double endX = size.width * progress;
    double endY = size.height - (size.height * progress);
    
    // Quadratic bezier to make it look like an exponential curve starting from bottom left
    path.quadraticBezierTo(endX * 0.6, size.height, endX, endY);

    canvas.drawPath(path, paint);

    // Fill underneath the curve
    final fillPaint = Paint()
      ..color = isCrashed ? Colors.red.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2)
      ..style = PaintingStyle.fill;
      
    final fillPath = Path.from(path);
    fillPath.lineTo(endX, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isCrashed != isCrashed;
  }
}
