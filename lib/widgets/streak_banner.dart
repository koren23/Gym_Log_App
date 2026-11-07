import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/analysis_providers.dart';
import '../providers/sheet_data_providers.dart';
import '../services/analysis/stats_engine.dart';
import 'streak_color.dart';

/// Compact, colored current-streak headline for the Home tab — same
/// [currentStreakWeeks] data as the Stats tab's Consistency card, just a
/// smaller, always-visible presentation sized to fit Home's fixed layout.
class StreakBanner extends ConsumerWidget {
  const StreakBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotState = ref.watch(snapshotProvider).value;
    final yearsAscending = snapshotState?.snapshot.yearData.values.toList()
      ?..sort((a, b) => a.year.compareTo(b.year));
    if (yearsAscending == null || yearsAscending.isEmpty) {
      return const SizedBox.shrink();
    }

    final visitDates = buildHistoryEntries(yearsAscending)
        .map((e) => e.date)
        .toList();
    if (visitDates.isEmpty) return const SizedBox.shrink();

    final streak = currentStreakWeeks(visitDates);
    final color = streakColor(streak);
    final theme = Theme.of(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          streak > 0
              ? ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.red, Colors.deepOrange, Colors.amber],
                  ).createShader(bounds),
                  child: const Icon(Icons.local_fire_department),
                )
              : Icon(Icons.local_fire_department, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              streak > 0
                  ? "$streak-week streak — keep it going!"
                  : 'Log a workout this week to start a streak.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (streak > 0)
            Text(
              '$streak',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}
