import 'package:flutter/material.dart';

import '../core/constants/body_zones.dart';

/// Front + back body silhouettes shown side by side, each muscle region
/// colored by [scores] (expected roughly in `[0, 2]`, where `1.0` reads as
/// "at your own historical average" — see `muscle_balance.dart`'s scoring).
/// Drawn as a neutral body outline with individually-outlined, segmented
/// muscle regions layered on top — echoing a classic front/back muscle-map
/// poster rather than blocky rectangles. Tapping a region calls [onZoneTap]
/// for drill-down into its fine-grained muscle breakdown.
class BodyDiagramWidget extends StatelessWidget {
  const BodyDiagramWidget({super.key, required this.scores, this.onZoneTap});

  final Map<BodyZone, double> scores;
  final ValueChanged<BodyZone>? onZoneTap;

  @override
  Widget build(BuildContext context) {
    final zoneColors = {
      for (final z in BodyZone.values) z: _colorForScore(context, scores[z]),
    };
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _BodyHalf(
                isFront: true,
                zoneColors: zoneColors,
                onZoneTap: onZoneTap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BodyHalf(
                isFront: false,
                zoneColors: zoneColors,
                onZoneTap: onZoneTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 2,
          alignment: WrapAlignment.center,
          children: [
            for (final zone in BodyZone.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: zoneColors[zone],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    scores[zone] == null
                        ? '${kBodyZoneLabels[zone]!} (no data)'
                        : kBodyZoneLabels[zone]!,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// "Safe"/progress-reading green at `score == 1`ish, red at `0`, gray when
/// there isn't yet enough history to compute a score at all.
Color _colorForScore(BuildContext context, double? score) {
  if (score == null) {
    return Theme.of(context).colorScheme.surfaceContainerHighest;
  }
  final t = (score / 2).clamp(0.0, 1.0);
  if (t < 0.5) {
    return Color.lerp(Colors.redAccent, Colors.orange, t * 2)!;
  }
  return Color.lerp(Colors.orange, Colors.green, (t - 0.5) * 2)!;
}

/// One silhouette (front or back) plus its tappable muscle-region overlays,
/// sized to roughly a real body's proportions so the pair reads as one
/// compact, near-square figure once placed side by side by
/// [BodyDiagramWidget].
class _BodyHalf extends StatelessWidget {
  const _BodyHalf({
    required this.isFront,
    required this.zoneColors,
    required this.onZoneTap,
  });

  final bool isFront;
  final Map<BodyZone, Color> zoneColors;
  final ValueChanged<BodyZone>? onZoneTap;

  @override
  Widget build(BuildContext context) {
    final zones = BodyZone.values.where(
      (z) => isFront ? bodyZoneShowsFront(z) : bodyZoneShowsBack(z),
    );
    return AspectRatio(
      aspectRatio: 0.46,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: BodyDiagramPainter(
                isFront: isFront,
                zoneColors: zoneColors,
              ),
            ),
          ),
          if (onZoneTap != null)
            for (final zone in zones)
              Positioned.fill(
                child: _ZoneTapArea(
                  zone: zone,
                  isFront: isFront,
                  onTap: () => onZoneTap!(zone),
                ),
              ),
        ],
      ),
    );
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rects = _zoneRectFractions(zone, isFront);
    if (rects.isEmpty) return const SizedBox.shrink();
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

/// Paints one front- or back-view humanoid silhouette: a neutral skin-tone
/// base body (head/neck/torso/arms/legs) with individually outlined muscle
/// regions layered on top, each filled by its owning [BodyZone]'s color
/// from [zoneColors]. Coordinates are fractions of the painted size, built
/// once for the right side and mirrored across the vertical centerline for
/// bilateral regions, since the body is symmetric.
class BodyDiagramPainter extends CustomPainter {
  BodyDiagramPainter({required this.isFront, required this.zoneColors});

  final bool isFront;
  final Map<BodyZone, Color> zoneColors;

  static const _skinColor = Color(0xFFEBE3D7);
  static const _outlineColor = Color(0x662A241C);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Offset p(double fx, double fy) => Offset(fx * w, fy * h);
    Color colorOf(BodyZone z) => zoneColors[z] ?? const Color(0xFFE0E0E0);

    void fillAndStroke(Path path, Color fill, {double strokeWidth = 1.1}) {
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = _outlineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }

    void fillAndStrokeMirrored(Path rightSide, Color fill) {
      fillAndStroke(rightSide, fill);
      canvas.save();
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
      fillAndStroke(rightSide, fill);
      canvas.restore();
    }

    void strokeMirrored(Path rightSide) {
      final paint = Paint()
        ..color = _outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawPath(rightSide, paint);
      canvas.save();
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
      canvas.drawPath(rightSide, paint);
      canvas.restore();
    }

    Path capsule({
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

    // ---- base silhouette (shared between front/back) ----
    final head = Path()
      ..addOval(Rect.fromLTWH(w * 0.39, h * 0.012, w * 0.22, h * 0.10));
    fillAndStroke(head, _skinColor);

    final neck = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.455, h * 0.10, w * 0.09, h * 0.035),
          Radius.circular(w * 0.02),
        ),
      );
    fillAndStroke(neck, _skinColor);

    final torso = Path()
      ..moveTo(w * 0.305, h * 0.135)
      ..quadraticBezierTo(w * 0.27, h * 0.24, w * 0.35, h * 0.335)
      ..quadraticBezierTo(w * 0.325, h * 0.42, w * 0.37, h * 0.50)
      ..lineTo(w * 0.63, h * 0.50)
      ..quadraticBezierTo(w * 0.675, h * 0.42, w * 0.65, h * 0.335)
      ..quadraticBezierTo(w * 0.73, h * 0.24, w * 0.695, h * 0.135)
      ..close();
    fillAndStroke(torso, _skinColor);

    final arm = capsule(
      topOuter: p(0.815, 0.155),
      topInner: p(0.705, 0.145),
      bulgeOuter: p(0.85, 0.28),
      bulgeInner: p(0.745, 0.285),
      bottomOuter: p(0.795, 0.51),
      bottomInner: p(0.73, 0.505),
    );
    fillAndStrokeMirrored(arm, _skinColor);

    final leg = capsule(
      topOuter: p(0.635, 0.495),
      topInner: p(0.505, 0.50),
      bulgeOuter: p(0.665, 0.64),
      bulgeInner: p(0.525, 0.645),
      bottomOuter: p(0.60, 0.97),
      bottomInner: p(0.535, 0.97),
    );
    fillAndStrokeMirrored(leg, _skinColor);

    final deltoid = Path()
      ..addOval(
        Rect.fromCenter(
          center: p(0.765, 0.175),
          width: w * 0.12,
          height: h * 0.075,
        ),
      );
    fillAndStrokeMirrored(deltoid, colorOf(BodyZone.shoulders));

    if (isFront) {
      final pec = Path()
        ..moveTo(w * 0.50, h * 0.165)
        ..quadraticBezierTo(w * 0.585, h * 0.155, w * 0.655, h * 0.185)
        ..quadraticBezierTo(w * 0.685, h * 0.225, w * 0.625, h * 0.255)
        ..quadraticBezierTo(w * 0.555, h * 0.27, w * 0.50, h * 0.255)
        ..close();
      fillAndStrokeMirrored(pec, colorOf(BodyZone.chest));

      // Abs — 3 rows x 2 columns, with a gap at the centerline and between
      // rows for the "segmented" muscle-map look.
      for (final rowTop in const [0.285, 0.345, 0.405]) {
        final block = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.435, h * rowTop, w * 0.058, h * 0.05),
              Radius.circular(w * 0.012),
            ),
          );
        fillAndStrokeMirrored(block, colorOf(BodyZone.core));
      }
      final oblique = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.365, h * 0.32, w * 0.045, h * 0.12),
            Radius.circular(w * 0.018),
          ),
        );
      fillAndStrokeMirrored(oblique, colorOf(BodyZone.core));

      final bicep = Path()
        ..addOval(
          Rect.fromCenter(
            center: p(0.795, 0.255),
            width: w * 0.075,
            height: h * 0.11,
          ),
        );
      fillAndStrokeMirrored(bicep, colorOf(BodyZone.bicepsForearm));

      final forearm = Path()
        ..addOval(
          Rect.fromCenter(
            center: p(0.765, 0.42),
            width: w * 0.06,
            height: h * 0.13,
          ),
        );
      fillAndStrokeMirrored(forearm, colorOf(BodyZone.bicepsForearm));

      // Quad (thigh only — the shin stays bare, matching a typical front
      // muscle map where no major muscle reads there).
      final quad = capsule(
        topOuter: p(0.625, 0.50),
        topInner: p(0.515, 0.505),
        bulgeOuter: p(0.65, 0.615),
        bulgeInner: p(0.535, 0.625),
        bottomOuter: p(0.60, 0.73),
        bottomInner: p(0.535, 0.735),
      );
      fillAndStrokeMirrored(quad, colorOf(BodyZone.quads));
      final quadLine = Path()
        ..moveTo(w * 0.565, h * 0.52)
        ..lineTo(w * 0.555, h * 0.72);
      strokeMirrored(quadLine);
    } else {
      final traps = Path()
        ..moveTo(w * 0.50, h * 0.125)
        ..quadraticBezierTo(w * 0.62, h * 0.15, w * 0.645, h * 0.205)
        ..quadraticBezierTo(w * 0.555, h * 0.255, w * 0.50, h * 0.265)
        ..quadraticBezierTo(w * 0.445, h * 0.255, w * 0.355, h * 0.205)
        ..quadraticBezierTo(w * 0.38, h * 0.15, w * 0.50, h * 0.125)
        ..close();
      fillAndStroke(traps, colorOf(BodyZone.back));

      final lat = Path()
        ..moveTo(w * 0.63, h * 0.22)
        ..quadraticBezierTo(w * 0.69, h * 0.30, w * 0.645, h * 0.40)
        ..quadraticBezierTo(w * 0.58, h * 0.42, w * 0.555, h * 0.38)
        ..quadraticBezierTo(w * 0.57, h * 0.28, w * 0.63, h * 0.22)
        ..close();
      fillAndStrokeMirrored(lat, colorOf(BodyZone.back));

      final lowerBack = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.43, h * 0.42, w * 0.14, h * 0.07),
            Radius.circular(w * 0.02),
          ),
        );
      fillAndStroke(lowerBack, colorOf(BodyZone.back));

      final tricep = Path()
        ..addOval(
          Rect.fromCenter(
            center: p(0.795, 0.255),
            width: w * 0.075,
            height: h * 0.14,
          ),
        );
      fillAndStrokeMirrored(tricep, colorOf(BodyZone.triceps));

      // Forearm (back view) — no separate back-forearm zone, so it shares
      // the triceps zone's color like the rest of the back-arm.
      final forearmBack = Path()
        ..addOval(
          Rect.fromCenter(
            center: p(0.765, 0.42),
            width: w * 0.06,
            height: h * 0.13,
          ),
        );
      fillAndStrokeMirrored(forearmBack, colorOf(BodyZone.triceps));

      final glute = Path()
        ..addOval(
          Rect.fromCenter(
            center: p(0.575, 0.535),
            width: w * 0.12,
            height: h * 0.08,
          ),
        );
      fillAndStrokeMirrored(glute, colorOf(BodyZone.glutesHamsCalves));

      final hamstring = Path()
        ..addOval(
          Rect.fromCenter(
            center: p(0.575, 0.655),
            width: w * 0.10,
            height: h * 0.14,
          ),
        );
      fillAndStrokeMirrored(hamstring, colorOf(BodyZone.glutesHamsCalves));

      final calf = Path()
        ..addOval(
          Rect.fromCenter(
            center: p(0.575, 0.86),
            width: w * 0.085,
            height: h * 0.11,
          ),
        );
      fillAndStrokeMirrored(calf, colorOf(BodyZone.glutesHamsCalves));
    }
  }

  @override
  bool shouldRepaint(covariant BodyDiagramPainter oldDelegate) =>
      oldDelegate.isFront != isFront || oldDelegate.zoneColors != zoneColors;
}

/// Fractional (0-1) bounding boxes for [zone]'s tap area(s) within a single
/// silhouette — one rect for a centered zone (chest/core/back), two
/// (mirrored) for a bilateral one (shoulders/arms/legs). Roughly, not
/// pixel-exactly, matches [BodyDiagramPainter]'s shapes — close enough for
/// a tap target. Empty if [zone] isn't shown on this side.
List<Rect> _zoneRectFractions(BodyZone zone, bool isFront) {
  const shoulderRight = Rect.fromLTWH(0.705, 0.135, 0.12, 0.08);
  const shoulderLeft = Rect.fromLTWH(0.175, 0.135, 0.12, 0.08);
  const armRight = Rect.fromLTWH(0.735, 0.20, 0.125, 0.285);
  const armLeft = Rect.fromLTWH(0.14, 0.20, 0.125, 0.285);

  if (isFront) {
    switch (zone) {
      case BodyZone.shoulders:
        return const [shoulderRight, shoulderLeft];
      case BodyZone.chest:
        return const [Rect.fromLTWH(0.345, 0.155, 0.31, 0.115)];
      case BodyZone.bicepsForearm:
        return const [armRight, armLeft];
      case BodyZone.core:
        return const [Rect.fromLTWH(0.365, 0.28, 0.27, 0.18)];
      case BodyZone.quads:
        return const [
          Rect.fromLTWH(0.515, 0.50, 0.15, 0.235),
          Rect.fromLTWH(0.335, 0.50, 0.15, 0.235),
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
        return const [Rect.fromLTWH(0.355, 0.12, 0.29, 0.37)];
      case BodyZone.glutesHamsCalves:
        return const [
          Rect.fromLTWH(0.515, 0.495, 0.15, 0.42),
          Rect.fromLTWH(0.335, 0.495, 0.15, 0.42),
        ];
      default:
        return const [];
    }
  }
}
