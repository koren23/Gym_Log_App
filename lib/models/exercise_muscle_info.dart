import '../core/constants/muscle_groups.dart';

/// One (exercise -> muscle) row reconstructed from the user's hand-maintained
/// "Exercises" reference tab (2026-onward layout: one column per current
/// [MuscleGroup]).
class ExerciseMuscleInfo {
  const ExerciseMuscleInfo({
    required this.exerciseName,
    required this.muscleGroup,
    required this.columnIndex,
  });

  final String exerciseName;
  final MuscleGroup muscleGroup;

  /// 0-based column index of this muscle's column in the "Exercises" tab —
  /// needed to append a newly-added exercise to the right column.
  final int columnIndex;
}
