import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sheet_data_providers.dart';
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
        loading: () => const Center(child: CircularProgressIndicator()),
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
        data: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: [
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
        ),
      ),
    );
  }
}
