import 'package:flutter/material.dart';

import '../core/constants/body_zones.dart';

/// A simplified front/back body silhouette, colored per [BodyZone] by
/// [scores] (expected roughly in `[0, 2]`, where `1.0` reads as "at your
/// own historical average" — see `muscle_balance.dart`'s scoring). Built
/// from basic geometric shapes (no illustration assets exist in this app —
/// same lowest-risk choice as the XP barbell bar). Tapping a zone calls
/// [onZoneTap] for drill-down into its fine-grained muscle breakdown.
class BodyDiagramWidget extends StatefulWidget {
  const BodyDiagramWidget({
    super.key,
    required this.scores,
    this.onZoneTap,
  });

  final Map<BodyZone, double> scores;
  final ValueChanged<BodyZone>? onZoneTap;

  @override
  State<BodyDiagramWidget> createState() => _BodyDiagramWidgetState();
}

class _BodyDiagramWidgetState extends State<BodyDiagramWidget> {
  bool _showFront = true;

  @override
  Widget build(BuildContext context) {
    final zones = BodyZone.values.where(
      (z) => _showFront ? bodyZoneShowsFront(z) : bodyZoneShowsBack(z),
    );
    return Column(
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Front')),
            ButtonSegment(value: false, label: Text('Back')),
          ],
          selected: {_showFront},
          onSelectionChanged: (s) => setState(() => _showFront = s.first),
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 0.55,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: BodyDiagramPainter(
                    isFront: _showFront,
                    zoneColors: {
                      for (final z in BodyZone.values)
                        z: _colorForScore(context, widget.scores[z]),
                    },
                  ),
                ),
              ),
              for (final zone in zones)
                Positioned.fill(
                  child: _ZoneTapArea(
                    zone: zone,
                    isFront: _showFront,
                    onTap: widget.onZoneTap == null
                        ? null
                        : () => widget.onZoneTap!(zone),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (final zone in zones)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colorForScore(context, widget.scores[zone]),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.scores[zone] == null
                        ? '${kBodyZoneLabels[zone]!} (not enough data)'
                        : kBodyZoneLabels[zone]!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Color _colorForScore(BuildContext context, double? score) {
    if (score == null) {
      // Deliberately unknown/not-enough-data, distinct from the red-green
      // scale below so it reads as "no signal yet" rather than "zero".
      return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
    // 0 -> red, 1 -> amber/green boundary, 2 -> green.
    final t = (score / 2).clamp(0.0, 1.0);
    return Color.lerp(Colors.redAccent, Colors.green, t)!;
  }
}

class _ZoneTapArea extends StatelessWidget {
  const _ZoneTapArea({
    required this.zone,
    required this.isFront,
    required this.onTap,
  });

  final BodyZone zone;
  final bool isFront;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rect = _zoneRectFraction(zone, isFront);
    if (rect == null || onTap == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => Positioned(
        left: rect.left * constraints.maxWidth,
        top: rect.top * constraints.maxHeight,
        width: rect.width * constraints.maxWidth,
        height: rect.height * constraints.maxHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Paints a simplified humanoid silhouette with each visible [BodyZone]'s
/// region filled by [zoneColors]. Coordinates are fractions of the
/// painted size, matching [_zoneRectFraction]'s tap areas.
class BodyDiagramPainter extends CustomPainter {
  BodyDiagramPainter({required this.isFront, required this.zoneColors});

  final bool isFront;
  final Map<BodyZone, Color> zoneColors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    void fillRRect(Rect fractionRect, Color color, [double radius = 10]) {
      final rect = Rect.fromLTWH(
        fractionRect.left * w,
        fractionRect.top * h,
        fractionRect.width * w,
        fractionRect.height * h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = color,
      );
    }

    // Head.
    canvas.drawOval(
      Rect.fromLTWH(w * 0.38, 0, w * 0.24, h * 0.1),
      Paint()..color = const Color(0xFFBDBDBD),
    );

    for (final zone in BodyZone.values) {
      final showing = isFront ? bodyZoneShowsFront(zone) : bodyZoneShowsBack(zone);
      if (!showing) continue;
      final color = zoneColors[zone] ?? const Color(0xFFE0E0E0);
      final rect = _zoneRectFraction(zone, isFront);
      if (rect == null) continue;
      fillRRect(rect, color);
    }
  }

  @override
  bool shouldRepaint(covariant BodyDiagramPainter oldDelegate) =>
      oldDelegate.isFront != isFront || oldDelegate.zoneColors != zoneColors;
}

/// Fractional (0-1) bounding box for [zone] within the painted silhouette,
/// shared by the painter and the tap-area overlay so colors and hit zones
/// always line up. Null if [zone] isn't shown on this side.
Rect? _zoneRectFraction(BodyZone zone, bool isFront) {
  if (isFront) {
    switch (zone) {
      case BodyZone.shoulders:
        return const Rect.fromLTWH(0.18, 0.12, 0.64, 0.07);
      case BodyZone.chest:
        return const Rect.fromLTWH(0.28, 0.20, 0.44, 0.1);
      case BodyZone.bicepsForearm:
        return const Rect.fromLTWH(0.1, 0.19, 0.16, 0.28);
      case BodyZone.core:
        return const Rect.fromLTWH(0.32, 0.31, 0.36, 0.14);
      case BodyZone.quads:
        return const Rect.fromLTWH(0.28, 0.47, 0.44, 0.28);
      default:
        return null;
    }
  } else {
    switch (zone) {
      case BodyZone.shoulders:
        return const Rect.fromLTWH(0.18, 0.12, 0.64, 0.07);
      case BodyZone.triceps:
        return const Rect.fromLTWH(0.1, 0.19, 0.16, 0.28);
      case BodyZone.back:
        return const Rect.fromLTWH(0.28, 0.20, 0.44, 0.25);
      case BodyZone.glutesHamsCalves:
        return const Rect.fromLTWH(0.28, 0.47, 0.44, 0.28);
      default:
        return null;
    }
  }
}
