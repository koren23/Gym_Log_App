import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/analysis_result.dart';
import '../../models/history_entry.dart';
import '../../models/workout_day_def.dart';
import '../../models/workout_visit.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../services/analysis/stats_engine.dart';
import '../../services/analysis/xp_engine.dart';
import '../../widgets/insight_summary.dart';
import '../root/main_shell.dart';

/// Shown right after a workout is published: a short, skimmable summary
/// (not full paragraphs) of what's trending up and what's stuck, so it's
/// quick to read standing in the gym.
class PostSaveInsightScreen extends ConsumerWidget {
  const PostSaveInsightScreen({super.key, required this.visit});

  final WorkoutVisit visit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final snapshotState = ref.watch(snapshotProvider).value;
    final yearsAscending = snapshotState?.snapshot.yearData.values.toList()
      ?..sort((a, b) => a.year.compareTo(b.year));

    final workoutDays = ref.watch(workoutDayDefsProvider);
    WorkoutDayDef? day;
    if (visit.workoutDayId != null) {
      for (final d in workoutDays) {
        if (d.id == visit.workoutDayId) {
          day = d;
          break;
        }
      }
    }

    final findings = yearsAscending == null
        ? const <AnalysisFinding>[]
        : analyzeExercises(
            yearsAscending: yearsAscending,
            exerciseNames: visit.entries.map((e) => e.exercise.name).toList(),
            bodyWeightEntries: ref.watch(bodyWeightEntriesProvider),
            settings: ref.watch(appSettingsServiceProvider),
            day: day,
          );

    WorkoutXpBreakdown? xpBreakdown;
    if (yearsAscending != null) {
      final realEntries = buildHistoryEntries(yearsAscending)
          .where((e) => e.metaRow != null)
          .toList();
      HistoryEntry? thisEntry;
      for (final entry in realEntries) {
        if (entry.metaRow?.visitId == visit.visitId) {
          thisEntry = entry;
          break;
        }
      }
      if (thisEntry != null) {
        xpBreakdown = computeWorkoutXp(
          visit: thisEntry,
          realEntries: realEntries,
          prHistory: prsByExercise(realEntries),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Workout logged')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      'Nice work — ${visit.entries.length} exercise${visit.entries.length == 1 ? '' : 's'} logged 💪',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (xpBreakdown != null) ...[
                      const SizedBox(height: 12),
                      _XpEarnedCard(breakdown: xpBreakdown),
                    ],
                    const SizedBox(height: 16),
                    InsightSummaryList(findings: findings),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                  (route) => false,
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// This workout's XP total, broken into the components that earned it —
/// shown only when any bonus fired, so a plain workout doesn't get a
/// cluttered all-zero breakdown.
class _XpEarnedCard extends StatelessWidget {
  const _XpEarnedCard({required this.breakdown});

  final WorkoutXpBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, int)>[
      ('Workout', breakdown.base),
      if (breakdown.prBonus > 0) ('New PR', breakdown.prBonus),
      if (breakdown.streakBonus > 0) ('Streak kept', breakdown.streakBonus),
      if (breakdown.improvementBonus > 0) ('Improving', breakdown.improvementBonus),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '+${breakdown.total} XP',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (label, amount) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: theme.textTheme.bodyMedium),
                    Text('+$amount', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
