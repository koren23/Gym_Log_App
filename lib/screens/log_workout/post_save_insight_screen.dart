import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/analysis_result.dart';
import '../../models/workout_visit.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/sheet_data_providers.dart';
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

    final findings = yearsAscending == null
        ? const <AnalysisFinding>[]
        : analyzeExercises(
            yearsAscending: yearsAscending,
            exerciseNames: visit.entries.map((e) => e.exercise.name).toList(),
            bodyWeightEntries: ref.watch(bodyWeightEntriesProvider),
          );

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
