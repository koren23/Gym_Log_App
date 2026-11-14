import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'models/workout_day_def.dart';
import 'providers/db_providers.dart';
import 'providers/settings_providers.dart';
import 'services/db/app_database.dart';
import 'services/db/body_weight_dao.dart';
import 'services/db/exercise_dao.dart';
import 'services/db/exercise_note_dao.dart';
import 'services/db/workout_dao.dart';
import 'services/db/workout_day_dao.dart';
import 'services/settings/app_settings_service.dart';
import 'services/sync/pending_sync_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final appDatabase = await AppDatabase.open();
  final settings = AppSettingsService(prefs);
  final workoutDayDao = WorkoutDayDao(appDatabase);

  // Resolved once, synchronously, here — so `workoutDayDefsProvider` can
  // stay a plain synchronous `Notifier<List<WorkoutDayDef>>` with no
  // `AsyncValue` ripple into its many synchronous consumers.
  var workoutDays = await workoutDayDao.getAll();
  if (workoutDays.isEmpty && !settings.hasSeededWorkoutDays) {
    await settings.setHasSeededWorkoutDays(true);
    await workoutDayDao.upsertAll(kWorkoutDaySeed);
    workoutDays = kWorkoutDaySeed;
  }

  runApp(
    ProviderScope(
      overrides: [
        appSettingsServiceProvider.overrideWithValue(settings),
        pendingSyncQueueProvider.overrideWithValue(PendingSyncQueue(prefs)),
        appDatabaseProvider.overrideWithValue(appDatabase),
        exerciseDaoProvider.overrideWithValue(ExerciseDao(appDatabase)),
        workoutDayDaoProvider.overrideWithValue(workoutDayDao),
        bodyWeightDaoProvider.overrideWithValue(BodyWeightDao(appDatabase)),
        exerciseNoteDaoProvider.overrideWithValue(ExerciseNoteDao(appDatabase)),
        workoutDaoProvider.overrideWithValue(WorkoutDao(appDatabase)),
        workoutDayDefsProvider.overrideWith(
          () => WorkoutDayDefsNotifier(workoutDays),
        ),
      ],
      child: const GymTrackerApp(),
    ),
  );
}
