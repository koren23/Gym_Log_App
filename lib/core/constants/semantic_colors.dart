import 'package:flutter/material.dart';

/// Green/red/amber accents for the log-workout exercise-tile trend stripe
/// (see `TileTrend`). This is the app's first semantic-status color — every
/// other trend color today (`WeeklyInsightBox`'s green/orange/blueGrey,
/// `SuggestionCard`'s container tints) is a hardcoded literal that doesn't
/// adapt to the user's chosen theme preset.
class SemanticTrendColors {
  const SemanticTrendColors({
    required this.improving,
    required this.stuck,
    required this.steady,
  });

  final Color improving;
  final Color stuck;
  final Color steady;
}

/// Derives [SemanticTrendColors] from [background]'s own brightness, the
/// same way `app.dart` derives the whole theme's brightness from
/// `AppColors.background` — so the stripe reads correctly against both
/// light presets (e.g. Forest) and dark ones (e.g. Midnight, Charcoal)
/// without needing per-preset configuration. Hues are fixed (green ~130°,
/// red ~4°, amber ~40°); only saturation/lightness adapt.
SemanticTrendColors semanticTrendColors(Color background) {
  final isDark =
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  final lightness = isDark ? 0.55 : 0.42;
  final saturation = isDark ? 0.65 : 0.55;
  return SemanticTrendColors(
    improving: HSLColor.fromAHSL(1, 130, saturation, lightness).toColor(),
    stuck: HSLColor.fromAHSL(1, 4, saturation, lightness).toColor(),
    steady: HSLColor.fromAHSL(1, 40, saturation, lightness).toColor(),
  );
}
