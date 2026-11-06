import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/body_zones.dart';
import '../../core/constants/muscle_groups.dart';
import '../../core/utils/exercise_muscle_resolution.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../services/analysis/muscle_balance.dart';
import '../../services/analysis/stats_engine.dart';
import '../../services/analysis/xp_engine.dart';
import '../../widgets/barbell_progress_bar.dart';
import '../../widgets/body_diagram.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_skeleton.dart';

final _dateFormat = DateFormat.yMMMd();

/// Whole-history derived stats: frequency, PRs, streaks, muscle balance
/// (body diagram), long-term goal nudges, and the XP/League progress bar —
/// everything here is recomputed from already-loaded history on every
/// build, nothing is written to the sheet. See `stats_engine.dart`'s doc
/// comment for the deliberately-deferred BMI/BMR/TDEE calorie-planning
/// scope note.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  bool _showImprovementRate = false;

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(snapshotProvider);
    final snapshotState = snapshotAsync.value;
    final yearsAscending = snapshotState?.snapshot.yearData.values.toList()
      ?..sort((a, b) => a.year.compareTo(b.year));

    if (snapshotAsync.isLoading && snapshotState == null) {
      return const ChartScreenSkeleton();
    }

    if (yearsAscending == null || yearsAscending.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(snapshotProvider.notifier).refresh(),
        child: const SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.only(top: 80),
            child: EmptyState(
              icon: Icons.insights,
              message: 'No logged workouts yet — stats will show up here.',
            ),
          ),
        ),
      );
    }

    final realEntries = buildHistoryEntries(yearsAscending)
        .where((e) => e.metaRow != null)
        .toList();

    if (realEntries.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(snapshotProvider.notifier).refresh(),
        child: const SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.only(top: 80),
            child: EmptyState(
              icon: Icons.insights,
              message: 'No logged workouts yet — stats will show up here.',
            ),
          ),
        ),
      );
    }

    final exercisesByName = resolvedExercisesByName(
      exercises: ref.watch(allKnownExercisesProvider),
      exerciseMuscleInfo: ref.watch(exerciseMuscleInfoProvider),
    );
    final bodyWeightEntries = ref.watch(bodyWeightEntriesProvider);
    final theme = Theme.of(context);

    final prs = prsByExercise(realEntries);
    final visitDates = realEntries.map((e) => e.date).toList();
    final xp = computeXp(realEntries: realEntries, prHistory: prs);
    final tier = xpTierFor(xp);
    final tierProgress = xpTierProgress(xp);

    final now = DateTime.now();
    final recentSince = now.subtract(const Duration(days: 56));
    final previousSince = now.subtract(const Duration(days: 112));
    final recentTotals = muscleVolumeTotalsSince(
      realEntries: realEntries,
      exercisesByName: exercisesByName,
      since: recentSince,
    );
    final previousWindowEntries = realEntries
        .where(
          (e) => !e.date.isBefore(previousSince) && e.date.isBefore(recentSince),
        )
        .toList();
    final previousTotals = muscleVolumeTotals(
      realEntries: previousWindowEntries,
      exercisesByName: exercisesByName,
    );
    final goals = longTermGoals(
      realEntries: realEntries,
      recentVolumeTotals: recentTotals,
      previousVolumeTotals: previousTotals,
    );

    final zoneScores = _showImprovementRate
        ? <BodyZone, double>{
            for (final entry in zoneImprovementRates(
              realEntries: realEntries,
              exercisesByName: exercisesByName,
            ).entries)
              if (entry.value != null) entry.key: 1 + entry.value! / 100,
          }
        : zoneCurrentLevelScores(
            realEntries: realEntries,
            exercisesByName: exercisesByName,
          );
    final muscleTotals = muscleVolumeTotals(
      realEntries: realEntries,
      exercisesByName: exercisesByName,
    );

    final mostRecentVisit = realEntries.reduce(
      (a, b) => a.date.isAfter(b.date) ? a : b,
    );
    final latestBodyWeightKg = bodyWeightEntries.isEmpty
        ? null
        : bodyWeightEntries
              .reduce((a, b) => a.date.isAfter(b.date) ? a : b)
              .weightKg;
    final estimatedDuration = estimatedWorkoutDuration(mostRecentVisit);

    final frequency = exerciseFrequency(realEntries).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topExercises = frequency.take(3).toList();

    final recentPrNames =
        {...prs.maxWeightDate.keys, ...prs.maxVolumeDate.keys}.toList()
          ..sort((a, b) {
            final aDate = _latestPrDate(prs, a);
            final bDate = _latestPrDate(prs, b);
            return bDate.compareTo(aDate);
          });

    return RefreshIndicator(
      onRefresh: () => ref.read(snapshotProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _StatsCard(
            title: 'Overview',
            icon: Icons.bar_chart,
            children: [
              _StatRow(
                'Working out since',
                _dateFormat.format(workingOutSince(realEntries)!),
              ),
              _StatRow(
                'Pace (last 8 weeks)',
                '${workoutsPerWeek(realEntries).toStringAsFixed(1)} workouts/week',
              ),
              _StatRow(
                'Average reps per set',
                averageRepsOverall(realEntries).toStringAsFixed(1),
              ),
              if (topExercises.isNotEmpty)
                _StatRow(
                  'Most logged',
                  topExercises
                      .map((e) => '${e.key} (${e.value}×)')
                      .join(', '),
                ),
            ],
          ),
          _StatsCard(
            title: 'League',
            icon: Icons.military_tech,
            children: [
              Row(
                children: [
                  Text(
                    tier.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text('$xp XP', style: theme.textTheme.bodyMedium),
                ],
              ),
              const SizedBox(height: 8),
              BarbellProgressBar(
                progress: tierProgress,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
          _StatsCard(
            title: 'Body & calories',
            icon: Icons.local_fire_department,
            children: [
              _StatRow(
                'Last workout, estimated duration',
                '${estimatedDuration.inMinutes} min',
              ),
              if (latestBodyWeightKg != null)
                _StatRow(
                  'Last workout, rough calorie estimate',
                  '${estimatedCaloriesBurned(bodyWeightKg: latestBodyWeightKg, duration: estimatedDuration).round()} kcal',
                )
              else
                Text(
                  'Log a body weight entry to see a rough calorie estimate.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          _StatsCard(
            title: 'Records',
            icon: Icons.emoji_events,
            children: [
              _StatRow('Weight PRs set (all time)', '${prs.weightPrCount}'),
              _StatRow('Volume PRs set (all time)', '${prs.volumePrCount}'),
              if (recentPrNames.isNotEmpty) const SizedBox(height: 8),
              for (final name in recentPrNames.take(5))
                _StatRow(
                  name,
                  [
                    if (prs.maxWeight[name] != null)
                      '${prs.maxWeight[name]!.toStringAsFixed(1)} kg',
                    if (prs.maxVolume[name] != null)
                      '${prs.maxVolume[name]!.round()} vol',
                  ].join(' · '),
                ),
            ],
          ),
          _StatsCard(
            title: 'Consistency',
            icon: Icons.local_fire_department_outlined,
            children: [
              _StatRow('Current streak', '${currentStreakWeeks(visitDates)} weeks'),
              _StatRow('Longest streak', '${longestStreakWeeks(visitDates)} weeks'),
              _StatRow(
                'Consistency',
                '${consistencyPct(visitDates).round()}% of weeks',
              ),
            ],
          ),
          _StatsCard(
            title: 'Muscle balance',
            icon: Icons.accessibility_new,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Current level')),
                    ButtonSegment(value: true, label: Text('Improvement')),
                  ],
                  selected: {_showImprovementRate},
                  onSelectionChanged: (s) =>
                      setState(() => _showImprovementRate = s.first),
                ),
              ),
              const SizedBox(height: 12),
              BodyDiagramWidget(
                scores: zoneScores,
                onZoneTap: (zone) =>
                    _showZoneBreakdown(context, zone, muscleTotals),
              ),
            ],
          ),
          if (goals.isNotEmpty)
            _StatsCard(
              title: 'Goals',
              icon: Icons.flag,
              children: [
                for (final goal in goals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(goal.detail, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  DateTime _latestPrDate(PrsByExercise prs, String name) {
    final weight = prs.maxWeightDate[name];
    final volume = prs.maxVolumeDate[name];
    if (weight == null) return volume!;
    if (volume == null) return weight;
    return weight.isAfter(volume) ? weight : volume;
  }

  void _showZoneBreakdown(
    BuildContext context,
    BodyZone zone,
    Map<MuscleGroup, double> muscleTotals,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kBodyZoneLabels[zone]!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final group in kMuscleGroupsByBodyZone[zone] ?? const [])
                _StatRow(
                  group.sheetHeader,
                  (muscleTotals[group] ?? 0) > 0
                      ? '${(muscleTotals[group] ?? 0).round()} vol'
                      : 'No logged volume',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }
}
