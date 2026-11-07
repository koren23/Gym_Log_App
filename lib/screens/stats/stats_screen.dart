import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/body_zones.dart';
import '../../core/constants/muscle_groups.dart';
import '../../core/utils/exercise_muscle_resolution.dart';
import '../../models/history_entry.dart';
import '../../models/personal_record.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../services/analysis/muscle_balance.dart';
import '../../services/analysis/stats_engine.dart';
import '../../services/analysis/xp_engine.dart';
import '../../services/settings/app_settings_service.dart';
import '../../widgets/barbell_progress_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/streak_color.dart';

final _dateFormat = DateFormat.yMMMd();

/// Whole-history derived stats: frequency, PRs, streaks, muscle balance
/// (per-zone list), long-term goal nudges, and the XP/League progress bar —
/// everything here is recomputed from already-loaded history on every
/// build, nothing is written to the sheet.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
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
    final allVisitDates = buildHistoryEntries(yearsAscending)
        .map((e) => e.date)
        .toList();
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
      allVisitDates: allVisitDates,
    );

    final zoneScores = zoneCurrentLevelScores(
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
    final estimatedDuration = estimatedWorkoutDuration(
      mostRecentVisit,
      exercisesByName: exercisesByName,
    );
    final heightCm = ref.watch(appSettingsServiceProvider).heightCm;
    final biologicalSex = ref.watch(appSettingsServiceProvider).biologicalSex;
    final birthDate = ref.watch(appSettingsServiceProvider).birthDate;
    final trainingStartDate =
        ref.watch(appSettingsServiceProvider).trainingStartDate ??
        workingOutSince(realEntries)!;

    final frequency = exerciseFrequency(realEntries).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topExercises = frequency.take(3).toList();

    final personalRecords = [
      ...ref.watch(appSettingsServiceProvider).personalRecords,
    ]..sort((a, b) => b.date.compareTo(a.date));

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
                _dateFormat.format(trainingStartDate),
              ),
              _StatRow(
                'Training for',
                trainingDurationLabel(trainingStartDate),
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
                Builder(
                  builder: (context) {
                    final bmiValue = bmi(
                      weightKg: latestBodyWeightKg,
                      heightCm: heightCm,
                    );
                    final category = bmiCategory(bmiValue);
                    return _StatRow(
                      'BMI',
                      '${bmiValue.toStringAsFixed(1)} · '
                          '${kBmiCategoryLabels[category]}',
                      valueColor: _bmiCategoryColor(category),
                    );
                  },
                )
              else if (latestBodyWeightKg != null)
                Text(
                  'Set your height in Settings to see your BMI.',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              if (latestBodyWeightKg != null &&
                  heightCm != null &&
                  biologicalSex != null &&
                  birthDate != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _showCalorieCalculator(
                      context,
                      weightKg: latestBodyWeightKg,
                      heightCm: heightCm,
                      sex: biologicalSex,
                      birthDate: birthDate,
                      realEntries: realEntries,
                    ),
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Maintenance calories'),
                  ),
                )
              else
                Text(
                  'Set your height, sex, birth date and a body weight '
                  'entry in Settings to see your maintenance calories.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          _StatsCard(
            title: 'Records',
            icon: Icons.emoji_events,
            accentColor: Colors.amber[700]!,
            headline: personalRecords.isEmpty ? null : personalRecords.first.exerciseName,
            headlineLabel: personalRecords.isEmpty ? null : 'Most recent PR',
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _addPersonalRecord(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Log a PR'),
                ),
              ),
              if (personalRecords.isEmpty)
                Text(
                  'No PRs logged yet — tap "Log a PR" when you hit one.',
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final record in personalRecords.take(5))
                  _StatRow(
                    record.exerciseName,
                    [
                      if (record.weightKg != null)
                        '${record.weightKg!.toStringAsFixed(1)} kg',
                      '${record.reps} reps',
                    ].join(' · '),
                    onDelete: () => _deletePersonalRecord(record.id),
                  ),
            ],
          ),
          _StatsCard(
            title: 'Consistency',
            icon: Icons.local_fire_department_outlined,
            accentColor: streakColor(currentStreakWeeks(allVisitDates)),
            headline: '${currentStreakWeeks(allVisitDates)}-week streak',
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
              for (final zone in BodyZone.values)
                _ZoneScoreRow(
                  label: kBodyZoneLabels[zone]!,
                  score: zoneScores[zone],
                  onTap: () => _showZoneBreakdown(context, zone, muscleTotals),
                ),
              const SizedBox(height: 8),
              const _MuscleBalanceLegend(),
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

  Future<void> _addPersonalRecord(BuildContext context) async {
    final result = await showDialog<PersonalRecord>(
      context: context,
      builder: (context) => const _AddPersonalRecordDialog(),
    );
    if (result == null) return;
    await ref.read(appSettingsServiceProvider).addPersonalRecord(result);
    setState(() {});
  }

  Future<void> _deletePersonalRecord(String id) async {
    await ref.read(appSettingsServiceProvider).deletePersonalRecord(id);
    setState(() {});
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

  void _showCalorieCalculator(
    BuildContext context, {
    required double weightKg,
    required double heightCm,
    required BiologicalSex sex,
    required DateTime birthDate,
    required List<HistoryEntry> realEntries,
  }) {
    final age = ageYears(birthDate);
    final bmrValue = bmr(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      sex: sex,
    );
    final frequency = workoutsPerWeek(realEntries);
    final activityLevel = activityLevelFor(frequency);
    final targets = calorieTargets(
      bmrValue: bmrValue,
      activityLevel: activityLevel,
    );

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Maintenance calories'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Based on ${activityLevel.label.toLowerCase()} '
              '(${frequency.toStringAsFixed(1)} workouts/week).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _StatRow('Maintenance', '${targets.maintenance.round()} kcal/day'),
            _StatRow(
              'Lose 0.25 kg/week',
              '${targets.mildLoss.round()} kcal/day',
            ),
            _StatRow('Lose 0.5 kg/week', '${targets.loss.round()} kcal/day'),
            _StatRow(
              'Gain 0.25 kg/week',
              '${targets.mildGain.round()} kcal/day',
            ),
            _StatRow('Gain 0.5 kg/week', '${targets.gain.round()} kcal/day'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// One tappable muscle-zone row: a score-colored dot, the zone's label, and
/// (when available) its score as a percent of the "at your own historical
/// average" baseline — tapping opens that zone's per-muscle-group breakdown.
class _ZoneScoreRow extends StatelessWidget {
  const _ZoneScoreRow({
    required this.label,
    required this.score,
    required this.onTap,
  });

  final String label;
  final double? score;
  final VoidCallback onTap;

  /// "Safe"/progress-reading green at `score == 1`ish, red at `0`, gray when
  /// there isn't yet enough history to compute a score at all.
  static Color _colorForScore(BuildContext context, double? score) {
    if (score == null) {
      return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
    final t = (score / 2).clamp(0.0, 1.0);
    if (t < 0.5) {
      return Color.lerp(Colors.redAccent, Colors.orange, t * 2)!;
    }
    return Color.lerp(Colors.orange, Colors.green, (t - 0.5) * 2)!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = this.score;
    final color = _colorForScore(context, score);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              score == null ? 'No data' : '${(score * 100).round()}%',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains what the zone-score percentage and dot colors above actually
/// mean: this zone's last-4-weeks average weekly volume as a percentage of
/// its own all-time average weekly volume (`zoneCurrentLevelScores`,
/// clamped to 0-200%) — never an absolute measure against anyone else.
class _MuscleBalanceLegend extends StatelessWidget {
  const _MuscleBalanceLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget dot(Color color) => Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dot(Colors.redAccent),
                Text('Below your average', style: theme.textTheme.bodySmall),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dot(Colors.orange),
                Text('At your average', style: theme.textTheme.bodySmall),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dot(Colors.green),
                Text('Above your average', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Each zone\'s % is its recent 4-week volume vs. its own '
          'all-time average — not a comparison to anyone else. '
          '"No data" means gray: not enough history yet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
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
  const _StatRow(this.label, this.value, {this.valueColor, this.onDelete});

  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 3,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          if (onDelete != null)
            InkWell(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small form for manually logging a PR — exercise name, required reps,
/// an optional weight, and a date (defaulting to today). Returns the new
/// [PersonalRecord] via [Navigator.pop], or null if cancelled.
class _AddPersonalRecordDialog extends StatefulWidget {
  const _AddPersonalRecordDialog();

  @override
  State<_AddPersonalRecordDialog> createState() =>
      _AddPersonalRecordDialogState();
}

class _AddPersonalRecordDialogState extends State<_AddPersonalRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _exerciseController = TextEditingController();
  final _weightController = TextEditingController();
  final _repsController = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _exerciseController.dispose();
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _exerciseController.text.trim();
    final weight = double.tryParse(_weightController.text.trim());
    final reps = int.parse(_repsController.text.trim());
    Navigator.of(context).pop(
      PersonalRecord(
        id: const Uuid().v4(),
        exerciseName: name,
        date: _date,
        reps: reps,
        weightKg: weight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log a PR'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _exerciseController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Exercise'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                  ? 'Required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _repsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reps'),
              validator: (value) {
                final reps = int.tryParse((value ?? '').trim());
                if (reps == null || reps <= 0) return 'Required';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Weight (kg, optional)',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat.yMMMd().format(_date)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// "Safe"-reading green for a normal BMI, warmer tones the further a
/// category drifts from it in either direction.
Color _bmiCategoryColor(BmiCategory category) => switch (category) {
  BmiCategory.normal => Colors.green,
  BmiCategory.underweight => Colors.amber[700]!,
  BmiCategory.overweight => Colors.orange,
  BmiCategory.obese => Colors.redAccent,
};
