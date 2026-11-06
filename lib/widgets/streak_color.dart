import 'package:flutter/material.dart';

/// Color-codes a current streak (in weeks): no streak reads neutral, a
/// short one reads warm, a long one reads green, ramping fully in by 8
/// weeks. Shared by the Stats tab's Consistency card and the Home tab's
/// [StreakBanner].
Color streakColor(int streakWeeks) {
  if (streakWeeks <= 0) return Colors.grey;
  final t = (streakWeeks / 8).clamp(0.0, 1.0);
  return Color.lerp(Colors.orange, Colors.green, t)!;
}
