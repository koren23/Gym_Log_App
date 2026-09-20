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

/// All workout days are sheet-backed (`WorkoutDays` tab) and fully
/// user-editable — no more "built-in, protected" days. [build] combines
/// whatever the sheet already confirms with any locally-pending day not
/// yet confirmed synced (deduped by id), and seeds Push/Pull/Legs/Full Body
/// exactly once if the sheet has no workout days at all yet.
class WorkoutDayDefsNotifier extends Notifier<List<WorkoutDayDef>> {
  @override
  List<WorkoutDayDef> build() {
    final sheetDays = ref.watch(sheetWorkoutDayDefsProvider);
    final localPending = ref
        .watch(appSettingsServiceProvider)
        .customWorkoutDayDefs
        .where((d) => sheetDays.every((s) => s.id != d.id));

    if (sheetDays.isEmpty && localPending.isEmpty) {
      // Nothing on the sheet yet and nothing pending locally either — seed
      // the classic 3 days + Full Body once. Fire-and-forget: if this
      // fails (offline/first load), it'll simply try again next time
      // build() re-runs with still-empty state.
      Future.microtask(() => _seedIfStillEmpty());
      return kWorkoutDaySeed;
    }
    return [...sheetDays, ...localPending];
  }

  Future<void> _seedIfStillEmpty() async {
    if (state.isNotEmpty && state != kWorkoutDaySeed) return;
    final notifier = ref.read(snapshotProvider.notifier);
    for (final def in kWorkoutDaySeed) {
      await notifier.addWorkoutDayToSheet(def);
    }
  }

  Future<void> addCustomDay(String label, List<MuscleGroup> groups) async {
    final def = WorkoutDayDef(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      muscleGroups: groups,
    );
    // Instant local UI update; the sheet write happens alongside it.
    final localCustoms = ref.read(appSettingsServiceProvider).customWorkoutDayDefs;
    await ref
        .read(appSettingsServiceProvider)
        .setCustomWorkoutDayDefs([...localCustoms, def]);
    state = [...state, def];
    await ref.read(snapshotProvider.notifier).addWorkoutDayToSheet(def);
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
    state = [for (final d in state) d.id == id ? updated : d];

    final localCustoms = ref.read(appSettingsServiceProvider).customWorkoutDayDefs;
    if (localCustoms.any((d) => d.id == id)) {
      await ref.read(appSettingsServiceProvider).setCustomWorkoutDayDefs([
        for (final d in localCustoms) d.id == id ? updated : d,
      ]);
    }
    await ref.read(snapshotProvider.notifier).updateWorkoutDayOnSheet(updated);
  }

  Future<void> removeCustomDay(String id) async {
    WorkoutDayDef? def;
    for (final d in state) {
      if (d.id == id) {
        def = d;
        break;
      }
    }
    state = state.where((d) => d.id != id).toList();
    final localCustoms = ref
        .read(appSettingsServiceProvider)
        .customWorkoutDayDefs
        .where((d) => d.id != id)
        .toList();
    await ref.read(appSettingsServiceProvider).setCustomWorkoutDayDefs(localCustoms);
    if (def != null) {
      await ref.read(snapshotProvider.notifier).removeWorkoutDayFromSheet(def);
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
