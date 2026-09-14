import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/analysis_result.dart';
import '../../models/workout_day_def.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/insight_summary.dart';
import '../../widgets/read_only_exercise_sets.dart';
import '../../widgets/star_rating_input.dart';

/// Read-only preview of the most recent real [day] workout — exercise
/// order, per-set reps/weights, whole-visit rating, personal notes, and the
/// app's analysis findings — so the user can check "how did I do last time"
/// before logging today's session, instead of only seeing this after
/// publishing.
class LastWorkoutInsightScreen extends ConsumerWidget {
  const LastWorkoutInsightScreen({super.key, required this.day});

  final WorkoutDayDef day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final snapshot = ref.watch(snapshotProvider).value?.snapshot;
    final yearsAscending = snapshot?.yearData.values.toList()
      ?..sort((a, b) => a.year.compareTo(b.year));
    final dayDefs = ref.watch(workoutDayDefsProvider);

    final entry = yearsAscending == null
        ? null
        : mostRecentRealVisitForDay(
            buildHistoryEntries(yearsAscending, workoutDays: dayDefs),
            day,
          );
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
                    const SizedBox(height: 12),
                    for (final ex in entry.metaRow!.exercises)
                      ReadOnlyExerciseSets(exercise: ex),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Rating: ', style: theme.textTheme.bodyMedium),
                        if (entry.metaRow!.rating != null)
                          ReadOnlyStarRating(value: entry.metaRow!.rating!)
                        else
                          Text('Not rated', style: theme.textTheme.bodySmall),
                      ],
                    ),
                    if (entry.metaRow!.note != null &&
                        entry.metaRow!.note!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '📝 ${entry.metaRow!.note}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      "App's take",
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InsightSummaryList(findings: findings),
                  ],
                ),
        ),
      ),
    );
  }
}
