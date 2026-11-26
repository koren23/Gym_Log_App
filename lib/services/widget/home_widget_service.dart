import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../core/color_utils.dart';
import '../../models/app_colors.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/local_history_providers.dart';
import '../../providers/settings_providers.dart';
import '../analysis/stats_engine.dart';

/// What the Android home-screen widget shows. Pure and unit-testable:
/// [HomeWidgetService] is the only part that touches a platform channel.
class WidgetStatsSnapshot {
  const WidgetStatsSnapshot({
    required this.streakWeeks,
    required this.bestStreakWeeks,
    required this.bestStreakEnded,
  });

  final int streakWeeks;
  final int bestStreakWeeks;

  /// When the best streak broke — the Sunday closing the first missed
  /// week, e.g. "Mar 16, 2025". Empty while the best streak is still alive.
  final String bestStreakEnded;
}

WidgetStatsSnapshot computeWidgetStats(
  List<DateTime> visitDates, {
  DateTime? now,
}) {
  final current = currentStreakWeeks(visitDates);
  final run = longestStreakRun(visitDates);
  if (run == null) {
    return const WidgetStatsSnapshot(
      streakWeeks: 0,
      bestStreakWeeks: 0,
      bestStreakEnded: '',
    );
  }
  final thisMonday = mondayOf(now ?? DateTime.now());
  final lastMonday = DateTime(
    thisMonday.year,
    thisMonday.month,
    thisMonday.day - 7,
  );
  // Same grace rule as currentStreakWeeks: a run that reached last week
  // isn't broken until this week ends empty.
  final ongoing =
      !run.lastMonday.isBefore(lastMonday) || run.weeks <= current;
  final brokeOn = DateTime(
    run.lastMonday.year,
    run.lastMonday.month,
    run.lastMonday.day + 13,
  );
  return WidgetStatsSnapshot(
    streakWeeks: current,
    bestStreakWeeks: math.max(run.weeks, current),
    bestStreakEnded: ongoing ? '' : DateFormat('MMM d, y').format(brokeOn),
  );
}

/// The in-app theme's colors, translated for the widget's surfaces.
class WidgetPalette {
  const WidgetPalette({
    required this.background,
    required this.surface,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.button,
    required this.button2,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color button;
  final Color button2;
}

WidgetPalette widgetPaletteFor(AppColors c) {
  final isDark =
      ThemeData.estimateBrightnessForColor(c.background) == Brightness.dark;
  return WidgetPalette(
    background: c.background,
    surface: isDark
        ? lightenColor(c.background, 0.08)
        : Color.lerp(c.background, Colors.white, 0.45)!,
    text: isDark ? const Color(0xFFF1F1F1) : const Color(0xFF2E2E2E),
    textMuted: isDark ? const Color(0xFFB4B4B4) : const Color(0xFF6B6B6B),
    accent: c.logWorkoutHero,
    button: c.logWorkoutHero,
    button2: c.dashboardButtons,
  );
}

/// Pushes data to the native `GymWidgetProvider` via the `home_widget`
/// plugin. Keys must match the ones GymWidgetProvider.kt reads.
class HomeWidgetService {
  const HomeWidgetService();

  static const _androidName = 'GymWidgetProvider';

  Future<void> pushStats(WidgetStatsSnapshot snap) async {
    await HomeWidget.saveWidgetData<int>('streak_weeks', snap.streakWeeks);
    await HomeWidget.saveWidgetData<int>(
      'best_streak_weeks',
      snap.bestStreakWeeks,
    );
    await HomeWidget.saveWidgetData<String>(
      'best_streak_ended',
      snap.bestStreakEnded,
    );
    await HomeWidget.updateWidget(androidName: _androidName);
  }

  Future<void> pushTheme(WidgetPalette p) async {
    // Signed 32-bit so the native side receives (and reads back) an Int.
    int argb(Color c) => c.toARGB32().toSigned(32);
    await HomeWidget.saveWidgetData<int>('w_bg', argb(p.background));
    await HomeWidget.saveWidgetData<int>('w_surface', argb(p.surface));
    await HomeWidget.saveWidgetData<int>('w_text', argb(p.text));
    await HomeWidget.saveWidgetData<int>('w_text_muted', argb(p.textMuted));
    await HomeWidget.saveWidgetData<int>('w_accent', argb(p.accent));
    await HomeWidget.saveWidgetData<int>('w_button', argb(p.button));
    await HomeWidget.saveWidgetData<int>('w_button2', argb(p.button2));
    await HomeWidget.updateWidget(androidName: _androidName);
  }
}

final homeWidgetServiceProvider = Provider<HomeWidgetService>(
  (ref) => const HomeWidgetService(),
);

/// Keeps the home-screen widget in sync with every visit mutation and
/// theme change, for the app's entire lifetime — watched once in
/// `GymTrackerApp.build`.
final homeWidgetSyncProvider = Provider<void>((ref) {
  ref.listen(localVisitsProvider, (previous, next) {
    final visits = next.value;
    if (visits == null) return;
    final visitDates = buildHistoryEntries(visits).map((e) => e.date).toList();
    ref
        .read(homeWidgetServiceProvider)
        .pushStats(computeWidgetStats(visitDates));
  }, fireImmediately: true);
  ref.listen(appColorsProvider, (previous, next) {
    ref.read(homeWidgetServiceProvider).pushTheme(widgetPaletteFor(next));
  }, fireImmediately: true);
});
