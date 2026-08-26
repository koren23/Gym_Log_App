enum TrendDirection { up, flat, down, unknown }

class AnalysisFinding {
  const AnalysisFinding({
    required this.subjectName,
    required this.weightTrend,
    required this.ratingTrend,
    required this.isPlateaued,
    required this.repRangeChanged,
    required this.message,
    this.suggestion,
    this.priority = 0,
  });

  /// Exercise name or muscle-group label this finding is about.
  final String subjectName;
  final TrendDirection weightTrend;
  final TrendDirection ratingTrend;
  final bool isPlateaued;
  final bool repRangeChanged;

  /// Human-readable summary paragraph.
  final String message;

  /// Short actionable suggestion, if any (e.g. "Try 8-10 reps instead of
  /// 6-8" or "Swap for Incline dumbbell bench press").
  final String? suggestion;

  /// Higher = more urgent/important; used to pick the single banner shown
  /// on the home screen when multiple findings exist.
  final int priority;
}
