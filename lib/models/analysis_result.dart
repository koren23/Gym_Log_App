import 'exercise.dart';

enum TrendDirection { up, flat, down, unknown }

/// The kind of actionable change a finding suggests, if any. Drives which
/// button (if any) a suggestion surface shows and what accepting it does —
/// see [SuggestionPayload] for the kind-specific data needed to apply it.
enum SuggestionKind {
  /// Plain informational finding — no actionable suggestion.
  none,
  deload,
  changeRepRangeOverall,
  changeRepRangeForSet,
  changeWeightForSet,
  changeTotalWeight,
  changeExercise,
  changeWorkoutDay,
}

/// Structured, kind-specific data for a [SuggestionKind] other than
/// [SuggestionKind.none] — carries exactly what's needed to apply the
/// suggestion (pre-fill a field, swap an exercise, ...), not just describe
/// it in prose.
sealed class SuggestionPayload {
  const SuggestionPayload();
}

/// Used by [SuggestionKind.changeRepRangeOverall] and
/// [SuggestionKind.changeRepRangeForSet].
class RepRangeSuggestionPayload extends SuggestionPayload {
  const RepRangeSuggestionPayload({
    this.setIndex,
    required this.newLow,
    required this.newHigh,
  });

  /// Which set this applies to, or null for the whole exercise
  /// ([SuggestionKind.changeRepRangeOverall]).
  final int? setIndex;
  final int newLow;
  final int newHigh;
}

/// Used by [SuggestionKind.changeWeightForSet], [SuggestionKind
/// .changeTotalWeight], and [SuggestionKind.deload].
class WeightSuggestionPayload extends SuggestionPayload {
  const WeightSuggestionPayload({this.setIndex, required this.newWeight});

  /// Which set this applies to, or null for the whole exercise/every set.
  final int? setIndex;
  final double newWeight;
}

/// Used by [SuggestionKind.changeExercise] — always a concrete replacement
/// exercise, never just a name, so "specifically pick an exercise" is
/// literal.
class ExerciseSwapPayload extends SuggestionPayload {
  const ExerciseSwapPayload({required this.replacement});
  final Exercise replacement;
}

/// Used by [SuggestionKind.changeWorkoutDay].
class WorkoutDaySuggestionPayload extends SuggestionPayload {
  const WorkoutDaySuggestionPayload({required this.dayId});
  final String dayId;
}

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
    this.kind = SuggestionKind.none,
    this.payload,
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

  /// What kind of actionable change [suggestion] describes, if any — see
  /// [SuggestionPayload] for the structured data an "accept" action needs.
  /// [SuggestionKind.none] for a plain informational finding.
  final SuggestionKind kind;

  /// Structured data matching [kind]'s expected payload subtype. Null when
  /// [kind] is [SuggestionKind.none].
  final SuggestionPayload? payload;
}
