import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/local_history_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../widgets/streak_banner.dart';
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
    // The local DB is the source of truth (v3.0.0) — every widget below
    // reads it directly (via localVisitsProvider) and handles its own
    // loading/empty state, so this tab's layout never waits on a sheet.
    // snapshotProvider is only consulted here for the optional best-effort
    // sheet mirror: retrying a queued push, and pull-to-refresh.
    final spreadsheetId = ref.watch(spreadsheetIdProvider);
    final snapshotAsync = spreadsheetId != null
        ? ref.watch(snapshotProvider)
        : null;

    final pendingCount = snapshotAsync?.value?.pendingCount ?? 0;
    if (!_autoRetried && pendingCount > 0) {
      _autoRetried = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(snapshotProvider.notifier).retryPendingSyncs();
      });
    }

    final screenHeight = MediaQuery.sizeOf(context).height;

    return RefreshIndicator(
      onRefresh: () async {
        if (spreadsheetId != null) {
          await ref.read(snapshotProvider.notifier).refresh();
        }
        await ref.read(localVisitsProvider.notifier).refresh();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: _expandedDayId != null ? 56 : screenHeight * 0.3,
              child: WeeklyInsightBox(minimized: _expandedDayId != null),
            ),
            SizedBox(height: _expandedDayId != null ? 8 : 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _expandedDayId != null
                  ? const SizedBox.shrink()
                  : const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: StreakBanner(),
                    ),
            ),
            Expanded(
              child: ThisWeekSummary(
                expandedDayId: _expandedDayId,
                onDayToggled: (id) => setState(() => _expandedDayId = id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
