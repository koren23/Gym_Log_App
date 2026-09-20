import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/sheet_layout.dart';
import '../../models/analysis_result.dart';
import '../../models/app_colors.dart';
import '../../models/pending_suggestion.dart';
import '../../models/recent_suggestion_record.dart';
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
  static const _kWebRefreshToken = 'web_refresh_token';
  static const _kWebPendingPkceVerifier = 'web_pending_pkce_verifier';
  static const _kWebPendingPkceState = 'web_pending_pkce_state';
  static const _kDismissedSuggestionSignatures =
      'dismissed_suggestion_signatures_v1';
  static const _kRecentSuggestions = 'recent_suggestions_v1';
  static const _kPendingSuggestions = 'pending_suggestions_v1';

  /// How long a shown suggestion stays "recent" for cooldown/variety
  /// purposes — see [recordSuggestionShown].
  static const int recentSuggestionCooldownDays = 10;

  /// Oldest records are pruned past this so the pref doesn't grow forever.
  static const int recentSuggestionsCap = 200;
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

  /// Web only: the OAuth refresh token from the hand-rolled PKCE flow (see
  /// `GoogleWebOAuthClient`), persisted in the PWA's own local storage so a
  /// fresh access token can be silently minted on every launch without
  /// depending on Safari's (often-blocked) cross-site cookie check.
  String? get webRefreshToken => _prefs.getString(_kWebRefreshToken);

  Future<void> setWebRefreshToken(String? token) async {
    if (token == null) {
      await _prefs.remove(_kWebRefreshToken);
    } else {
      await _prefs.setString(_kWebRefreshToken, token);
    }
  }

  /// Web only: the PKCE code verifier and CSRF state stashed just before
  /// navigating away to Google's consent screen, so they survive the
  /// full-page round trip and can be checked/consumed on return.
  String? get webPendingPkceVerifier =>
      _prefs.getString(_kWebPendingPkceVerifier);
  String? get webPendingPkceState => _prefs.getString(_kWebPendingPkceState);

  Future<void> setWebPendingPkce({
    required String verifier,
    required String state,
  }) async {
    await _prefs.setString(_kWebPendingPkceVerifier, verifier);
    await _prefs.setString(_kWebPendingPkceState, state);
  }

  Future<void> clearWebPendingPkce() async {
    await _prefs.remove(_kWebPendingPkceVerifier);
    await _prefs.remove(_kWebPendingPkceState);
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

  /// Signatures of the form `'${kind.name}::$subjectName'` — a "Not now" on
  /// one suggestion kind for an exercise no longer suppresses unrelated
  /// kinds for that same exercise (unlike the old, coarser
  /// `name::isPlateaued` scheme this replaces).
  Set<String> get dismissedSuggestionSignatures =>
      (_prefs.getStringList(_kDismissedSuggestionSignatures) ?? const [])
          .toSet();

  Future<void> dismissSuggestion(SuggestionKind kind, String subjectName) async {
    final current = dismissedSuggestionSignatures;
    current.add('${kind.name}::$subjectName');
    await _prefs.setStringList(
      _kDismissedSuggestionSignatures,
      current.toList(),
    );
  }

  /// Suggestions actually shown to the user recently — drives per-kind
  /// cooldown/variety in [AnalysisEngine.analyze] (`recentlySuggestedKinds`)
  /// so the same nudge doesn't repeat every session. Recorded once, at
  /// display time (see `SuggestionCard`), not whenever the engine merely
  /// computes a candidate.
  List<RecentSuggestionRecord> get recentSuggestions {
    final raw = _prefs.getString(_kRecentSuggestions);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          RecentSuggestionRecord.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordSuggestionShown(
    SuggestionKind kind,
    String subjectName, {
    String? detail,
  }) async {
    final updated = [
      ...recentSuggestions,
      RecentSuggestionRecord(
        kind: kind,
        subjectName: subjectName,
        detail: detail,
        shownAt: DateTime.now(),
      ),
    ];
    final trimmed = updated.length > recentSuggestionsCap
        ? updated.sublist(updated.length - recentSuggestionsCap)
        : updated;
    await _prefs.setString(
      _kRecentSuggestions,
      jsonEncode([for (final r in trimmed) r.toJson()]),
    );
  }

  /// Suggestions the user has accepted but not yet consumed — one per
  /// exercise name (accepting a new one for the same exercise overwrites
  /// the old one). Consulted by `log_workout_screen.dart` when starting a
  /// new entry for that exercise, or (for [SuggestionKind.changeExercise])
  /// when building a day's exercise list. See `PendingSuggestionsNotifier`.
  Map<String, PendingSuggestion> get pendingSuggestions {
    final raw = _prefs.getString(_kPendingSuggestions);
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in map.entries)
          entry.key: PendingSuggestion.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> setPendingSuggestions(
    Map<String, PendingSuggestion> suggestions,
  ) => _prefs.setString(
    _kPendingSuggestions,
    jsonEncode({
      for (final e in suggestions.entries) e.key: e.value.toJson(),
    }),
  );

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
