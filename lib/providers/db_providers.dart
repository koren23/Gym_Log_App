import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/db/app_database.dart';
import '../services/db/body_weight_dao.dart';
import '../services/db/exercise_dao.dart';
import '../services/db/exercise_note_dao.dart';
import '../services/db/workout_dao.dart';
import '../services/db/workout_day_dao.dart';
import '../services/sync/sheet_import_service.dart';

// Resolved once, synchronously, in main() before runApp — see the
// appSettingsServiceProvider/pendingSyncQueueProvider pattern in
// settings_providers.dart for why: it lets every DB-backed Notifier stay a
// plain synchronous Notifier<T> instead of AsyncNotifier<AsyncValue<T>>.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

final exerciseDaoProvider = Provider<ExerciseDao>(
  (ref) => throw UnimplementedError('exerciseDaoProvider must be overridden'),
);

final workoutDayDaoProvider = Provider<WorkoutDayDao>(
  (ref) =>
      throw UnimplementedError('workoutDayDaoProvider must be overridden'),
);

final bodyWeightDaoProvider = Provider<BodyWeightDao>(
  (ref) =>
      throw UnimplementedError('bodyWeightDaoProvider must be overridden'),
);

final exerciseNoteDaoProvider = Provider<ExerciseNoteDao>(
  (ref) =>
      throw UnimplementedError('exerciseNoteDaoProvider must be overridden'),
);

final workoutDaoProvider = Provider<WorkoutDao>(
  (ref) => throw UnimplementedError('workoutDaoProvider must be overridden'),
);

/// Pure composition of the DAO providers above — never overridden itself.
final sheetImportServiceProvider = Provider<SheetImportService>(
  (ref) => SheetImportService(
    exerciseDao: ref.watch(exerciseDaoProvider),
    workoutDayDao: ref.watch(workoutDayDaoProvider),
    workoutDao: ref.watch(workoutDaoProvider),
    bodyWeightDao: ref.watch(bodyWeightDaoProvider),
    exerciseNoteDao: ref.watch(exerciseNoteDaoProvider),
  ),
);
