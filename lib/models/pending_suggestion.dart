import '../core/constants/muscle_groups.dart';
import 'analysis_result.dart';
import 'exercise.dart';
import 'exercise_unit.dart';

/// A user-accepted suggestion, staged locally until the next time its
/// exercise (or, for [SuggestionKind.changeExercise], its workout day) is
/// logged — see `PendingSuggestionsNotifier` and `log_workout_screen.dart`'s
/// `_applyPendingSuggestionIfAny`/`_exercisesForDay`.
class PendingSuggestion {
  const PendingSuggestion({
    required this.kind,
    required this.subjectExerciseName,
    this.setIndex,
    this.newRepRangeLow,
    this.newRepRangeHigh,
    this.newWeight,
    this.replacementExercise,
    required this.acceptedAt,
  });

  final SuggestionKind kind;

  /// The exercise this suggestion was about — also the key it's stored
  /// under (one pending suggestion at a time per exercise).
  final String subjectExerciseName;

  /// Which set to apply this to, or null for the whole exercise.
  final int? setIndex;
  final int? newRepRangeLow;
  final int? newRepRangeHigh;
  final double? newWeight;

  /// Set only for [SuggestionKind.changeExercise].
  final Exercise? replacementExercise;

  final DateTime acceptedAt;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'subjectExerciseName': subjectExerciseName,
    'setIndex': setIndex,
    'newRepRangeLow': newRepRangeLow,
    'newRepRangeHigh': newRepRangeHigh,
    'newWeight': newWeight,
    'replacementExerciseName': replacementExercise?.name,
    'replacementExerciseMuscleGroup': replacementExercise?.muscleGroup.name,
    'replacementExerciseUnit': replacementExercise?.unit.name,
    'replacementExerciseCustomUnitLabel': replacementExercise?.customUnitLabel,
    'acceptedAt': acceptedAt.toIso8601String(),
  };

  factory PendingSuggestion.fromJson(Map<String, dynamic> json) {
    final replacementName = json['replacementExerciseName'] as String?;
    return PendingSuggestion(
      kind: SuggestionKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => SuggestionKind.none,
      ),
      subjectExerciseName: json['subjectExerciseName'] as String,
      setIndex: json['setIndex'] as int?,
      newRepRangeLow: json['newRepRangeLow'] as int?,
      newRepRangeHigh: json['newRepRangeHigh'] as int?,
      newWeight: (json['newWeight'] as num?)?.toDouble(),
      replacementExercise: replacementName == null
          ? null
          : Exercise(
              name: replacementName,
              muscleGroup: MuscleGroup.values.firstWhere(
                (g) => g.name == json['replacementExerciseMuscleGroup'],
                orElse: () => MuscleGroup.values.first,
              ),
              unit: ExerciseUnit.values.firstWhere(
                (u) => u.name == json['replacementExerciseUnit'],
                orElse: () => ExerciseUnit.kg,
              ),
              customUnitLabel:
                  json['replacementExerciseCustomUnitLabel'] as String?,
            ),
      acceptedAt: DateTime.parse(json['acceptedAt'] as String),
    );
  }
}
