import '../../models/analysis_result.dart';
import '../../models/workout_day_def.dart';

/// Day-level escalation on top of per-exercise [AnalysisEngine] findings:
/// when most of a workout day's exercises are individually stuck — and each
/// has already had its own remedy suggested — that's worth a bigger nudge
/// ("maybe rework this day") rather than yet another single-exercise tweak.
/// Deliberately conservative: never pre-empts individual fixes, only
/// escalates once they've already been surfaced.
class WorkoutDayAnalyzer {
  const WorkoutDayAnalyzer();

  static const int minStuckExercises = 3;
  static const double minStuckFraction = 0.6;

  /// [exerciseFindings] should be exactly the (non-null) findings for the
  /// exercises that belong to [day] — see how `proactiveFindingsProvider`
  /// groups findings by day before calling this.
  AnalysisFinding? analyze({
    required WorkoutDayDef day,
    required List<AnalysisFinding> exerciseFindings,
  }) {
    if (exerciseFindings.isEmpty) return null;

    final stuck = exerciseFindings.where((f) => f.isPlateaued).toList();
    if (stuck.isEmpty) return null;

    // Only escalate once every stuck exercise already has its own remedy —
    // a day-level nudge should never pre-empt or duplicate an
    // individual-exercise suggestion, only pick up once those are
    // exhausted.
    final allHaveOwnRemedy = stuck.every((f) => f.kind != SuggestionKind.none);
    if (!allHaveOwnRemedy) return null;

    final meetsCount = stuck.length >= minStuckExercises;
    final meetsFraction =
        exerciseFindings.length >= 2 &&
        stuck.length / exerciseFindings.length >= minStuckFraction;
    if (!meetsCount && !meetsFraction) return null;

    return AnalysisFinding(
      subjectName: day.label,
      weightTrend: TrendDirection.flat,
      ratingTrend: TrendDirection.flat,
      isPlateaued: true,
      repRangeChanged: false,
      message:
          '${day.label} — ${stuck.length} of ${exerciseFindings.length} '
          "exercises have been stuck lately, even after individual tweaks. "
          "Might be worth reworking this day's mix.",
      suggestion: 'Review ${day.label}\'s exercises.',
      priority: 4,
      kind: SuggestionKind.changeWorkoutDay,
      payload: WorkoutDaySuggestionPayload(dayId: day.id),
    );
  }
}
