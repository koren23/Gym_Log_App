import '../../data/default_exercises_seed.dart';
import '../../models/exercise.dart';
import 'exercise_dao.dart';

/// One-time fill-in of notes/photo for the curated starter exercises in
/// [kDefaultExercisesSeed] — see
/// `AppSettingsService.hasSeededDefaultExerciseDetails`. Never overwrites a
/// value the user has already set: an existing exercise only gets the
/// seed's notes/photo when both are still null. A seed exercise the user
/// has never logged is inserted fresh.
Future<void> seedDefaultExerciseDetails(ExerciseDao dao) async {
  for (final seed in kDefaultExercisesSeed) {
    final existing = await dao.getByName(seed.name);
    if (existing == null) {
      await dao.insert(
        Exercise(
          name: seed.name,
          muscleGroup: seed.muscleGroup,
          notes: seed.notes,
          photoAssetKey: seed.photoAssetKey,
        ),
      );
    } else if (existing.notes == null && existing.photoAssetKey == null) {
      await dao.update(
        existing.copyWith(notes: seed.notes, photoAssetKey: seed.photoAssetKey),
      );
    }
  }
}
