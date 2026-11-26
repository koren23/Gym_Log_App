import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../providers/analysis_providers.dart';
import '../../providers/local_history_providers.dart';
import '../analysis/stats_engine.dart';

/// The two numbers the Android home-screen widget shows — current streak
/// (every tier) and best-ever streak (large tier only). Pure and
/// unit-testable: [HomeWidgetService.push] is the only part that touches a
/// platform channel.
class WidgetStatsSnapshot {
  const WidgetStatsSnapshot({
    required this.streakWeeks,
    required this.bestStreakWeeks,
  });

  final int streakWeeks;
  final int bestStreakWeeks;
}

/// Same [currentStreakWeeks]/[longestStreakWeeks] data the in-app
/// `StreakBanner`/Stats screen show, just packaged for the widget.
WidgetStatsSnapshot computeWidgetStats(List<DateTime> visitDates) =>
    WidgetStatsSnapshot(
      streakWeeks: currentStreakWeeks(visitDates),
      bestStreakWeeks: longestStreakWeeks(visitDates),
    );

/// Pushes [WidgetStatsSnapshot]s to the native `GymWidgetProvider` via the
/// `home_widget` plugin.
class HomeWidgetService {
  const HomeWidgetService();

  static const _streakKey = 'streak_weeks';
  static const _bestStreakKey = 'best_streak_weeks';

  Future<void> push(WidgetStatsSnapshot snap) async {
    await HomeWidget.saveWidgetData<int>(_streakKey, snap.streakWeeks);
    await HomeWidget.saveWidgetData<int>(_bestStreakKey, snap.bestStreakWeeks);
    await HomeWidget.updateWidget(androidName: 'GymWidgetProvider');
  }
}

final homeWidgetServiceProvider = Provider<HomeWidgetService>(
  (ref) => const HomeWidgetService(),
);

/// Keeps the home-screen widget in sync with every visit mutation, for the
/// app's entire lifetime — watch this once (in `GymTrackerApp.build`) and
/// every log/edit/delete/import that touches [localVisitsProvider] pushes a
/// fresh snapshot with no changes needed at any of those call sites.
final homeWidgetSyncProvider = Provider<void>((ref) {
  ref.listen(localVisitsProvider, (previous, next) {
    final visits = next.value;
    if (visits == null) return;
    final visitDates = buildHistoryEntries(visits).map((e) => e.date).toList();
    ref.read(homeWidgetServiceProvider).push(computeWidgetStats(visitDates));
  }, fireImmediately: true);
});
