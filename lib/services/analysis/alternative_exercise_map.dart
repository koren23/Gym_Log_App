import '../../core/constants/muscle_groups.dart';
import '../../models/exercise.dart';

/// Suggests alternative exercises for the same muscle group, derived
/// entirely from the user's own exercise list — no external exercise
/// database.
class AlternativeExerciseMap {
  const AlternativeExerciseMap(this._exercisesByGroup);

  final Map<MuscleGroup, List<Exercise>> _exercisesByGroup;

  /// Returns other exercises in [exercise]'s muscle group, ordered to
  /// prefer ones not logged recently (least-recently-used first).
  List<Exercise> alternativesFor(
    Exercise exercise, {
    Map<String, DateTime>? lastLoggedDate,
  }) {
    final group = exercise.muscleGroup;
    final siblings = (_exercisesByGroup[group] ?? const [])
        .where((e) => e.name.toLowerCase() != exercise.name.toLowerCase())
        .toList();

    if (lastLoggedDate == null) return siblings;

    siblings.sort((a, b) {
      final da = lastLoggedDate[a.name];
      final db = lastLoggedDate[b.name];
      if (da == null && db == null) return 0;
      if (da == null) return -1;
      if (db == null) return 1;
      return da.compareTo(db);
    });
    return siblings;
  }
}
