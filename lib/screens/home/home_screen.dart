import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sheet_data_providers.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/this_week_summary.dart';
import '../../widgets/weekly_insight_box.dart';

/// The "Home" tab of [MainShell]: a "last few weeks" progress summary and
/// a lightweight recent-workouts glance. Detailed graphs and full history
/// live in their own bottom-nav tabs; body weight/workout logging are the
/// FABs on the shell.
///
/// Laid out as a fixed Column (not one long ListView) so the page mostly
/// doesn't need to scroll: the insight box shrinks when a Push/Pull/Legs
/// section below is opened, and only the recent-workouts list scrolls
/// internally if its content doesn't fit the remaining space.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  bool _autoRetried = false;
  String? _expandedDayId;

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(snapshotProvider);

    final pendingCount = snapshotAsync.value?.pendingCount ?? 0;
    if (!_autoRetried && pendingCount > 0) {
      _autoRetried = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(snapshotProvider.notifier).retryPendingSyncs();
      });
    }

    final screenHeight = MediaQuery.sizeOf(context).height;

    return RefreshIndicator(
      onRefresh: () => ref.read(snapshotProvider.notifier).refresh(),
      child: snapshotAsync.when(
        loading: () => const HomeSkeleton(),
        error: (e, st) => ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Failed to load spreadsheet:\n$e',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: FilledButton(
                onPressed: () => ref.read(snapshotProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
        data: (snapshotState) {
          final streak = _currentStreak(snapshotState.snapshot);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                if (streak > 0) ...[
                  _StreakBanner(days: streak),
                  const SizedBox(height: 8),
                ],
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: _expandedDayId != null ? 56 : screenHeight * 0.3,
                  child: WeeklyInsightBox(minimized: _expandedDayId != null),
                ),
                SizedBox(height: _expandedDayId != null ? 8 : 16),
                Expanded(
                  child: ThisWeekSummary(
                    expandedDayId: _expandedDayId,
                    onDayToggled: (id) => setState(() => _expandedDayId = id),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Consecutive calendar days (counting backward from today, or from
/// yesterday if nothing's logged yet today so the streak doesn't zero out
/// mid-day) with at least one logged workout.
int _currentStreak(dynamic snapshot) {
  final workoutDates = <DateTime>{};
  for (final year in snapshot.yearData.values) {
    for (final row in year.metaRows) {
      final d = row.date;
      workoutDates.add(DateTime(d.year, d.month, d.day));
    }
  }
  if (workoutDates.isEmpty) return 0;
  final today = DateTime.now();
  var cursor = DateTime(today.year, today.month, today.day);
  if (!workoutDates.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (workoutDates.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

class _StreakBanner extends StatelessWidget {
  const _StreakBanner({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Text(
            days == 1 ? '1 day streak' : '$days day streak',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
