import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/muscle_groups.dart';
import '../core/utils/exercise_muscle_resolution.dart';
import '../models/analysis_result.dart';
import '../models/body_weight_entry.dart';
import '../models/exercise.dart';
import '../models/history_entry.dart';
import '../models/rating_relevance.dart';
import '../models/recent_suggestion_record.dart';
import '../models/set_feedback.dart';
import '../models/workout_day_def.dart';
import '../models/year_sheet_data.dart';
import '../services/analysis/alternative_exercise_map.dart';
import '../services/analysis/analysis_engine.dart';
import '../services/analysis/volume.dart';
import '../services/analysis/workout_day_analyzer.dart';
import '../services/settings/app_settings_service.dart';
import '../widgets/simple_line_chart.dart' show ChartPoint;
import 'local_history_providers.dart';
import 'sheet_data_providers.dart';
import 'settings_providers.dart';

const _engine = AnalysisEngine();

/// Overall body-weight trend over the last [AnalysisEngine
/// .proactiveScanWindowWeeks] weeks — passed into [AnalysisEngine.analyze]
/// so a deliberate cut isn't mistaken for a lifting-weight stall.
TrendDirection bodyWeightTrend(List<BodyWeightEntry> entries) {
  final ascending = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  final cutoff = DateTime.now().subtract(
    Duration(days: 7 * AnalysisEngine.proactiveScanWindowWeeks),
  );
  final recent = ascending.where((e) => e.date.isAfter(cutoff)).toList();
  if (recent.length < 2) return TrendDirection.unknown;

  final half = recent.length ~/ 2;
  if (half == 0) return TrendDirection.flat;
  final firstHalf = recent.sublist(0, half);
  final secondHalf = recent.sublist(recent.length - half);
  final firstAvg =
      firstHalf.map((e) => e.weightKg).reduce((a, b) => a + b) /
      firstHalf.length;
  final secondAvg =
      secondHalf.map((e) => e.weightKg).reduce((a, b) => a + b) /
      secondHalf.length;
  if (firstAvg == 0) return TrendDirection.flat;

  final pctChange = (secondAvg - firstAvg) / firstAvg;
  if (pctChange >= AnalysisEngine.bodyWeightTrendThresholdPct) {
    return TrendDirection.up;
  }
  if (pctChange <= -AnalysisEngine.bodyWeightTrendThresholdPct) {
    return TrendDirection.down;
  }
  return TrendDirection.flat;
}

/// Builds a chronological weight/rep/rating history for [exerciseName]
/// across every logged visit (oldest first) — [visits] is expected
/// most-recent-last (see [localVisitsProvider]).
List<HistoryPoint> buildExerciseHistory({
  required List<MetaRow> visits,
  required String exerciseName,
}) {
  final points = <HistoryPoint>[];

  for (final visit in visits) {
    LoggedExerciseRepRange? loggedRange;
    for (final e in visit.exercises) {
      if (e.exerciseName.toLowerCase() == exerciseName.toLowerCase()) {
        loggedRange = e;
        break;
      }
    }
    if (loggedRange == null) continue;
    final actualWeights = loggedRange.actualWeights;
    if (actualWeights.isEmpty) continue;
    final avgWeight =
        actualWeights.reduce((a, b) => a + b) / actualWeights.length;

    points.add(
      HistoryPoint(
        isoYear: visit.isoYear,
        isoWeek: visit.isoWeek,
        date: visit.date,
        avgWeight: avgWeight,
        repRangeLow: loggedRange.repRangeLow,
        repRangeHigh: loggedRange.repRangeHigh,
        rating: visit.rating,
        ratingRelevance: visit.ratingRelevance,
        exactDateKnown: visit.exactDateKnown,
        totalSets: loggedRange.setCount,
        avgReps: loggedRange.avgReps,
        thumbsUpCount: loggedRange.setFeedback
            .where((f) => f == SetFeedback.up)
            .length,
        thumbsDownCount: loggedRange.setFeedback
            .where((f) => f == SetFeedback.down)
            .length,
        actualRepsPerSet: loggedRange.actualReps,
        actualWeightsPerSet: actualWeights,
        perSetFeedback: loggedRange.setFeedback,
        approxRepsPerSet: loggedRange.approxReps,
      ),
    );
  }

  return points;
}

/// Most recent logged date per exercise name (exact case, as stored on the
/// visit) across every logged visit — feeds
/// [AlternativeExerciseMap.alternativesFor]'s `lastLoggedDate` so exercise
/// swaps prefer a sibling that hasn't been trained in a while, instead of
/// always the same first candidate.
Map<String, DateTime> _lastLoggedDatesByExerciseName(List<MetaRow> visits) {
  final result = <String, DateTime>{};
  for (final visit in visits) {
    for (final ex in visit.exercises) {
      final existing = result[ex.exerciseName];
      if (existing == null || visit.date.isAfter(existing)) {
        result[ex.exerciseName] = visit.date;
      }
    }
  }
  return result;
}

/// Suggestion kinds/alternative-exercise names already shown recently for
/// [subjectName] — feeds [AnalysisEngine.analyze]'s `recentlySuggestedKinds`/
/// `recentlySuggestedAlternatives` so the same nudge doesn't repeat every
/// session. See `AppSettingsService.recentSuggestions`/
/// `recordSuggestionShown`.
({Set<String> alternatives, Set<SuggestionKind> kinds}) _recentSuggestionsFor(
  String subjectName,
  List<RecentSuggestionRecord> recentSuggestions,
) {
  final cutoff = DateTime.now().subtract(
    Duration(days: AppSettingsService.recentSuggestionCooldownDays),
  );
  final relevant = recentSuggestions.where(
    (r) => r.subjectName == subjectName && r.shownAt.isAfter(cutoff),
  );
  return (
    alternatives: {
      for (final r in relevant)
        if (r.kind == SuggestionKind.changeExercise && r.detail != null)
          r.detail!,
    },
    kinds: {for (final r in relevant) r.kind},
  );
}

/// Historical average number of sets actually performed for [exerciseName]
/// (e.g. "stairmaster usually 2 sets"), used as the default set count when
/// starting a new entry for it — rounded, clamped 1-10, over roughly the
/// last [lookback] logged instances that have per-set data on record. Null
/// when there's no such history yet (brand new exercise, or only legacy
/// rows with no per-set data), so the caller can fall back to a fixed
/// default.
int? historicalAverageSetCount({
  required List<MetaRow> visits,
  required String exerciseName,
  int lookback = 10,
}) {
  final withSets = [
    for (final h in buildExerciseHistory(visits: visits, exerciseName: exerciseName))
      if (h.totalSets != null) h.totalSets!,
  ];
  if (withSets.isEmpty) return null;
  final recent = withSets.length > lookback
      ? withSets.sublist(withSets.length - lookback)
      : withSets;
  final avg = recent.reduce((a, b) => a + b) / recent.length;
  return avg.round().clamp(1, 10);
}

/// Combines every exercise resolved to [muscle] (see
/// [resolveMuscleGroup]/[exerciseNamesByMuscleSheetHeader]) into one
/// progress series of real-visit-to-real-visit % volume change, so switching
/// exercises for the same muscle (e.g. cable -> machine lateral raises)
/// still reads as one continuous story instead of an apples-to-oranges jump
/// in raw kg.
///
/// Only ever walks real, exact-dated app-logged visits (skips
/// [MetaRow.isSynthetic] ones) and compares *volume* (weight × reps, not
/// just weight) instance-to-instance: for each matching exercise, every
/// visit after its first computable one emits a point for the % change in
/// that exercise's total volume versus its own immediately-previous visit.
/// A shared baseline across different exercises isn't used on purpose —
/// different equipment/leverage makes absolute volume incomparable, so
/// comparing each exercise only to its own previous instance is what keeps
/// the combined line honest.
List<ChartPoint> buildMuscleProgressPoints({
  required List<MetaRow> visits,
  required List<Exercise> exercises,
  required String muscle,
}) {
  final matchingNames =
      exerciseNamesByMuscleSheetHeader(exercises)[muscle] ??
      const <String>{};
  if (matchingNames.isEmpty) return const [];

  final realVisits = visits.where((v) => !v.isSynthetic).toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  final points = <ChartPoint>[];
  for (final name in matchingNames) {
    double? previousVolume;
    VolumeMethod? previousMethod;
    for (final visit in realVisits) {
      LoggedExerciseRepRange? range;
      for (final e in visit.exercises) {
        if (e.exerciseName.toLowerCase() == name.toLowerCase()) {
          range = e;
          break;
        }
      }
      if (range == null) continue;

      final result = instanceVolumeDetailed(range, matrixCellWeight: null);
      if (result == null) continue;
      final volume = result.volume;

      // The proxy (matrix-cell) and exact (per-set) computations aren't on a
      // perfectly comparable scale — a visit logged just before/after the
      // user started per-set tracking can otherwise read as a huge fake
      // spike or crash purely from the method switching, not real training
      // change. Skip emitting a point across that one transition, but keep
      // tracking forward so later same-method comparisons are unaffected.
      if (previousVolume != null &&
          previousVolume != 0 &&
          previousMethod == result.method) {
        points.add(
          ChartPoint(
            date: visit.date,
            value: (volume - previousVolume) / previousVolume * 100,
            note: name,
          ),
        );
      }
      previousVolume = volume;
      previousMethod = result.method;
    }
  }

  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
}

/// One [HistoryEntry] per logged visit (real or [MetaRow.isSynthetic] —
/// see `SheetImportService`, which is where sheet-typed-but-unlogged
/// visits are reconstructed once, at import time), sorted most-recent
/// first.
List<HistoryEntry> buildHistoryEntries(List<MetaRow> visits) {
  final entries = [
    for (final visit in visits)
      HistoryEntry(
        date: visit.date,
        isoWeek: visit.isoWeek,
        isoYear: visit.isoYear,
        exerciseNames: visit.exerciseNames,
        muscleGroups: visit.muscleGroups,
        metaRow: visit,
      ),
  ];
  entries.sort((a, b) => b.date.compareTo(a.date));
  return entries;
}

/// Per-set weights actually logged for [exerciseName] on the most recent
/// real visit (optionally strictly before [beforeDate], for an edit-visit
/// "last time" preview) — skips [MetaRow.isSynthetic] visits and ones whose
/// rating was marked unrelated, since those carry no dependable weight
/// signal.
List<double> previousActualWeights({
  required List<MetaRow> visits,
  required String exerciseName,
  DateTime? beforeDate,
}) {
  final entries = buildHistoryEntries(visits)
      .where((e) => !e.isSynthetic)
      .where((e) => e.metaRow.ratingRelevance != RatingRelevance.unrelated)
      .where((e) => beforeDate == null || e.date.isBefore(beforeDate))
      .where(
        (e) => e.metaRow.exercises.any(
          (ex) => ex.exerciseName.toLowerCase() == exerciseName.toLowerCase(),
        ),
      )
      .toList();
  if (entries.isEmpty) return const [];
  final latest = entries.first; // buildHistoryEntries is already most-recent-first
  final loggedRange = latest.metaRow.exercises.firstWhere(
    (ex) => ex.exerciseName.toLowerCase() == exerciseName.toLowerCase(),
  );
  return loggedRange.actualWeights;
}

/// Resolves a [HistoryEntry.muscleGroups] / [MetaRow.muscleGroups] list
/// (sheet-header strings) back to the [WorkoutDay] it belongs to.
WorkoutDay? workoutDayForGroupLabels(List<String> labels) {
  for (final label in labels) {
    final group = muscleGroupFromSheetHeader(label);
    if (group == null) continue;
    final day = workoutDayForMuscleGroup(group);
    if (day != null) return day;
  }
  return null;
}

/// Resolves the single most-specific [WorkoutDayDef] in [allDays] that
/// [entry] belongs to.
///
/// An explicit tag ([WorkoutVisit.workoutDayId]/[MetaRow.workoutDayId], set
/// on real visits logged after that field was added) is authoritative —
/// skip muscle-based inference entirely so a shared muscle group can never
/// misattribute a real visit to the wrong day. Returns null if the tagged
/// day no longer exists in [allDays] (e.g. deleted since).
///
/// Otherwise, two rules are tried and OR'd together per candidate day:
///  - Legacy rule: [entry]'s labels resolve to the exact same legacy
///    [WorkoutDay] as the candidate's [WorkoutDayDef.legacyDay].
///  - Current rule: every muscle group [entry] trained (resolved via the
///    current taxonomy) is within the candidate's declared set (subset
///    match).
/// Among every day satisfying either rule, the one with the fewest declared
/// muscle groups wins — so a broader day (e.g. "Upper Body") never "steals"
/// a visit/entry a narrower day (e.g. "Arms") already accounts for, since a
/// narrower day's declared groups are themselves always a subset of a
/// broader day's. Ties broken by [allDays] order.
WorkoutDayDef? bestMatchingDayForEntry(
  HistoryEntry entry,
  List<WorkoutDayDef> allDays,
) {
  final explicitId = entry.metaRow.workoutDayId;
  if (explicitId != null) {
    for (final d in allDays) {
      if (d.id == explicitId) return d;
    }
    return null;
  }

  final resolved = <MuscleGroup>{
    for (final label in entry.muscleGroups)
      if (currentMuscleFromSheetHeader(label) case final g?) g,
  };
  final legacyMatch = workoutDayForGroupLabels(entry.muscleGroups);

  WorkoutDayDef? best;
  for (final day in allDays) {
    final currentMatch =
        resolved.isNotEmpty && resolved.every(day.muscleGroups.contains);
    final legacyOk = day.legacyDay != null && day.legacyDay == legacyMatch;
    if (!currentMatch && !legacyOk) continue;
    if (best == null || day.muscleGroups.length < best.muscleGroups.length) {
      best = day;
    }
  }
  return best;
}

/// Whether [entry] belongs to [day], arbitrated against every other day in
/// [allDays] via [bestMatchingDayForEntry] — see there for the full rule
/// set.
bool historyEntryBelongsToDay(
  HistoryEntry entry,
  WorkoutDayDef day,
  List<WorkoutDayDef> allDays,
) => bestMatchingDayForEntry(entry, allDays)?.id == day.id;

/// The most recent real (app-logged, not [HistoryEntry.isSynthetic]) visit
/// belonging to [day] — skips synthetic/reconstructed entries (hand-typed
/// sheet data), which carry no per-set reps/weights/rating/note detail to
/// preview. Null if [day] has no real visit yet.
HistoryEntry? mostRecentRealVisitForDay(
  List<HistoryEntry> historyEntries,
  WorkoutDayDef day,
  List<WorkoutDayDef> allDays,
) {
  for (final entry in historyEntries) {
    if (!entry.isSynthetic && historyEntryBelongsToDay(entry, day, allDays)) {
      return entry;
    }
  }
  return null;
}

Map<String, Exercise> _exercisesByNameLower(List<Exercise> exercises) => {
  for (final e in exercises) e.name.toLowerCase(): e,
};

Map<MuscleGroup, List<Exercise>> _exercisesByMuscleGroup(
  List<Exercise> exercises,
) {
  final result = <MuscleGroup, List<Exercise>>{};
  for (final exercise in exercises) {
    final group = resolveMuscleGroup(exercise);
    if (group == null) continue;
    (result[group] ??= []).add(exercise);
  }
  return result;
}

/// Findings for every exercise trained in the last [AnalysisEngine
/// .proactiveScanWindowWeeks] weeks, most urgent first.
final proactiveFindingsProvider = Provider<List<AnalysisFinding>>((ref) {
  final visits = ref.watch(localVisitsProvider).value;
  if (visits == null) return const [];

  final cutoff = DateTime.now().subtract(
    Duration(days: 7 * AnalysisEngine.proactiveScanWindowWeeks),
  );

  final recentExerciseNames = <String>{
    for (final entry in buildHistoryEntries(visits))
      if (entry.date.isAfter(cutoff)) ...entry.exerciseNames,
  };

  final exercises = ref.watch(allKnownExercisesProvider);
  final exercisesByName = _exercisesByNameLower(exercises);
  final altMap = AlternativeExerciseMap(_exercisesByMuscleGroup(exercises));
  final lastLoggedDates = _lastLoggedDatesByExerciseName(visits);
  final settings = ref.watch(appSettingsServiceProvider);
  final dismissed = settings.dismissedSuggestionSignatures;
  final recentSuggestions = settings.recentSuggestions;
  final bwTrend = bodyWeightTrend(ref.watch(bodyWeightEntriesProvider));
  final workoutDays = ref.watch(workoutDayDefsProvider);

  bool notDismissed(AnalysisFinding f) =>
      !dismissed.contains('${f.kind.name}::${f.subjectName}');

  final findings = <AnalysisFinding>[];
  for (final name in recentExerciseNames) {
    final exercise = exercisesByName[name.toLowerCase()];
    if (exercise == null) continue;
    final history = buildExerciseHistory(visits: visits, exerciseName: name);
    final recent = _recentSuggestionsFor(name, recentSuggestions);
    final finding = _engine.analyze(
      subjectName: name,
      history: history,
      alternativeExercises: altMap.alternativesFor(
        exercise,
        lastLoggedDate: lastLoggedDates,
      ),
      recentlySuggestedAlternatives: recent.alternatives,
      recentlySuggestedKinds: recent.kinds,
      bodyWeightTrend: bwTrend,
      unit: exercise.unit,
      customUnitLabel: exercise.customUnitLabel,
    );
    if (finding == null || !notDismissed(finding)) continue;
    findings.add(finding);
  }

  // Day-level escalation: group each exercise's finding by the workout
  // day(s) it belongs to (muscle-group membership), and let
  // WorkoutDayAnalyzer decide if the day itself deserves a nudge on top of
  // the individual-exercise ones.
  const dayAnalyzer = WorkoutDayAnalyzer();
  final findingsByDay = <String, List<AnalysisFinding>>{};
  for (final finding in findings) {
    final exercise = exercisesByName[finding.subjectName.toLowerCase()];
    if (exercise == null) continue;
    for (final day in workoutDays) {
      if (day.muscleGroups.contains(exercise.muscleGroup)) {
        (findingsByDay[day.id] ??= []).add(finding);
      }
    }
  }
  for (final day in workoutDays) {
    final dayFindings = findingsByDay[day.id];
    if (dayFindings == null) continue;
    final dayFinding = dayAnalyzer.analyze(
      day: day,
      exerciseFindings: dayFindings,
    );
    if (dayFinding != null && notDismissed(dayFinding)) {
      findings.add(dayFinding);
    }
  }

  findings.sort((a, b) => b.priority.compareTo(a.priority));
  return findings;
});

/// Analysis scoped to exactly the exercises in [exerciseNames] (used right
/// after logging a workout). [day] additionally runs the day-level
/// escalation ([WorkoutDayAnalyzer]) scoped to just these exercises' findings
/// — pass the [WorkoutDayDef] the visit was logged under, if known.
List<AnalysisFinding> analyzeExercises({
  required List<MetaRow> visits,
  required List<Exercise> exercises,
  required List<String> exerciseNames,
  List<BodyWeightEntry> bodyWeightEntries = const [],
  AppSettingsService? settings,
  WorkoutDayDef? day,
}) {
  if (exercises.isEmpty) return const [];
  final exercisesByName = _exercisesByNameLower(exercises);
  final altMap = AlternativeExerciseMap(_exercisesByMuscleGroup(exercises));
  final lastLoggedDates = _lastLoggedDatesByExerciseName(visits);
  final bwTrend = bodyWeightTrend(bodyWeightEntries);
  final recentSuggestions = settings?.recentSuggestions ?? const [];

  final findings = <AnalysisFinding>[];
  for (final name in exerciseNames) {
    final exercise = exercisesByName[name.toLowerCase()];
    if (exercise == null) continue;
    final history = buildExerciseHistory(visits: visits, exerciseName: name);
    final recent = _recentSuggestionsFor(name, recentSuggestions);
    final finding = _engine.analyze(
      subjectName: name,
      history: history,
      alternativeExercises: altMap.alternativesFor(
        exercise,
        lastLoggedDate: lastLoggedDates,
      ),
      recentlySuggestedAlternatives: recent.alternatives,
      recentlySuggestedKinds: recent.kinds,
      bodyWeightTrend: bwTrend,
      unit: exercise.unit,
      customUnitLabel: exercise.customUnitLabel,
    );
    if (finding != null) findings.add(finding);
  }

  if (day != null) {
    const dayAnalyzer = WorkoutDayAnalyzer();
    final dayFinding = dayAnalyzer.analyze(day: day, exerciseFindings: findings);
    if (dayFinding != null) findings.add(dayFinding);
  }

  return findings;
}
