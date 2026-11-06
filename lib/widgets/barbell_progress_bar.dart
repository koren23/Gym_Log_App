import 'package:flutter/material.dart';

/// Draws a horizontal progress bar shaped like a barbell: a thin shaft with
/// circular "plates" loading on from the left as [progress] (0.0-1.0)
/// increases. Pure geometric shapes — no illustration assets exist in this
/// app, so this matches the body diagram's (item 7) same lowest-risk
/// approach.
class BarbellProgressBar extends StatelessWidget {
  const BarbellProgressBar({
    super.key,
    required this.progress,
    required this.color,
    this.height = 28,
  });

  final double progress;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          size: Size(constraints.maxWidth, height),
          painter: _BarbellPainter(
            progress: progress.clamp(0.0, 1.0),
            color: color,
            trackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

class _BarbellPainter extends CustomPainter {
  _BarbellPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final shaftHeight = size.height * 0.28;
    final shaftY = size.height / 2;
    final plateRadius = size.height / 2;
    final sleeveLength = plateRadius * 0.9;

    // Track (empty shaft + end sleeves).
    final trackPaint = Paint()..color = trackColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          sleeveLength,
          shaftY - shaftHeight / 2,
          size.width - sleeveLength * 2,
          shaftHeight,
        ),
        Radius.circular(shaftHeight / 2),
      ),
      trackPaint,
    );
    canvas.drawCircle(
      Offset(sleeveLength * 0.5, shaftY),
      plateRadius * 0.55,
      trackPaint,
    );
    canvas.drawCircle(
      Offset(size.width - sleeveLength * 0.5, shaftY),
      plateRadius * 0.55,
      trackPaint,
    );

    if (progress <= 0) return;

    final loadedWidth = (size.width - sleeveLength * 2) * progress;
    final fillPaint = Paint()..color = color;

    // Filled shaft portion.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          sleeveLength,
          shaftY - shaftHeight / 2,
          loadedWidth,
          shaftHeight,
        ),
        Radius.circular(shaftHeight / 2),
      ),
      fillPaint,
    );

    // Plates loading on, evenly spaced across the loaded portion.
    const plateCount = 4;
    for (var i = 0; i < plateCount; i++) {
      final plateProgress = (i + 1) / plateCount;
      if (progress < plateProgress - (1 / plateCount) * 0.4) continue;
      final x = sleeveLength + loadedWidth * ((i + 0.5) / plateCount);
      final scale = (progress / plateProgress).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(x, shaftY), plateRadius * 0.85 * scale, fillPaint);
    }

    // Left end sleeve, filled once there's any progress.
    canvas.drawCircle(
      Offset(sleeveLength * 0.5, shaftY),
      plateRadius * 0.55,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BarbellPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
