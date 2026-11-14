import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/muscle_groups.dart';
import '../models/app_colors.dart';
import '../models/pending_suggestion.dart';
import '../models/workout_day_def.dart';
import '../models/workout_defaults.dart';
import '../services/settings/app_settings_service.dart';
import '../services/sync/pending_sync_queue.dart';
import 'db_providers.dart';
import 'sheet_data_providers.dart';

/// Overridden in `main.dart` after `AppSettingsService.create()` resolves,
/// so the rest of the app can read it synchronously.
final appSettingsServiceProvider = Provider<AppSettingsService>((ref) {
  throw UnimplementedError('appSettingsServiceProvider must be overridden');
});

/// Overridden in `main.dart` alongside [appSettingsServiceProvider] (both
/// need the same [SharedPreferences] instance).
final pendingSyncQueueProvider = Provider<PendingSyncQueue>((ref) {
  throw UnimplementedError('pendingSyncQueueProvider must be overridden');
});

class SpreadsheetIdNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(appSettingsServiceProvider).spreadsheetId;

  Future<void> setSpreadsheet({required String id, required String url}) async {
    await ref.read(appSettingsServiceProvider).setSpreadsheet(id: id, url: url);
    state = id;
  }

  Future<void> clear() async {
    await ref.read(appSettingsServiceProvider).clearSpreadsheet();
    state = null;
  }
}

final spreadsheetIdProvider = NotifierProvider<SpreadsheetIdNotifier, String?>(
  SpreadsheetIdNotifier.new,
);

class AppDisplayNameNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(appSettingsServiceProvider).appDisplayName;

  Future<void> setName(String name) async {
    await ref.read(appSettingsServiceProvider).setAppDisplayName(name);
    state = ref.read(appSettingsServiceProvider).appDisplayName;
  }
}

final appDisplayNameProvider = NotifierProvider<AppDisplayNameNotifier, String>(
  AppDisplayNameNotifier.new,
);

class AppColorsNotifier extends Notifier<AppColors> {
  @override
  AppColors build() => ref.watch(appSettingsServiceProvider).appColors;

  Future<void> setAppBarColor(Color color) async {
    await ref.read(appSettingsServiceProvider).setAppBarColor(color);
    state = state.copyWith(appBar: color);
  }

  Future<void> setBackgroundColor(Color color) async {
    await ref.read(appSettingsServiceProvider).setBackgroundColor(color);
    state = state.copyWith(background: color);
  }

  Future<void> setDashboardButtonsColor(Color color) async {
    await ref.read(appSettingsServiceProvider).setDashboardButtonsColor(color);
    state = state.copyWith(dashboardButtons: color);
  }

  Future<void> setLogWorkoutHeroColor(Color color) async {
    await ref.read(appSettingsServiceProvider).setLogWorkoutHeroColor(color);
    state = state.copyWith(logWorkoutHero: color);
  }

  Future<void> resetToDefaults() async {
    await ref.read(appSettingsServiceProvider).resetColors();
    state = AppColors.defaults;
  }

  /// Applies one of [kAppThemePresets] — sets all 4 colors together.
  Future<void> applyPreset(AppColors preset) async {
    final service = ref.read(appSettingsServiceProvider);
    await service.setAppBarColor(preset.appBar);
    await service.setBackgroundColor(preset.background);
    await service.setDashboardButtonsColor(preset.dashboardButtons);
    await service.setLogWorkoutHeroColor(preset.logWorkoutHero);
    state = preset;
  }
}

final appColorsProvider = NotifierProvider<AppColorsNotifier, AppColors>(
  AppColorsNotifier.new,
);

class WorkoutDefaultsNotifier extends Notifier<WorkoutDefaults> {
  @override
  WorkoutDefaults build() {
    final service = ref.watch(appSettingsServiceProvider);
    return WorkoutDefaults(
      repRangeLow: service.defaultRepRangeLow,
      repRangeHigh: service.defaultRepRangeHigh,
    );
  }

  /// Set together so low/high never pass through a transiently-invalid
  /// (low > high) state.
  Future<void> setRepRange(int low, int high) async {
    final clampedLow = low.clamp(1, 50);
    final clampedHigh = high.clamp(clampedLow, 50);
    final service = ref.read(appSettingsServiceProvider);
    await service.setDefaultRepRangeLow(clampedLow);
    await service.setDefaultRepRangeHigh(clampedHigh);
    state = state.copyWith(repRangeLow: clampedLow, repRangeHigh: clampedHigh);
  }
}

final workoutDefaultsProvider =
    NotifierProvider<WorkoutDefaultsNotifier, WorkoutDefaults>(
      WorkoutDefaultsNotifier.new,
    );

/// Local-DB-backed (`workout_day_defs` table) as of v3.0.0 — a sheet, if
/// connected, is a best-effort mirror, not where this reads from. Stays a
/// plain synchronous `Notifier<List<WorkoutDayDef>>` (not `AsyncNotifier`)
/// because its initial state is resolved once, synchronously, in `main()`
/// before `runApp` and handed in via `overrideWith` — see the
/// `appDatabaseProvider`/DAO-provider pattern in `db_providers.dart` for why.
class WorkoutDayDefsNotifier extends Notifier<List<WorkoutDayDef>> {
  WorkoutDayDefsNotifier([this._initial]);

  final List<WorkoutDayDef>? _initial;

  @override
  List<WorkoutDayDef> build() => _initial ?? kWorkoutDaySeed;

  Future<void> addCustomDay(String label, List<MuscleGroup> groups) async {
    final def = WorkoutDayDef(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      muscleGroups: groups,
    );
    await ref.read(workoutDayDaoProvider).upsert(def);
    state = [...state, def];
    try {
      await ref.read(snapshotProvider.notifier).addWorkoutDayToSheet(def);
    } catch (_) {
      // Best-effort sheet mirror — the local save above already succeeded.
    }
  }

  /// Genuinely edits an existing day's label/muscle set in place (as
  /// opposed to delete + recreate) — this preserves [WorkoutDayDef
  /// .legacyDay] and [WorkoutDayDef.sheetRowIndex], so a seeded day (e.g.
  /// Push) keeps matching its pre-2026 history after being edited, and the
  /// same sheet row is updated rather than a new one created.
  Future<void> updateCustomDay(
    String id,
    String label,
    List<MuscleGroup> groups,
  ) async {
    WorkoutDayDef? existing;
    for (final d in state) {
      if (d.id == id) {
        existing = d;
        break;
      }
    }
    if (existing == null) return;
    final updated = WorkoutDayDef(
      id: existing.id,
      label: label,
      muscleGroups: groups,
      legacyDay: existing.legacyDay,
      sheetRowIndex: existing.sheetRowIndex,
    );
    await ref.read(workoutDayDaoProvider).upsert(updated);
    state = [for (final d in state) d.id == id ? updated : d];
    try {
      await ref.read(snapshotProvider.notifier).updateWorkoutDayOnSheet(updated);
    } catch (_) {
      // Best-effort sheet mirror — the local save above already succeeded.
    }
  }

  /// Replaces the in-memory list from the DB directly — called once, right
  /// after [SheetImportService.importAndReconcile] writes fresh rows into
  /// `workout_day_defs` by a path other than this notifier's own mutators.
  Future<void> reloadFromDb() async {
    state = await ref.read(workoutDayDaoProvider).getAll();
  }

  Future<void> removeCustomDay(String id) async {
    WorkoutDayDef? def;
    for (final d in state) {
      if (d.id == id) {
        def = d;
        break;
      }
    }
    if (def == null) return;
    await ref.read(workoutDayDaoProvider).softDelete(id);
    state = state.where((d) => d.id != id).toList();
    try {
      await ref.read(snapshotProvider.notifier).removeWorkoutDayFromSheet(def);
    } catch (_) {
      // Best-effort sheet mirror — the local delete above already succeeded.
    }
  }
}

final workoutDayDefsProvider =
    NotifierProvider<WorkoutDayDefsNotifier, List<WorkoutDayDef>>(
      WorkoutDayDefsNotifier.new,
    );


/// Suggestions the user has accepted from a [SuggestionCard] but not yet
/// consumed — see `AppSettingsService.pendingSuggestions`. Local-only
/// (never synced to the sheet): a suggestion applies once, to whichever
/// device is used to log that exercise next.
class PendingSuggestionsNotifier extends Notifier<Map<String, PendingSuggestion>> {
  @override
  Map<String, PendingSuggestion> build() =>
      ref.watch(appSettingsServiceProvider).pendingSuggestions;

  Future<void> accept(PendingSuggestion suggestion) async {
    final updated = {...state, suggestion.subjectExerciseName: suggestion};
    state = updated;
    await ref.read(appSettingsServiceProvider).setPendingSuggestions(updated);
  }

  /// Removes and returns the pending suggestion for [exerciseName], if any
  /// — call once it's actually been applied to a draft.
  PendingSuggestion? consume(String exerciseName) {
    final existing = state[exerciseName];
    if (existing == null) return null;
    final updated = {...state}..remove(exerciseName);
    state = updated;
    ref.read(appSettingsServiceProvider).setPendingSuggestions(updated);
    return existing;
  }

  Future<void> dismiss(String exerciseName) async {
    if (!state.containsKey(exerciseName)) return;
    final updated = {...state}..remove(exerciseName);
    state = updated;
    await ref.read(appSettingsServiceProvider).setPendingSuggestions(updated);
  }
}

final pendingSuggestionsProvider =
    NotifierProvider<PendingSuggestionsNotifier, Map<String, PendingSuggestion>>(
      PendingSuggestionsNotifier.new,
    );
