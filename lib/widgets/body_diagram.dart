import 'package:flutter/material.dart';

import '../core/constants/body_zones.dart';

/// A front/back body silhouette, colored per [BodyZone] by [scores]
/// (expected roughly in `[0, 2]`, where `1.0` reads as "at your own
/// historical average" — see `muscle_balance.dart`'s scoring), drawn as a
/// proper anatomical outline (curved torso/limb shapes, not blocky
/// rectangles) so each colored region reads as a body part at a glance.
/// Tapping a zone calls [onZoneTap] for drill-down into its fine-grained
/// muscle breakdown.
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
          aspectRatio: 0.5,
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
    // 0 -> red, 1 -> amber/green boundary, 2 -> green — same 3-stop red ->
    // orange -> green ramp as a muscle-recovery heatmap, just driven by
    // training-volume score here rather than recovery time.
    final t = (score / 2).clamp(0.0, 1.0);
    if (t < 0.5) {
      return Color.lerp(Colors.redAccent, Colors.orange, t * 2)!;
    }
    return Color.lerp(Colors.orange, Colors.green, (t - 0.5) * 2)!;
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
    final rects = _zoneRectFractions(zone, isFront);
    if (rects.isEmpty || onTap == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          for (final rect in rects)
            Positioned(
              left: rect.left * constraints.maxWidth,
              top: rect.top * constraints.maxHeight,
              width: rect.width * constraints.maxWidth,
              height: rect.height * constraints.maxHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTap,
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints an anatomically-shaped humanoid silhouette — curved torso and
/// tapered limb regions rather than stacked rectangles — with each visible
/// [BodyZone] filled by [zoneColors]. Coordinates are fractions of the
/// painted size, built once per side (right) and mirrored for the left via
/// a canvas flip, since every zone here applies equally to both sides.
class BodyDiagramPainter extends CustomPainter {
  BodyDiagramPainter({required this.isFront, required this.zoneColors});

  final bool isFront;
  final Map<BodyZone, Color> zoneColors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Offset p(double fx, double fy) => Offset(fx * w, fy * h);
    Color colorOf(BodyZone z) => zoneColors[z] ?? const Color(0xFFE0E0E0);

    void fillMirrored(Path rightSide, Color color) {
      final paint = Paint()..color = color;
      canvas.drawPath(rightSide, paint);
      canvas.save();
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
      canvas.drawPath(rightSide, paint);
      canvas.restore();
    }

    Path limb({
      required Offset topOuter,
      required Offset topInner,
      required Offset bulgeOuter,
      required Offset bulgeInner,
      required Offset bottomOuter,
      required Offset bottomInner,
    }) => Path()
      ..moveTo(topInner.dx, topInner.dy)
      ..quadraticBezierTo(
        bulgeInner.dx,
        bulgeInner.dy,
        bottomInner.dx,
        bottomInner.dy,
      )
      ..lineTo(bottomOuter.dx, bottomOuter.dy)
      ..quadraticBezierTo(
        bulgeOuter.dx,
        bulgeOuter.dy,
        topOuter.dx,
        topOuter.dy,
      )
      ..close();

    // Head + neck (decorative, not a scored zone).
    canvas.drawOval(
      Rect.fromLTWH(w * 0.41, 0, w * 0.18, h * 0.11),
      Paint()..color = const Color(0xFFBDBDBD),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.465, h * 0.10, w * 0.07, h * 0.04),
      Paint()..color = const Color(0xFFBDBDBD),
    );

    // Shoulders (both views) — a rounded cap either side of the neck.
    final shoulderOval = Path()
      ..addOval(Rect.fromCenter(center: p(0.78, 0.15), width: w * 0.18, height: h * 0.10));
    fillMirrored(shoulderOval, colorOf(BodyZone.shoulders));

    final armRight = limb(
      topOuter: p(0.84, 0.165),
      topInner: p(0.735, 0.19),
      bulgeOuter: p(0.90, 0.30),
      bulgeInner: p(0.80, 0.31),
      bottomOuter: p(0.855, 0.46),
      bottomInner: p(0.785, 0.46),
    );
    final legFrontRight = limb(
      topOuter: p(0.70, 0.49),
      topInner: p(0.515, 0.49),
      bulgeOuter: p(0.735, 0.62),
      bulgeInner: p(0.535, 0.63),
      bottomOuter: p(0.675, 0.92),
      bottomInner: p(0.555, 0.92),
    );
    final legBackRight = limb(
      topOuter: p(0.72, 0.485),
      topInner: p(0.50, 0.49),
      bulgeOuter: p(0.755, 0.58),
      bulgeInner: p(0.475, 0.605),
      bottomOuter: p(0.675, 0.92),
      bottomInner: p(0.555, 0.92),
    );

    if (isFront) {
      final chest = Path()
        ..moveTo(w * 0.27, h * 0.19)
        ..cubicTo(
          w * 0.195,
          h * 0.225,
          w * 0.20,
          h * 0.30,
          w * 0.29,
          h * 0.335,
        )
        ..lineTo(w * 0.71, h * 0.335)
        ..cubicTo(
          w * 0.80,
          h * 0.30,
          w * 0.805,
          h * 0.225,
          w * 0.73,
          h * 0.19,
        )
        ..close();
      canvas.drawPath(chest, Paint()..color = colorOf(BodyZone.chest));

      final core = Path()
        ..moveTo(w * 0.30, h * 0.335)
        ..lineTo(w * 0.70, h * 0.335)
        ..cubicTo(w * 0.735, h * 0.40, w * 0.70, h * 0.465, w * 0.655, h * 0.485)
        ..lineTo(w * 0.345, h * 0.485)
        ..cubicTo(w * 0.30, h * 0.465, w * 0.265, h * 0.40, w * 0.30, h * 0.335)
        ..close();
      canvas.drawPath(core, Paint()..color = colorOf(BodyZone.core));

      fillMirrored(armRight, colorOf(BodyZone.bicepsForearm));
      fillMirrored(legFrontRight, colorOf(BodyZone.quads));
    } else {
      final back = Path()
        ..moveTo(w * 0.22, h * 0.19)
        ..cubicTo(w * 0.175, h * 0.28, w * 0.195, h * 0.385, w * 0.28, h * 0.485)
        ..lineTo(w * 0.72, h * 0.485)
        ..cubicTo(w * 0.805, h * 0.385, w * 0.825, h * 0.28, w * 0.78, h * 0.19)
        ..close();
      canvas.drawPath(back, Paint()..color = colorOf(BodyZone.back));

      fillMirrored(armRight, colorOf(BodyZone.triceps));
      fillMirrored(legBackRight, colorOf(BodyZone.glutesHamsCalves));
    }
  }

  @override
  bool shouldRepaint(covariant BodyDiagramPainter oldDelegate) =>
      oldDelegate.isFront != isFront || oldDelegate.zoneColors != zoneColors;
}

/// Fractional (0-1) bounding boxes for [zone]'s tap area(s) within the
/// painted silhouette — one rect for a centered zone (chest/core/back),
/// two (mirrored) for a bilateral one (shoulders/arms/legs). Roughly, not
/// pixel-exactly, matches [BodyDiagramPainter]'s shapes — close enough for
/// a tap target. Empty if [zone] isn't shown on this side.
List<Rect> _zoneRectFractions(BodyZone zone, bool isFront) {
  const shoulderRight = Rect.fromLTWH(0.69, 0.10, 0.18, 0.10);
  const shoulderLeft = Rect.fromLTWH(0.13, 0.10, 0.18, 0.10);
  const armRight = Rect.fromLTWH(0.735, 0.165, 0.17, 0.30);
  const armLeft = Rect.fromLTWH(0.095, 0.165, 0.17, 0.30);

  if (isFront) {
    switch (zone) {
      case BodyZone.shoulders:
        return const [shoulderRight, shoulderLeft];
      case BodyZone.chest:
        return const [Rect.fromLTWH(0.27, 0.19, 0.46, 0.145)];
      case BodyZone.bicepsForearm:
        return const [armRight, armLeft];
      case BodyZone.core:
        return const [Rect.fromLTWH(0.27, 0.335, 0.46, 0.15)];
      case BodyZone.quads:
        return const [
          Rect.fromLTWH(0.515, 0.49, 0.22, 0.43),
          Rect.fromLTWH(0.265, 0.49, 0.22, 0.43),
        ];
      default:
        return const [];
    }
  } else {
    switch (zone) {
      case BodyZone.shoulders:
        return const [shoulderRight, shoulderLeft];
      case BodyZone.triceps:
        return const [armRight, armLeft];
      case BodyZone.back:
        return const [Rect.fromLTWH(0.18, 0.19, 0.64, 0.295)];
      case BodyZone.glutesHamsCalves:
        return const [
          Rect.fromLTWH(0.50, 0.485, 0.26, 0.435),
          Rect.fromLTWH(0.24, 0.485, 0.26, 0.435),
        ];
      default:
        return const [];
    }
  }
}
