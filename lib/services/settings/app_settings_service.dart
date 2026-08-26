import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/sheet_layout.dart';
import '../../models/app_colors.dart';
import '../../models/workout_day_def.dart';

/// The Android launcher icon/label is fixed at "Koren's Gym Log" (baked
/// into the app package) — this is just the in-app display name shown on
/// screen, which the user can personalize via Settings.
const String kDefaultAppDisplayName = "Koren's Gym Log";

/// Thin wrapper around [SharedPreferences] for the app's small set of local
/// scalar settings. Sheets is the database — this is not a general-purpose
/// local store.
class AppSettingsService {
  AppSettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _kSpreadsheetId = 'spreadsheet_id';
  static const _kSpreadsheetUrl = 'spreadsheet_url';
  static const _kLastSignedInEmail = 'last_signed_in_email';
  static const _kDismissedFindingSignatures = 'dismissed_finding_signatures';
  static const _kAppDisplayName = 'app_display_name';
  static const _kAppBarColor = 'color_app_bar';
  static const _kBackgroundColor = 'color_background';
  static const _kDashboardButtonsColor = 'color_dashboard_buttons';
  static const _kLogWorkoutHeroColor = 'color_log_workout_hero';
  static const _kWorkoutDraft = 'workout_draft';
  static const _kDefaultRepRangeLow = 'default_rep_range_low';
  static const _kDefaultRepRangeHigh = 'default_rep_range_high';
  static const _kCustomWorkoutDays = 'custom_workout_days';

  static Future<AppSettingsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettingsService(prefs);
  }

  String? get spreadsheetId => _prefs.getString(_kSpreadsheetId);
  String? get spreadsheetUrl => _prefs.getString(_kSpreadsheetUrl);
  String? get lastSignedInEmail => _prefs.getString(_kLastSignedInEmail);

  Future<void> setSpreadsheet({required String id, required String url}) async {
    await _prefs.setString(_kSpreadsheetId, id);
    await _prefs.setString(_kSpreadsheetUrl, url);
  }

  Future<void> clearSpreadsheet() async {
    await _prefs.remove(_kSpreadsheetId);
    await _prefs.remove(_kSpreadsheetUrl);
  }

  Future<void> setLastSignedInEmail(String? email) async {
    if (email == null) {
      await _prefs.remove(_kLastSignedInEmail);
    } else {
      await _prefs.setString(_kLastSignedInEmail, email);
    }
  }

  String get appDisplayName =>
      _prefs.getString(_kAppDisplayName) ?? kDefaultAppDisplayName;

  Future<void> setAppDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == kDefaultAppDisplayName) {
      await _prefs.remove(_kAppDisplayName);
    } else {
      await _prefs.setString(_kAppDisplayName, trimmed);
    }
  }

  AppColors get appColors => AppColors(
    appBar: Color(
      _prefs.getInt(_kAppBarColor) ?? AppColors.kDefaultAppBar.toARGB32(),
    ),
    background: Color(
      _prefs.getInt(_kBackgroundColor) ??
          AppColors.kDefaultBackground.toARGB32(),
    ),
    dashboardButtons: Color(
      _prefs.getInt(_kDashboardButtonsColor) ??
          AppColors.kDefaultDashboardButtons.toARGB32(),
    ),
    logWorkoutHero: Color(
      _prefs.getInt(_kLogWorkoutHeroColor) ??
          AppColors.kDefaultLogWorkoutHero.toARGB32(),
    ),
  );

  Future<void> setAppBarColor(Color color) =>
      _prefs.setInt(_kAppBarColor, color.toARGB32());
  Future<void> setBackgroundColor(Color color) =>
      _prefs.setInt(_kBackgroundColor, color.toARGB32());
  Future<void> setDashboardButtonsColor(Color color) =>
      _prefs.setInt(_kDashboardButtonsColor, color.toARGB32());
  Future<void> setLogWorkoutHeroColor(Color color) =>
      _prefs.setInt(_kLogWorkoutHeroColor, color.toARGB32());

  Future<void> resetColors() async {
    await _prefs.remove(_kAppBarColor);
    await _prefs.remove(_kBackgroundColor);
    await _prefs.remove(_kDashboardButtonsColor);
    await _prefs.remove(_kLogWorkoutHeroColor);
  }

  Set<String> get dismissedFindingSignatures =>
      (_prefs.getStringList(_kDismissedFindingSignatures) ?? const []).toSet();

  Future<void> dismissFinding(String signature) async {
    final current = dismissedFindingSignatures;
    current.add(signature);
    await _prefs.setStringList(_kDismissedFindingSignatures, current.toList());
  }

  /// The single in-progress "Log workout" draft, as JSON — overwritten on
  /// every change (only one draft exists at a time) so a session survives
  /// leaving the screen before finally publishing it.
  String? get workoutDraftJson => _prefs.getString(_kWorkoutDraft);

  Future<void> setWorkoutDraft(String json) =>
      _prefs.setString(_kWorkoutDraft, json);

  Future<void> clearWorkoutDraft() => _prefs.remove(_kWorkoutDraft);

  int get defaultRepRangeLow =>
      _prefs.getInt(_kDefaultRepRangeLow) ?? kDefaultRepRangeLow;
  int get defaultRepRangeHigh =>
      _prefs.getInt(_kDefaultRepRangeHigh) ?? kDefaultRepRangeHigh;

  Future<void> setDefaultRepRangeLow(int value) =>
      _prefs.setInt(_kDefaultRepRangeLow, value);
  Future<void> setDefaultRepRangeHigh(int value) =>
      _prefs.setInt(_kDefaultRepRangeHigh, value);

  /// Workout days pending local storage until confirmed synced to the
  /// sheet-backed `WorkoutDays` tab (see `WorkoutDayDefsNotifier`) — an
  /// offline staging area, not the source of truth once a day is synced.
  List<WorkoutDayDef> get customWorkoutDayDefs {
    final raw = _prefs.getString(_kCustomWorkoutDays);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          WorkoutDayDef.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> setCustomWorkoutDayDefs(List<WorkoutDayDef> defs) =>
      _prefs.setString(
        _kCustomWorkoutDays,
        jsonEncode([for (final d in defs) d.toJson()]),
      );
}
