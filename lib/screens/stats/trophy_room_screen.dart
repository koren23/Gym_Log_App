import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/muscle_groups.dart';
import '../../core/utils/exercise_muscle_resolution.dart';
import '../../core/utils/exercise_value_format.dart';
import '../../core/utils/text.dart';
import '../../models/exercise.dart';
import '../../models/history_entry.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/local_history_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../services/analysis/stats_engine.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_skeleton.dart';

final _dateFormat = DateFormat.yMMMd();

/// Auto-computed, all-time-best-per-exercise PR board — distinct from the
/// Stats screen's "Records" card (hand-typed PR log) and the in-the-moment
/// PR snackbar shown while logging (a one-shot toast, not browsable later).
/// Every number here comes straight from [prsByExercise]'s running-max walk
/// over real logged history.
class TrophyRoomScreen extends ConsumerWidget {
  const TrophyRoomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitsAsync = ref.watch(localVisitsProvider);
    final visits = visitsAsync.value;

    if (visitsAsync.isLoading && visits == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trophy room')),
        body: const ChartScreenSkeleton(),
      );
    }

    final realEntries = visits == null
        ? const <HistoryEntry>[]
        : buildHistoryEntries(visits).where((e) => !e.isSynthetic).toList();
    final prs = prsByExercise(realEntries);
    final exercisesByName = resolvedExercisesByName(
      ref.watch(allKnownExercisesProvider),
    );

    final names = {...prs.maxWeight.keys, ...prs.maxVolume.keys};

    final byGroup = <MuscleGroup, List<String>>{};
    final ungrouped = <String>[];
    for (final name in names) {
      final exercise = exercisesByName[name.toLowerCase()];
      final group = exercise != null && exercise.muscleGroupKnown
          ? exercise.muscleGroup
          : null;
      if (group == null || group.legacy) {
        ungrouped.add(name);
      } else {
        byGroup.putIfAbsent(group, () => []).add(name);
      }
    }
    for (final list in byGroup.values) {
      list.sort();
    }
    ungrouped.sort();

    final hasAnyTrophy = names.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Trophy room')),
      body: !hasAnyTrophy
          ? const EmptyState(
              icon: Icons.emoji_events_outlined,
              message: 'Log a workout with weights or reps to start '
                  'earning trophies.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                for (final group in kCurrentMuscleGroups)
                  if (byGroup[group] case final exerciseNames?
                      when exerciseNames.isNotEmpty)
                    _MuscleGroupSection(
                      title: titleCase(group.sheetHeader),
                      exerciseNames: exerciseNames,
                      exercisesByName: exercisesByName,
                      prs: prs,
                    ),
                if (ungrouped.isNotEmpty)
                  _MuscleGroupSection(
                    title: 'Other',
                    exerciseNames: ungrouped,
                    exercisesByName: exercisesByName,
                    prs: prs,
                  ),
              ],
            ),
    );
  }
}

class _MuscleGroupSection extends StatelessWidget {
  const _MuscleGroupSection({
    required this.title,
    required this.exerciseNames,
    required this.exercisesByName,
    required this.prs,
  });

  final String title;
  final List<String> exerciseNames;
  final Map<String, Exercise> exercisesByName;
  final PrsByExercise prs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          for (final name in exerciseNames)
            _TrophyCard(
              name: name,
              exercise: exercisesByName[name.toLowerCase()],
              maxWeight: prs.maxWeight[name],
              maxWeightDate: prs.maxWeightDate[name],
              maxVolume: prs.maxVolume[name],
              maxVolumeDate: prs.maxVolumeDate[name],
            ),
        ],
      ),
    );
  }
}

class _TrophyCard extends StatelessWidget {
  const _TrophyCard({
    required this.name,
    required this.exercise,
    required this.maxWeight,
    required this.maxWeightDate,
    required this.maxVolume,
    required this.maxVolumeDate,
  });

  final String name;
  final Exercise? exercise;
  final double? maxWeight;
  final DateTime? maxWeightDate;
  final double? maxVolume;
  final DateTime? maxVolumeDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amber = Colors.amber[700]!;
    final knownExercise = exercise;

    final weightLine = maxWeight == null
        ? null
        : 'Best set: ${knownExercise != null ? formatExerciseValue(knownExercise.unit, maxWeight!, customLabel: knownExercise.customUnitLabel) : '${maxWeight!.toStringAsFixed(1)}kg'}'
              '${maxWeightDate != null ? ' · ${_dateFormat.format(maxWeightDate!)}' : ''}';
    final volumeLine = maxVolume == null
        ? null
        : 'Best volume: ${maxVolume!.toStringAsFixed(0)}kg'
              '${maxVolumeDate != null ? ' · ${_dateFormat.format(maxVolumeDate!)}' : ''}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: amber.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.emoji_events, size: 20, color: amber),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (weightLine != null)
                    Text(weightLine, style: theme.textTheme.bodySmall),
                  if (volumeLine != null)
                    Text(volumeLine, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
