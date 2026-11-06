import '../../models/exercise.dart';
import '../../models/exercise_muscle_info.dart';
import '../../models/year_sheet_data.dart';
import '../constants/muscle_groups.dart';

/// Resolves the single authoritative [MuscleGroup] for [exercise]: its own
/// current-era tag wins whenever it's known and non-legacy (the reliable,
/// per-exercise source); only when it has no such usable tag does this fall
/// back to a name-matched entry from the legacy "Exercises" reference tab
/// ([exerciseMuscleInfo]). This precedence replaces every previous call
/// site's *union* of both sources, which could tag one exercise under two
/// different muscles at once.
MuscleGroup? resolveMuscleGroup({
  required Exercise exercise,
  required List<ExerciseMuscleInfo> exerciseMuscleInfo,
}) {
  if (exercise.muscleGroupKnown && !exercise.muscleGroup.legacy) {
    return exercise.muscleGroup;
  }
  for (final info in exerciseMuscleInfo) {
    if (info.exerciseName.toLowerCase() == exercise.name.toLowerCase()) {
      return info.muscleGroup;
    }
  }
  return null;
}

/// [exercises] keyed by lowercased name, with [Exercise.muscleGroup]
/// replaced by its [resolveMuscleGroup] resolution wherever that differs —
/// the shape the Stats tab's `muscle_balance.dart`/`stats_engine.dart`
/// aggregations expect, so a legacy-tagged exercise still counts toward the
/// right muscle instead of being silently dropped.
Map<String, Exercise> resolvedExercisesByName({
  required List<Exercise> exercises,
  required List<ExerciseMuscleInfo> exerciseMuscleInfo,
}) {
  final result = <String, Exercise>{};
  for (final exercise in exercises) {
    final resolved = resolveMuscleGroup(
      exercise: exercise,
      exerciseMuscleInfo: exerciseMuscleInfo,
    );
    result[exercise.name.toLowerCase()] =
        (resolved == null || resolved == exercise.muscleGroup)
        ? exercise
        : Exercise(
            name: exercise.name,
            muscleGroup: resolved,
            sheetRow: exercise.sheetRow,
            muscleGroupKnown: true,
            unit: exercise.unit,
            customUnitLabel: exercise.customUnitLabel,
            secondaryMuscleGroups: exercise.secondaryMuscleGroups,
          );
  }
  return result;
}

/// Every exercise name known across [yearsAscending], bucketed by the
/// current-muscle sheet header it resolves to via [resolveMuscleGroup] — the
/// single shared "which exercises belong to muscle X" builder, used by both
/// the Graphs picker and [buildMuscleProgressPoints] in
/// `analysis_providers.dart`.
Map<String, Set<String>> exerciseNamesByMuscleSheetHeader({
  required List<YearSheetData> yearsAscending,
  required List<ExerciseMuscleInfo> exerciseMuscleInfo,
}) {
  final exercisesByName = <String, Exercise>{
    for (final y in yearsAscending)
      for (final e in y.allExercises) e.name: e,
  };

  final result = <String, Set<String>>{};
  for (final entry in exercisesByName.entries) {
    final group = resolveMuscleGroup(
      exercise: entry.value,
      exerciseMuscleInfo: exerciseMuscleInfo,
    );
    if (group == null || group.legacy) continue;
    result.putIfAbsent(group.sheetHeader, () => {}).add(entry.key);
  }
  return result;
}
