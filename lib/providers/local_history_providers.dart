import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/body_weight_entry.dart';
import '../models/exercise.dart';
import '../models/exercise_note.dart';
import '../models/year_sheet_data.dart';
import 'db_providers.dart';

/// Every logged visit, from the local database — the direct replacement
/// for "every year's sheet-parsed `metaRows` combined." Source of truth as
/// of v3.0.0; a connected sheet is a best-effort mirror, not where this
/// reads from.
class LocalVisitsNotifier extends AsyncNotifier<List<MetaRow>> {
  @override
  Future<List<MetaRow>> build() async {
    final dao = ref.watch(workoutDaoProvider);
    return dao.getAllAsMetaRows();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final localVisitsProvider =
    AsyncNotifierProvider<LocalVisitsNotifier, List<MetaRow>>(
      LocalVisitsNotifier.new,
    );

/// Every known exercise, from the local database — available instantly
/// with zero sheet dependency. Direct replacement for the old sheet-backed
/// `allKnownExercisesProvider`.
class LocalExercisesNotifier extends AsyncNotifier<List<Exercise>> {
  @override
  Future<List<Exercise>> build() async {
    final dao = ref.watch(exerciseDaoProvider);
    return dao.getAll();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final localExercisesProvider =
    AsyncNotifierProvider<LocalExercisesNotifier, List<Exercise>>(
      LocalExercisesNotifier.new,
    );

/// Every logged body-weight entry, from the local database.
class LocalBodyWeightNotifier extends AsyncNotifier<List<BodyWeightEntry>> {
  @override
  Future<List<BodyWeightEntry>> build() async {
    final dao = ref.watch(bodyWeightDaoProvider);
    return dao.getAll();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final localBodyWeightProvider =
    AsyncNotifierProvider<LocalBodyWeightNotifier, List<BodyWeightEntry>>(
      LocalBodyWeightNotifier.new,
    );

/// Every exercise note, from the local database.
class LocalNotesNotifier extends AsyncNotifier<List<ExerciseNote>> {
  @override
  Future<List<ExerciseNote>> build() async {
    final dao = ref.watch(exerciseNoteDaoProvider);
    return dao.getAll();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final localNotesProvider =
    AsyncNotifierProvider<LocalNotesNotifier, List<ExerciseNote>>(
      LocalNotesNotifier.new,
    );
