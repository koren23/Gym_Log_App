import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analysis_result.dart';
import '../models/pending_suggestion.dart';
import '../providers/analysis_providers.dart';
import '../providers/settings_providers.dart';
import '../screens/settings/settings_screen.dart';

/// A single [AnalysisFinding] rendered with, when [AnalysisFinding.kind] is
/// actionable, a "Do this"/"Not now" button pair — the primary actionable
/// surface for suggestion variety (see `PostSaveInsightScreen`,
/// `WeeklyInsightBox`). A [SuggestionKind.none] finding renders as plain
/// text (no buttons) — nothing to accept/dismiss.
class SuggestionCard extends ConsumerWidget {
  const SuggestionCard({super.key, required this.finding});

  final AnalysisFinding finding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actionable = finding.kind != SuggestionKind.none;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: finding.isPlateaued
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            finding.subjectName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(finding.message, style: theme.textTheme.bodyMedium),
          if (finding.suggestion != null) ...[
            const SizedBox(height: 6),
            Text(
              finding.suggestion!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (actionable) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _dismiss(ref),
                  child: const Text('Not now'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => _accept(context, ref),
                  child: Text(_actionLabel(finding.kind)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _actionLabel(SuggestionKind kind) => switch (kind) {
    SuggestionKind.changeExercise => 'Swap exercise',
    SuggestionKind.changeRepRangeForSet => 'Update this set',
    SuggestionKind.changeRepRangeOverall => 'Update rep range',
    SuggestionKind.changeWeightForSet => 'Update this set',
    SuggestionKind.changeTotalWeight => 'Update weight',
    SuggestionKind.deload => 'Apply deload',
    SuggestionKind.changeWorkoutDay => 'Review this day',
    SuggestionKind.none => 'Do this',
  };

  Future<void> _recordShown(WidgetRef ref) {
    final payload = finding.payload;
    return ref
        .read(appSettingsServiceProvider)
        .recordSuggestionShown(
          finding.kind,
          finding.subjectName,
          detail: payload is ExerciseSwapPayload
              ? payload.replacement.name
              : null,
        );
  }

  Future<void> _dismiss(WidgetRef ref) async {
    await ref
        .read(appSettingsServiceProvider)
        .dismissSuggestion(finding.kind, finding.subjectName);
    await _recordShown(ref);
    ref.invalidate(proactiveFindingsProvider);
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final payload = finding.payload;
    if (finding.kind == SuggestionKind.changeWorkoutDay) {
      await _recordShown(ref);
      if (!context.mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return;
    }

    final pending = switch (payload) {
      RepRangeSuggestionPayload(:final setIndex, :final newLow, :final newHigh) =>
        PendingSuggestion(
          kind: finding.kind,
          subjectExerciseName: finding.subjectName,
          setIndex: setIndex,
          newRepRangeLow: newLow,
          newRepRangeHigh: newHigh,
          acceptedAt: DateTime.now(),
        ),
      WeightSuggestionPayload(:final setIndex, :final newWeight) =>
        PendingSuggestion(
          kind: finding.kind,
          subjectExerciseName: finding.subjectName,
          setIndex: setIndex,
          newWeight: newWeight,
          acceptedAt: DateTime.now(),
        ),
      ExerciseSwapPayload(:final replacement) => PendingSuggestion(
        kind: finding.kind,
        subjectExerciseName: finding.subjectName,
        replacementExercise: replacement,
        acceptedAt: DateTime.now(),
      ),
      _ => null,
    };
    if (pending == null) return;
    await ref.read(pendingSuggestionsProvider.notifier).accept(pending);
    await _recordShown(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Got it — applied next time you log ${finding.subjectName}.',
        ),
      ),
    );
  }
}
