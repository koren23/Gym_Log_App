import '../../core/constants/body_zones.dart';
import '../../core/constants/muscle_groups.dart';
import '../../models/exercise.dart';
import '../../models/history_entry.dart';
import 'volume.dart';

/// Per-muscle total training volume across [realEntries] (app-logged
/// visits only — see [HistoryEntry.metaRow]). Shared by the Stats tab's
/// "Muscle Balance" card and the body diagram (item 7). Each exercise's
/// instance volume (see [instanceVolume]) counts at full weight toward its
/// primary muscle and at [secondaryWeightFraction] toward every muscle in
/// [Exercise.secondaryMuscleGroups] — a secondary mover gets credit, but
/// less than the muscle actually driving the lift. [exercisesByName] should
/// be keyed by lowercase exercise name (e.g. from `allKnownExercisesProvider`).
Map<MuscleGroup, double> muscleVolumeTotals({
  required List<HistoryEntry> realEntries,
  required Map<String, Exercise> exercisesByName,
  double secondaryWeightFraction = 0.5,
}) {
  final totals = <MuscleGroup, double>{};
  for (final visit in realEntries) {
    final meta = visit.metaRow;
    if (meta == null) continue;
    for (final range in meta.exercises) {
      final exercise = exercisesByName[range.exerciseName.toLowerCase()];
      if (exercise == null) continue;
      final volume = instanceVolume(range);
      if (volume == null) continue;

      totals[exercise.muscleGroup] =
          (totals[exercise.muscleGroup] ?? 0) + volume;
      for (final secondary in exercise.secondaryMuscleGroups) {
        totals[secondary] =
            (totals[secondary] ?? 0) + volume * secondaryWeightFraction;
      }
    }
  }
  return totals;
}

/// Same per-muscle accounting as [muscleVolumeTotals], but restricted to
/// [realEntries] on or after [since] — used to compute a recent-window
/// volume (e.g. "last 4 weeks") for the body diagram's "current level"
/// score.
Map<MuscleGroup, double> muscleVolumeTotalsSince({
  required List<HistoryEntry> realEntries,
  required Map<String, Exercise> exercisesByName,
  required DateTime since,
  double secondaryWeightFraction = 0.5,
}) => muscleVolumeTotals(
  realEntries: realEntries
      .where((e) => !e.date.isBefore(since))
      .toList(),
  exercisesByName: exercisesByName,
  secondaryWeightFraction: secondaryWeightFraction,
);

/// Half-vs-half percent-change trend over an ordered series of per-period
/// values (e.g. one muscle's weekly volume totals, oldest first) — same
/// shape as `AnalysisEngine._weightTrend`, kept local here rather than
/// reaching into that engine's private methods. Null if there isn't enough
/// data (fewer than 2 points, or a zero first-half average) to say
/// anything.
/// Sums the per-[MuscleGroup] totals in [muscleTotals] into per-[BodyZone]
/// totals, via [kMuscleGroupsByBodyZone] — the shared mapping between the
/// body diagram's 8 zones and this file's 18 fine-grained muscle totals.
Map<BodyZone, double> zoneVolumeTotals(Map<MuscleGroup, double> muscleTotals) {
  return {
    for (final zone in BodyZone.values)
      zone: (kMuscleGroupsByBodyZone[zone] ?? const [])
          .fold(0.0, (sum, group) => sum + (muscleTotals[group] ?? 0)),
  };
}

/// "Current level" score per [BodyZone] for the body diagram: this zone's
/// last-4-weeks average weekly volume, relative to its own all-time average
/// weekly volume — `1.0` means "right at your own historical average",
/// clamped to `[0, 2]` so the diagram's color scale stays bounded.
Map<BodyZone, double> zoneCurrentLevelScores({
  required List<HistoryEntry> realEntries,
  required Map<String, Exercise> exercisesByName,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  if (realEntries.isEmpty) {
    return {for (final zone in BodyZone.values) zone: 0.0};
  }
  final earliestDate = realEntries
      .map((e) => e.date)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final totalWeeks = (today.difference(earliestDate).inDays / 7).clamp(
    1.0,
    double.infinity,
  );

  final lifetimeTotals = zoneVolumeTotals(
    muscleVolumeTotals(
      realEntries: realEntries,
      exercisesByName: exercisesByName,
    ),
  );
  final recentTotals = zoneVolumeTotals(
    muscleVolumeTotalsSince(
      realEntries: realEntries,
      exercisesByName: exercisesByName,
      since: today.subtract(const Duration(days: 28)),
    ),
  );

  return {
    for (final zone in BodyZone.values)
      zone: _scoreZone(
        recentWeeklyVolume: (recentTotals[zone] ?? 0) / 4,
        lifetimeWeeklyVolume: (lifetimeTotals[zone] ?? 0) / totalWeeks,
      ),
  };
}

double _scoreZone({
  required double recentWeeklyVolume,
  required double lifetimeWeeklyVolume,
}) {
  if (lifetimeWeeklyVolume <= 0) return 0;
  return (recentWeeklyVolume / lifetimeWeeklyVolume).clamp(0.0, 2.0);
}

/// "Improvement rate" per [BodyZone]: the half-vs-half %-change (see
/// [windowedTrendPct]) of this zone's week-bucketed volume series — null
/// where there isn't enough history yet to compute a trend.
Map<BodyZone, double?> zoneImprovementRates({
  required List<HistoryEntry> realEntries,
  required Map<String, Exercise> exercisesByName,
}) {
  final byWeek = <(int, int), Map<BodyZone, double>>{};
  for (final visit in realEntries) {
    final meta = visit.metaRow;
    if (meta == null) continue;
    final key = (visit.isoYear, visit.isoWeek);
    final zoneTotals = byWeek.putIfAbsent(key, () => {});
    for (final range in meta.exercises) {
      final exercise = exercisesByName[range.exerciseName.toLowerCase()];
      if (exercise == null) continue;
      final volume = instanceVolume(range);
      if (volume == null) continue;
      for (final zone in BodyZone.values) {
        final groups = kMuscleGroupsByBodyZone[zone] ?? const [];
        var weight = 0.0;
        if (groups.contains(exercise.muscleGroup)) weight += 1.0;
        for (final secondary in exercise.secondaryMuscleGroups) {
          if (groups.contains(secondary)) weight += 0.5;
        }
        if (weight > 0) {
          zoneTotals[zone] = (zoneTotals[zone] ?? 0) + volume * weight;
        }
      }
    }
  }

  final weekKeys = byWeek.keys.toList()
    ..sort((a, b) {
      final yearCmp = a.$1.compareTo(b.$1);
      return yearCmp != 0 ? yearCmp : a.$2.compareTo(b.$2);
    });

  return {
    for (final zone in BodyZone.values)
      zone: windowedTrendPct([
        for (final key in weekKeys) byWeek[key]![zone] ?? 0,
      ]),
  };
}

double? windowedTrendPct(List<double> valuesOldestFirst, {int window = 6}) {
  final points = valuesOldestFirst.length > window
      ? valuesOldestFirst.sublist(valuesOldestFirst.length - window)
      : valuesOldestFirst;
  if (points.length < 2) return null;

  final half = points.length ~/ 2;
  if (half == 0) return null;
  final firstHalf = points.sublist(0, half);
  final secondHalf = points.sublist(points.length - half);
  final firstAvg = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
  final secondAvg = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
  if (firstAvg == 0) return null;

  return (secondAvg - firstAvg) / firstAvg * 100;
}
