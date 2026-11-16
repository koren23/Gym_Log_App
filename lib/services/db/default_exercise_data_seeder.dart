import '../../data/default_exercises_seed.dart';
import '../../models/exercise.dart';
import 'exercise_dao.dart';

/// One-time seed of the curated default package's suggested rep range/set
/// count onto local exercises that don't have their own yet — inserts a
/// curated exercise outright if it doesn't exist locally at all. Only ever
/// fills values that are still unset; never overwrites a user-edited or
/// already-seeded suggestion. Safe to call multiple times; gated to run
/// once via `AppSettingsService.hasSeededDefaultExerciseData`.
Future<void> seedDefaultExerciseData(ExerciseDao dao) async {
  for (final seed in kDefaultExercisesSeed) {
    final existing = await dao.getByName(seed.name);
    if (existing == null) {
      await dao.insert(
        Exercise(
          name: seed.name,
          muscleGroup: seed.muscleGroup,
          unit: seed.unit,
          customUnitLabel: seed.customUnitLabel,
          repRangeLow: seed.repRangeLow,
          repRangeHigh: seed.repRangeHigh,
          setCount: seed.setCount,
        ),
      );
      continue;
    }
    final hasOwnSuggestion =
        existing.repRangeLow != null ||
        existing.repRangeHigh != null ||
        existing.setCount != null;
    if (hasOwnSuggestion) continue;
    await dao.update(
      existing.copyWith(
        repRangeLow: seed.repRangeLow,
        repRangeHigh: seed.repRangeHigh,
        setCount: seed.setCount,
      ),
    );
  }
}

/// One-time fix for the sheet-sync muscle-group corruption bug (see
/// `ExerciseDao.upsert`'s doc comment): overwrites a local exercise's
/// muscle group back to the curated package's value whenever it currently
/// disagrees. This is the one deliberate exception to "never overwrite a
/// known muscle group" — needed because many users' local data is already
/// corrupted by syncs that ran before the bug was fixed. Gated to run once
/// via `AppSettingsService.hasResetCuratedMuscleGroups`.
Future<void> resetCuratedMuscleGroups(ExerciseDao dao) async {
  for (final seed in kDefaultExercisesSeed) {
    final existing = await dao.getByName(seed.name);
    if (existing == null || existing.muscleGroup == seed.muscleGroup) {
      continue;
    }
    await dao.update(
      Exercise(
        name: existing.name,
        muscleGroup: seed.muscleGroup,
        sheetRow: existing.sheetRow,
        muscleGroupKnown: true,
        unit: existing.unit,
        customUnitLabel: existing.customUnitLabel,
        secondaryMuscleGroups: existing.secondaryMuscleGroups,
        repRangeLow: existing.repRangeLow,
        repRangeHigh: existing.repRangeHigh,
        setCount: existing.setCount,
      ),
    );
  }
}

/// Explicit, user-requested reset of every curated exercise's suggested rep
/// range + set count back to the current default package's values —
/// overwrites even a prior value, unlike [seedDefaultExerciseData]'s "only
/// fill if still unset" rule. Only ever called from Settings' "Reset
/// settings to default" action, never automatically on launch.
Future<void> resetCuratedRepRangeAndSetCount(ExerciseDao dao) async {
  for (final seed in kDefaultExercisesSeed) {
    final existing = await dao.getByName(seed.name);
    if (existing == null) continue;
    await dao.update(
      existing.copyWith(
        repRangeLow: seed.repRangeLow,
        clearRepRangeLow: seed.repRangeLow == null,
        repRangeHigh: seed.repRangeHigh,
        clearRepRangeHigh: seed.repRangeHigh == null,
        setCount: seed.setCount,
        clearSetCount: seed.setCount == null,
      ),
    );
  }
}
