import '../../models/exercise.dart';
import '../constants/muscle_groups.dart';

/// The single authoritative [MuscleGroup] for [exercise] — null only if it
/// has no usable tag at all. As of v3.0.0 this is a near-trivial check: the
/// "Exercises" reference-tab fallback that used to run live on every read
/// is now folded into `Exercise.muscleGroup`/`muscleGroupKnown` once, at
/// import time (`SheetImportService._importExercises`), so nothing here
/// needs a second data source to consult.
MuscleGroup? resolveMuscleGroup(Exercise exercise) {
  if (exercise.muscleGroupKnown && !exercise.muscleGroup.legacy) {
    return exercise.muscleGroup;
  }
  return null;
}

/// [exercises] keyed by lowercased name — the shape the Stats tab's
/// `muscle_balance.dart`/`stats_engine.dart` aggregations expect.
Map<String, Exercise> resolvedExercisesByName(List<Exercise> exercises) {
  return {for (final e in exercises) e.name.toLowerCase(): e};
}

/// Every exercise name in [exercises], bucketed by the current-muscle sheet
/// header it resolves to via [resolveMuscleGroup] — the single shared
/// "which exercises belong to muscle X" builder, used by both the Graphs
/// picker and [buildMuscleProgressPoints] in `analysis_providers.dart`.
Map<String, Set<String>> exerciseNamesByMuscleSheetHeader(
  List<Exercise> exercises,
) {
  final result = <String, Set<String>>{};
  for (final exercise in exercises) {
    final group = resolveMuscleGroup(exercise);
    if (group == null || group.legacy) continue;
    result.putIfAbsent(group.sheetHeader, () => {}).add(exercise.name);
  }
  return result;
}
