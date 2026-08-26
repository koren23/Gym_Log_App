import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/history_entry.dart';
import '../models/workout_day_def.dart';
import '../models/year_sheet_data.dart';
import '../providers/analysis_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/sheet_data_providers.dart';
import 'simple_line_chart.dart' show approximateWeekLabel;

/// A lightweight "at a glance" card for the home screen: the most recent
/// session per user-defined workout day, each with its exercises and a
/// trend arrow vs. that exercise's previous session. Deliberately not the
/// full analysis-engine plateau logic (that needs >=3 points and lives in
/// the proactive insight banner) — just a quick last-vs-previous glance.
///
/// [expandedDayId]/[onDayToggled] make this a controlled accordion (only
/// one day open at a time, single-select) so the parent Home screen can
/// shrink the insight box above when a day opens up, keeping the page from
/// needing much scrolling.
class ThisWeekSummary extends ConsumerWidget {
  const ThisWeekSummary({
    super.key,
    required this.expandedDayId,
    required this.onDayToggled,
  });

  final String? expandedDayId;
  final ValueChanged<String?> onDayToggled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotState = ref.watch(snapshotProvider).value;
    final theme = Theme.of(context);
    final dayDefs = ref.watch(workoutDayDefsProvider);

    if (snapshotState == null) {
      return const SizedBox.shrink();
    }

    final yearsAscending = snapshotState.snapshot.yearData.values.toList()
      ..sort((a, b) => a.year.compareTo(b.year));

    final allEntries = buildHistoryEntries(
      yearsAscending,
      workoutDays: dayDefs,
    );

    if (allEntries.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No workouts logged yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final day in dayDefs) ...[
          expandedDayId == day.id
              ? Expanded(
                  child: _DaySection(
                    day: day,
                    entry: _latestEntryForDay(allEntries, day),
                    yearsAscending: yearsAscending,
                    expanded: true,
                    onToggle: () => onDayToggled(null),
                  ),
                )
              : _DaySection(
                  day: day,
                  entry: _latestEntryForDay(allEntries, day),
                  yearsAscending: yearsAscending,
                  expanded: false,
                  onToggle: () => onDayToggled(day.id),
                ),
          if (day != dayDefs.last) const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// The most recent entry belonging to [day] — see
  /// [historyEntryBelongsToDay] for the matching rule.
  HistoryEntry? _latestEntryForDay(List<HistoryEntry> entries, WorkoutDayDef day) {
    for (final entry in entries) {
      if (historyEntryBelongsToDay(entry, day)) return entry;
    }
    return null;
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.entry,
    required this.yearsAscending,
    required this.expanded,
    required this.onToggle,
  });

  final WorkoutDayDef day;
  final HistoryEntry? entry;
  final List<YearSheetData> yearsAscending;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = this.entry;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  Text(
                    day.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (entry != null)
                    Text(
                      entry.exactDateKnown
                          ? DateFormat('MMM d').format(entry.date)
                          : approximateWeekLabel(entry.isoWeek, entry.isoYear),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Expanded(
              child: entry == null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'No ${day.label} workouts logged yet.',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 4),
                      children: [
                        for (final name in entry.exerciseNames)
                          _ExerciseRow(
                            name: name,
                            yearsAscending: yearsAscending,
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.name, required this.yearsAscending});

  final String name;
  final List<YearSheetData> yearsAscending;

  @override
  Widget build(BuildContext context) {
    final history = buildExerciseHistory(
      yearsAscending: yearsAscending,
      exerciseName: name,
    );

    var trendIcon = Icons.remove;
    var trendColor = Colors.grey;
    if (history.length >= 2) {
      final last = history.last.avgWeight;
      final prev = history[history.length - 2].avgWeight;
      if (last > prev) {
        trendIcon = Icons.arrow_upward;
        trendColor = Colors.green;
      } else if (last < prev) {
        trendIcon = Icons.arrow_downward;
        trendColor = Colors.red;
      }
    }

    final latestWeight = history.isEmpty ? null : history.last.avgWeight;

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(name, style: const TextStyle(fontSize: 13)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (latestWeight != null) Text(latestWeight.toStringAsFixed(1)),
          const SizedBox(width: 6),
          Icon(trendIcon, size: 16, color: trendColor),
        ],
      ),
    );
  }
}
