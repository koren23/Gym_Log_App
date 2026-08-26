import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/analysis_result.dart';
import '../../models/history_entry.dart';
import '../../models/workout_day_def.dart';
import '../../models/year_sheet_data.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/insight_summary.dart';

/// Read-only lookup of the analysis findings from the most recent [day]
/// workout — lets the user check "how did I do last time" before logging
/// today's session, instead of only seeing this after publishing.
class LastWorkoutInsightScreen extends ConsumerWidget {
  const LastWorkoutInsightScreen({super.key, required this.day});

  final WorkoutDayDef day;

  HistoryEntry? _lastEntryFor(
    List<YearSheetData> yearsAscending,
    List<WorkoutDayDef> dayDefs,
  ) {
    for (final entry in buildHistoryEntries(
      yearsAscending,
      workoutDays: dayDefs,
    )) {
      if (historyEntryBelongsToDay(entry, day)) return entry;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final snapshot = ref.watch(snapshotProvider).value?.snapshot;
    final yearsAscending = snapshot?.yearData.values.toList()
      ?..sort((a, b) => a.year.compareTo(b.year));
    final dayDefs = ref.watch(workoutDayDefsProvider);

    final entry = yearsAscending == null
        ? null
        : _lastEntryFor(yearsAscending, dayDefs);
    final findings = (entry == null || yearsAscending == null)
        ? const <AnalysisFinding>[]
        : analyzeExercises(
            yearsAscending: yearsAscending,
            exerciseNames: entry.exerciseNames,
            bodyWeightEntries: ref.watch(bodyWeightEntriesProvider),
          );

    return Scaffold(
      appBar: AppBar(title: Text('Last ${day.label} day')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: entry == null
              ? Text(
                  'No previous ${day.label} workout logged yet.',
                  style: theme.textTheme.bodyMedium,
                )
              : ListView(
                  children: [
                    Text(
                      DateFormat('EEEE, MMM d, yyyy').format(entry.date),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.exerciseNames.join(', '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    InsightSummaryList(findings: findings),
                  ],
                ),
        ),
      ),
    );
  }
}
