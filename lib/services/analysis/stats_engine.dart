import '../../core/constants/muscle_groups.dart';
import '../../models/exercise.dart';
import '../../models/history_entry.dart';
import '../settings/app_settings_service.dart';
import 'volume.dart';

/// Pure stats helpers for the Stats tab — same style as `AnalysisEngine`,
/// operating over already-loaded [HistoryEntry]s rather than raw sheet
/// data. Nothing here writes to the sheet; every value is recomputed from
/// history on every load, exactly like the rest of this app's derived
/// stats, so a retroactive log edit is always reflected immediately.

/// Earliest real (app-logged) visit date — "working out since" — or null
/// if there are no real visits yet.
DateTime? workingOutSince(List<HistoryEntry> realEntries) {
  if (realEntries.isEmpty) return null;
  return realEntries.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Human-readable "how long ago" label for a training start date, e.g.
/// "2 years, 3 months", "5 months", "3 weeks", or "4 days" — always the two
/// largest non-zero units (one unit once we're down to weeks/days), so it
/// reads naturally at any age rather than spelling out exact day counts.
String trainingDurationLabel(DateTime since, {DateTime? now}) {
  final today = now ?? DateTime.now();
  var totalDays = today.difference(DateTime(since.year, since.month, since.day)).inDays;
  if (totalDays < 0) totalDays = 0;

  final years = totalDays ~/ 365;
  final remainingAfterYears = totalDays % 365;
  final months = remainingAfterYears ~/ 30;
  final remainingAfterMonths = remainingAfterYears % 30;
  final weeks = remainingAfterMonths ~/ 7;
  final days = remainingAfterMonths % 7;

  String unit(int n, String name) => '$n $name${n == 1 ? '' : 's'}';

  if (years > 0) {
    return months > 0
        ? '${unit(years, 'year')}, ${unit(months, 'month')}'
        : unit(years, 'year');
  }
  if (months > 0) {
    return weeks > 0
        ? '${unit(months, 'month')}, ${unit(weeks, 'week')}'
        : unit(months, 'month');
  }
  if (weeks > 0) {
    return unit(weeks, 'week');
  }
  return unit(days, 'day');
}

/// Average real visits per week over the last [windowWeeks] weeks (ending
/// today), as a simple frequency metric.
double workoutsPerWeek(List<HistoryEntry> realEntries, {int windowWeeks = 8}) {
  final since = DateTime.now().subtract(Duration(days: windowWeeks * 7));
  final count = realEntries.where((e) => !e.date.isBefore(since)).length;
  return count / windowWeeks;
}

/// Visit count per exercise name, across every real visit — used to find
/// the most/least commonly logged exercises.
Map<String, int> exerciseFrequency(List<HistoryEntry> realEntries) {
  final counts = <String, int>{};
  for (final entry in realEntries) {
    for (final name in entry.exerciseNames) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  return counts;
}

/// Mean reps-per-set across every real visit's every logged set (visits
/// with no per-set rep data don't contribute).
double averageRepsOverall(List<HistoryEntry> realEntries) {
  var totalReps = 0;
  var totalSets = 0;
  for (final entry in realEntries) {
    final meta = entry.metaRow;
    if (meta == null) continue;
    for (final range in meta.exercises) {
      for (final reps in range.actualReps) {
        totalReps += reps;
        totalSets++;
      }
    }
  }
  return totalSets == 0 ? 0 : totalReps / totalSets;
}

/// Standard BMI (`kg / (m)^2`) from body weight and height.
double bmi({required double weightKg, required double heightCm}) {
  final heightM = heightCm / 100;
  return weightKg / (heightM * heightM);
}

/// Standard WHO adult BMI category for a given [bmi] value.
enum BmiCategory { underweight, normal, overweight, obese }

const Map<BmiCategory, String> kBmiCategoryLabels = {
  BmiCategory.underweight: 'Underweight',
  BmiCategory.normal: 'Normal',
  BmiCategory.overweight: 'Overweight',
  BmiCategory.obese: 'Obese',
};

BmiCategory bmiCategory(double bmi) {
  if (bmi < 18.5) return BmiCategory.underweight;
  if (bmi < 25) return BmiCategory.normal;
  if (bmi < 30) return BmiCategory.overweight;
  return BmiCategory.obese;
}

/// Age in whole years as of [now] (defaults to today).
int ageYears(DateTime birthDate, {DateTime? now}) {
  final today = now ?? DateTime.now();
  var age = today.year - birthDate.year;
  if (today.month < birthDate.month ||
      (today.month == birthDate.month && today.day < birthDate.day)) {
    age--;
  }
  return age;
}

/// Basal metabolic rate via the Mifflin-St Jeor equation — the same
/// formula calculator.net's calorie calculator uses.
double bmr({
  required double weightKg,
  required double heightCm,
  required int age,
  required BiologicalSex sex,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return sex == BiologicalSex.male ? base + 5 : base - 161;
}

/// Standard activity tiers (calculator.net's multiplier scale) used to turn
/// BMR into maintenance calories (TDEE).
enum ActivityLevel {
  sedentary(1.2, 'Sedentary'),
  light(1.375, 'Lightly active'),
  moderate(1.55, 'Moderately active'),
  veryActive(1.725, 'Very active'),
  extraActive(1.9, 'Extra active');

  const ActivityLevel(this.multiplier, this.label);
  final double multiplier;
  final String label;
}

/// Maps a workouts-per-week frequency (see [workoutsPerWeek]) onto an
/// [ActivityLevel] tier — a rough but reasonable proxy, since this app has
/// no other activity-tracking input.
ActivityLevel activityLevelFor(double workoutsPerWeek) {
  if (workoutsPerWeek < 1) return ActivityLevel.sedentary;
  if (workoutsPerWeek < 3) return ActivityLevel.light;
  if (workoutsPerWeek < 5) return ActivityLevel.moderate;
  if (workoutsPerWeek < 6) return ActivityLevel.veryActive;
  return ActivityLevel.extraActive;
}

/// Maintenance calories plus the four lose/gain targets calculator.net
/// shows, derived from [bmr] (`kg` of body fat ≈ 7700 kcal).
class CalorieTargets {
  const CalorieTargets({
    required this.maintenance,
    required this.mildLoss,
    required this.loss,
    required this.mildGain,
    required this.gain,
  });

  /// Maintenance calories/day (`bmr * activity multiplier`).
  final double maintenance;

  /// To lose ~0.25kg/week.
  final double mildLoss;

  /// To lose ~0.5kg/week.
  final double loss;

  /// To gain ~0.25kg/week.
  final double mildGain;

  /// To gain ~0.5kg/week.
  final double gain;
}

CalorieTargets calorieTargets({
  required double bmrValue,
  required ActivityLevel activityLevel,
}) {
  final maintenance = bmrValue * activityLevel.multiplier;
  return CalorieTargets(
    maintenance: maintenance,
    mildLoss: maintenance - 275,
    loss: maintenance - 550,
    mildGain: maintenance + 275,
    gain: maintenance + 550,
  );
}

/// Rough calorie estimate from training volume rather than time: every rep
/// has a small fixed cost, every set adds a flat under-tension/transition
/// cost, both scaled by body weight against a 70kg reference. Labelled
/// "rough estimate" in the UI — this is not a precise metabolic measurement.
double estimatedCaloriesBurned({
  required double bodyWeightKg,
  required int totalReps,
  required int totalSets,
  double kcalPerRep = 0.5,
  double kcalPerSetOverhead = 2.0,
}) =>
    (kcalPerRep * totalReps + kcalPerSetOverhead * totalSets) *
    (bodyWeightKg / 70.0);

/// Running-max PRs per exercise across every real visit, walked
/// chronologically — a PR is a new running max, either in heaviest single
/// set weight or in total instance volume (see [instanceVolume]).
class PrsByExercise {
  PrsByExercise({
    required this.maxWeight,
    required this.maxWeightDate,
    required this.maxVolume,
    required this.maxVolumeDate,
    required this.weightPrCount,
    required this.volumePrCount,
  });

  final Map<String, double> maxWeight;
  final Map<String, DateTime> maxWeightDate;
  final Map<String, double> maxVolume;
  final Map<String, DateTime> maxVolumeDate;

  /// Total number of new running-max weight PRs set across all history —
  /// used by the XP engine.
  final int weightPrCount;

  /// Total number of new running-max volume PRs set across all history.
  final int volumePrCount;
}

PrsByExercise prsByExercise(List<HistoryEntry> realEntries) {
  final sorted = [...realEntries]..sort((a, b) => a.date.compareTo(b.date));

  final maxWeight = <String, double>{};
  final maxWeightDate = <String, DateTime>{};
  final maxVolume = <String, double>{};
  final maxVolumeDate = <String, DateTime>{};
  var weightPrCount = 0;
  var volumePrCount = 0;

  for (final visit in sorted) {
    final meta = visit.metaRow;
    if (meta == null) continue;
    for (final range in meta.exercises) {
      final name = range.exerciseName;

      if (range.actualWeights.isNotEmpty) {
        final heaviestSet = range.actualWeights.reduce(
          (a, b) => a > b ? a : b,
        );
        if (heaviestSet > (maxWeight[name] ?? 0)) {
          maxWeight[name] = heaviestSet;
          maxWeightDate[name] = visit.date;
          weightPrCount++;
        }
      }

      final volume = instanceVolume(range);
      if (volume != null && volume > (maxVolume[name] ?? 0)) {
        maxVolume[name] = volume;
        maxVolumeDate[name] = visit.date;
        volumePrCount++;
      }
    }
  }

  return PrsByExercise(
    maxWeight: maxWeight,
    maxWeightDate: maxWeightDate,
    maxVolume: maxVolume,
    maxVolumeDate: maxVolumeDate,
    weightPrCount: weightPrCount,
    volumePrCount: volumePrCount,
  );
}

/// Number of consecutive recent weeks (ending with the most recent visit's
/// week, or this week if more recent) that have at least one real visit.
int currentStreakWeeks(List<DateTime> visitDates) {
  if (visitDates.isEmpty) return 0;
  final weeks = visitDates.map(_weekKey).toSet();
  var streak = 0;
  var cursor = _weekKey(DateTime.now());
  while (weeks.contains(cursor)) {
    streak++;
    cursor = _weekBefore(cursor);
  }
  if (streak == 0) {
    // This week has no visit yet — check if last week does, so a streak
    // in progress doesn't read as broken until the week is actually over.
    cursor = _weekBefore(_weekKey(DateTime.now()));
    while (weeks.contains(cursor)) {
      streak++;
      cursor = _weekBefore(cursor);
    }
  }
  return streak;
}

/// Longest run of consecutive weeks with at least one real visit, ever.
int longestStreakWeeks(List<DateTime> visitDates) {
  if (visitDates.isEmpty) return 0;
  final weeks = visitDates.map(_weekKey).toSet().toList()
    ..sort((a, b) {
      final yearCmp = a.$1.compareTo(b.$1);
      return yearCmp != 0 ? yearCmp : a.$2.compareTo(b.$2);
    });
  var longest = 0;
  var current = 0;
  (int, int)? previous;
  for (final week in weeks) {
    if (previous != null && week == _weekBefore(previous)) {
      current++;
    } else {
      current = 1;
    }
    longest = current > longest ? current : longest;
    previous = week;
  }
  return longest;
}

/// Percent of weeks since [since] (or the earliest visit, if null) that
/// have at least one real visit.
double consistencyPct(List<DateTime> visitDates, {DateTime? since}) {
  if (visitDates.isEmpty) return 0;
  final start = since ?? visitDates.reduce((a, b) => a.isBefore(b) ? a : b);
  final totalWeeks = (DateTime.now().difference(start).inDays / 7).ceil();
  if (totalWeeks <= 0) return 0;
  final activeWeeks = visitDates.map(_weekKey).toSet().length;
  return (activeWeeks / totalWeeks * 100).clamp(0, 100);
}

/// Days since each [MuscleGroup] (resolved including secondaries, see
/// `muscle_balance.dart`) was last trained — missing from the map if never
/// trained.
Map<MuscleGroup, int> daysSinceLastTrained(
  List<HistoryEntry> realEntries,
  Map<String, Exercise> exercisesByName,
  DateTime now,
) {
  final lastTrained = <MuscleGroup, DateTime>{};
  for (final visit in realEntries) {
    final meta = visit.metaRow;
    if (meta == null) continue;
    for (final range in meta.exercises) {
      final exercise = exercisesByName[range.exerciseName.toLowerCase()];
      if (exercise == null) continue;
      for (final group in [exercise.muscleGroup, ...exercise.secondaryMuscleGroups]) {
        final existing = lastTrained[group];
        if (existing == null || visit.date.isAfter(existing)) {
          lastTrained[group] = visit.date;
        }
      }
    }
  }
  return {
    for (final entry in lastTrained.entries)
      entry.key: now.difference(entry.value).inDays,
  };
}

/// A simple long-term progress nudge for the Stats tab's Goals card —
/// deliberately not reusing `AnalysisFinding`/`SuggestionCard`, which are
/// short-term, per-exercise/per-day nudges; these are whole-history,
/// quarter-scale observations.
class GoalNudge {
  const GoalNudge({required this.title, required this.detail});
  final String title;
  final String detail;
}

List<GoalNudge> longTermGoals({
  required List<HistoryEntry> realEntries,
  required Map<MuscleGroup, double> recentVolumeTotals,
  required Map<MuscleGroup, double> previousVolumeTotals,
  List<DateTime>? allVisitDates,
}) {
  final goals = <GoalNudge>[];
  final visitDates = realEntries.map((e) => e.date).toList();

  final consistency = consistencyPct(visitDates);
  if (visitDates.isNotEmpty) {
    goals.add(
      GoalNudge(
        title: "You've trained ${consistency.round()}% of weeks",
        detail: 'Since ${_formatDate(workingOutSince(realEntries)!)}.',
      ),
    );
  }

  final streak = currentStreakWeeks(allVisitDates ?? visitDates);
  if (streak >= 2) {
    goals.add(
      GoalNudge(
        title: '$streak-week streak',
        detail: "You've trained at least once a week for $streak weeks running.",
      ),
    );
  }

  var totalRecent = 0.0;
  var totalPrevious = 0.0;
  for (final group in recentVolumeTotals.keys) {
    totalRecent += recentVolumeTotals[group] ?? 0;
    totalPrevious += previousVolumeTotals[group] ?? 0;
  }
  if (totalPrevious > 0) {
    final pctChange = (totalRecent - totalPrevious) / totalPrevious * 100;
    if (pctChange.abs() >= 1) {
      goals.add(
        GoalNudge(
          title:
              'Overall volume ${pctChange >= 0 ? 'up' : 'down'} ${pctChange.abs().round()}%',
          detail: 'Compared to the equivalent earlier window.',
        ),
      );
    }
  }

  return goals;
}

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

(int, int) _weekKey(DateTime date) {
  final monday = date.subtract(Duration(days: date.weekday - 1));
  final jan1 = DateTime(monday.year, 1, 1);
  final week = ((monday.difference(jan1).inDays) / 7).floor() + 1;
  return (monday.year, week);
}

(int, int) _weekBefore((int, int) key) {
  final (year, week) = key;
  if (week > 1) return (year, week - 1);
  return (year - 1, 52);
}
