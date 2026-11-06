import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/body_zones.dart';
import '../../core/constants/muscle_groups.dart';
import '../../core/utils/exercise_muscle_resolution.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../services/analysis/muscle_balance.dart';
import '../../services/analysis/stats_engine.dart';
import '../../services/analysis/xp_engine.dart';
import '../../widgets/barbell_progress_bar.dart';
import '../../widgets/body_diagram.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/streak_color.dart';

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

    final improvementRates = zoneImprovementRates(
      realEntries: realEntries,
      exercisesByName: exercisesByName,
    );
    final hasAnyImprovementData = improvementRates.values.any(
      (v) => v != null,
    );
    final showingImprovementFallback =
        _showImprovementRate && !hasAnyImprovementData;
    final zoneScores = _showImprovementRate && hasAnyImprovementData
        ? <BodyZone, double>{
            for (final entry in improvementRates.entries)
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
    final heightCm = ref.watch(appSettingsServiceProvider).heightCm;

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
            accentColor: theme.colorScheme.primary,
            headline: '${workoutsPerWeek(realEntries).toStringAsFixed(1)}/wk',
            headlineLabel: 'Pace (last 8 weeks)',
            children: [
              _StatRow(
                'Working out since',
                _dateFormat.format(workingOutSince(realEntries)!),
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
            accentColor: theme.colorScheme.tertiary,
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
            accentColor: Colors.deepOrange,
            headline: '${estimatedDuration.inMinutes} min',
            headlineLabel: 'Last workout, estimated duration',
            children: [
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
              if (latestBodyWeightKg != null && heightCm != null)
                _StatRow(
                  'BMI',
                  bmi(
                    weightKg: latestBodyWeightKg,
                    heightCm: heightCm,
                  ).toStringAsFixed(1),
                )
              else if (latestBodyWeightKg != null)
                Text(
                  'Set your height in Settings to see your BMI.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          _StatsCard(
            title: 'Records',
            icon: Icons.emoji_events,
            accentColor: Colors.amber[700]!,
            headline: recentPrNames.isEmpty ? null : recentPrNames.first,
            headlineLabel: recentPrNames.isEmpty ? null : 'Most recent PR',
            children: [
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
            accentColor: streakColor(currentStreakWeeks(visitDates)),
            headline: '${currentStreakWeeks(visitDates)}-week streak',
            children: [
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
            accentColor: theme.colorScheme.secondary,
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
              if (showingImprovementFallback) ...[
                const SizedBox(height: 8),
                Text(
                  'Not enough history yet to show improvement trends — '
                  'showing current level instead.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
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
              accentColor: Colors.teal,
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
    required this.accentColor,
    required this.children,
    this.headline,
    this.headlineLabel,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final String? headline;
  final String? headlineLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: accentColor.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 18, color: accentColor),
                  ),
                  const SizedBox(width: 10),
                  Text(title, style: theme.textTheme.titleMedium),
                ],
              ),
              if (headline != null) ...[
                const SizedBox(height: 10),
                Text(
                  headline!,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
                if (headlineLabel != null)
                  Text(headlineLabel!, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              ...children,
            ],
          ),
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
