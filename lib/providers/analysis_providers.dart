import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/muscle_groups.dart';
import '../core/constants/sheet_layout.dart';
import '../core/utils/iso_week.dart';
import '../models/analysis_result.dart';
import '../models/body_weight_entry.dart';
import '../models/exercise.dart';
import '../models/exercise_muscle_info.dart';
import '../models/history_entry.dart';
import '../models/rating_relevance.dart';
import '../models/set_feedback.dart';
import '../models/workout_day_def.dart';
import '../models/year_sheet_data.dart';
import '../services/analysis/alternative_exercise_map.dart';
import '../services/analysis/analysis_engine.dart';
import '../widgets/simple_line_chart.dart' show ChartPoint;
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
/// across the loaded years (oldest first).
List<HistoryPoint> buildExerciseHistory({
  required List<YearSheetData> yearsAscending,
  required String exerciseName,
}) {
  final points = <HistoryPoint>[];

  for (final yearData in yearsAscending) {
    final exercise = yearData.findExercise(exerciseName);
    if (exercise == null || exercise.sheetRow == null) continue;

    final weeksAscending = yearData.weekColumns.keys.toList()..sort();
    for (final week in weeksAscending) {
      final col = yearData.weekColumns[week]!;
      final weight = yearData.cellValues[CellKey(exercise.sheetRow!, col)];
      if (weight == null) continue;

      final matchingMetaRow = yearData.metaRows.where(
        (m) =>
            m.isoWeek == week &&
            m.exercises.any(
              (e) => e.exerciseName.toLowerCase() == exerciseName.toLowerCase(),
            ),
      );
      final meta = matchingMetaRow.isEmpty ? null : matchingMetaRow.first;
      final loggedRange = meta?.exercises.firstWhere(
        (e) => e.exerciseName.toLowerCase() == exerciseName.toLowerCase(),
      );

      points.add(
        HistoryPoint(
          isoYear: yearData.year,
          isoWeek: week,
          date: meta?.date ?? approximateDateForIsoWeek(yearData.year, week),
          avgWeight: weight,
          repRangeLow: loggedRange?.repRangeLow ?? kDefaultRepRangeLow,
          repRangeHigh: loggedRange?.repRangeHigh ?? kDefaultRepRangeHigh,
          rating: meta?.rating,
          ratingRelevance: meta?.ratingRelevance ?? RatingRelevance.normal,
          exactDateKnown: meta != null,
          totalSets: loggedRange?.setCount,
          avgReps: loggedRange?.avgReps,
          thumbsUpCount:
              loggedRange?.setFeedback
                  .where((f) => f == SetFeedback.up)
                  .length ??
              0,
          thumbsDownCount:
              loggedRange?.setFeedback
                  .where((f) => f == SetFeedback.down)
                  .length ??
              0,
        ),
      );
    }
  }

  return points;
}

/// Historical average number of sets actually performed for [exerciseName]
/// (e.g. "stairmaster usually 2 sets"), used as the default set count when
/// starting a new entry for it — rounded, clamped 1-10, over roughly the
/// last [lookback] logged instances that have per-set data on record. Null
/// when there's no such history yet (brand new exercise, or only legacy
/// rows with no per-set data), so the caller can fall back to a fixed
/// default.
int? historicalAverageSetCount({
  required List<YearSheetData> yearsAscending,
  required String exerciseName,
  int lookback = 10,
}) {
  final withSets = [
    for (final h in buildExerciseHistory(
      yearsAscending: yearsAscending,
      exerciseName: exerciseName,
    ))
      if (h.totalSets != null) h.totalSets!,
  ];
  if (withSets.isEmpty) return null;
  final recent = withSets.length > lookback
      ? withSets.sublist(withSets.length - lookback)
      : withSets;
  final avg = recent.reduce((a, b) => a + b) / recent.length;
  return avg.round().clamp(1, 10);
}

/// Combines every exercise tagged with [muscle] into one progress series, so
/// switching exercises for the same muscle (e.g. cable -> machine lateral
/// raises) still reads as one continuous story instead of an
/// apples-to-oranges jump in raw kg. An exercise's muscle tag comes primarily
/// from the year tabs' own data (reliable for both [MatrixTabFormat
/// .legacyGrouped] and [MatrixTabFormat.currentGrouped] tabs); the optional
/// legacy "Exercises" reference tab ([exerciseMuscleInfo]) is folded in only
/// as an extra source, so this keeps working with no hard dependency on that
/// tab existing at all.
///
/// Formula: each exercise is indexed to its own first logged session = 100
/// (so a value of 120 means "+20% over where you started on that specific
/// exercise"). A shared baseline across different exercises isn't used
/// on purpose — different equipment/leverage makes their absolute starting
/// weights incomparable, so indexing each to itself is what keeps the
/// combined line honest. When more than one exercise for the muscle has a
/// point in the same ISO week, their indexed values are averaged for that
/// week's point.
List<ChartPoint> buildMuscleProgressPoints({
  required List<YearSheetData> yearsAscending,
  required String muscle,
  required List<ExerciseMuscleInfo> exerciseMuscleInfo,
}) {
  final muscleLower = muscle.toLowerCase();
  final taggedNames = {
    for (final y in yearsAscending)
      for (final e in y.allExercises)
        if (e.muscleGroupKnown &&
            !e.muscleGroup.legacy &&
            e.muscleGroup.sheetHeader.toLowerCase() == muscleLower)
          e.name.toLowerCase(),
    for (final info in exerciseMuscleInfo)
      if (info.muscleGroup.sheetHeader.toLowerCase() == muscleLower)
        info.exerciseName.toLowerCase(),
  };
  final knownNames = <String>{
    for (final y in yearsAscending)
      for (final e in y.allExercises) e.name,
  };
  final matchingNames = knownNames.where(
    (n) => taggedNames.contains(n.toLowerCase()),
  );

  final indexedByWeek = <String, List<double>>{};
  final dateByWeek = <String, DateTime>{};
  final exercisesByWeek = <String, Set<String>>{};

  for (final name in matchingNames) {
    final history = buildExerciseHistory(
      yearsAscending: yearsAscending,
      exerciseName: name,
    );
    if (history.isEmpty) continue;
    final baseline = history.first.avgWeight;
    if (baseline == 0) continue;

    for (final h in history) {
      final key = '${h.isoYear}-${h.isoWeek}';
      indexedByWeek
          .putIfAbsent(key, () => [])
          .add(h.avgWeight / baseline * 100);
      dateByWeek.putIfAbsent(key, () => h.date);
      (exercisesByWeek[key] ??= {}).add(name);
    }
  }

  final points = [
    for (final key in indexedByWeek.keys)
      ChartPoint(
        date: dateByWeek[key]!,
        value:
            indexedByWeek[key]!.reduce((a, b) => a + b) /
            indexedByWeek[key]!.length,
        note: exercisesByWeek[key]!.join(', '),
      ),
  ]..sort((a, b) => a.date.compareTo(b.date));

  return points;
}

/// Best-guess specific date for a week/day that has no exact date on
/// record (data typed directly into the sheet before the app tracked
/// exact visit dates) — the user's actual historical schedule for
/// 2024-2026 wasn't logged day-by-day, so this assigns a fixed weekday
/// per workout day (Push -> Sunday, Pull -> Tuesday, Legs -> Thursday of
/// that ISO week) purely so legacy entries have *some* calendar date to
/// display. Visits logged through the app carry their own real date and
/// never go through this.
DateTime approximateDateForWorkoutDay(
  int isoYear,
  int isoWeek,
  WorkoutDay day,
) {
  final monday = approximateDateForIsoWeek(isoYear, isoWeek);
  final offsetFromMonday = switch (day) {
    WorkoutDay.push => 6, // Sunday (last day of the ISO week)
    WorkoutDay.pull => 1, // Tuesday
    WorkoutDay.legs => 3, // Thursday
  };
  return monday.add(Duration(days: offsetFromMonday));
}

/// Combines real app-logged visits with reconstructed entries for weeks
/// that have exercise weights typed directly into the sheet but no
/// corresponding metadata row (no exact date/rating available for those —
/// see [HistoryEntry.isSynthetic]). [workoutDays] (the user's current
/// sheet-backed workout days) drives reconstruction for `currentGrouped`
/// years — omit it and those years simply contribute no reconstructed
/// entries (legacy-format years are unaffected either way). Sorted
/// most-recent first.
List<HistoryEntry> buildHistoryEntries(
  List<YearSheetData> yearsAscending, {
  List<WorkoutDayDef> workoutDays = const [],
}) {
  final entries = <HistoryEntry>[];

  for (final year in yearsAscending) {
    for (final visit in year.metaRows) {
      entries.add(
        HistoryEntry(
          date: visit.date,
          isoWeek: visit.isoWeek,
          isoYear: visit.isoYear,
          exerciseNames: visit.exerciseNames,
          muscleGroups: visit.muscleGroups,
          metaRow: visit,
        ),
      );
    }

    if (year.format == MatrixTabFormat.currentGrouped) {
      // Once a week has a real, explicitly-tagged visit (workoutDayId set —
      // i.e. logged through the app after this field was added), that
      // visit is authoritative for the whole week: don't synthesize ANY
      // other day for it, even one that merely shares a muscle group with
      // it (e.g. abdominals trained under both Push and Legs) — otherwise a
      // shared exercise's matrix cell, written by the real visit, gets
      // mistaken for a second, un-logged day's own session. Weeks with no
      // explicitly-tagged visit (rows predating this field, or hand-typed
      // sheet data) fall back to the older muscle-set-match suppression
      // below, which still allows legitimate per-day reconstruction from
      // hand-typed data with no MetaRows at all.
      final weeksWithExplicitRealVisit = <int>{
        for (final visit in year.metaRows)
          if (visit.workoutDayId != null) visit.isoWeek,
      };

      // A (week, day) pair already has a real visit — don't also
      // synthesize it. A visit belongs to every current day whose declared
      // muscle set is a superset of what it actually trained (mirrors
      // ThisWeekSummary's own belongs-to-day matching).
      final loggedCurrentDayWeeks = <String>{
        for (final visit in year.metaRows)
          for (final day in workoutDays)
            if (_currentMuscleGroupsForVisit(visit).isNotEmpty &&
                _currentMuscleGroupsForVisit(
                  visit,
                ).every(day.muscleGroups.contains))
              '${visit.isoWeek}::${day.id}',
      };

      // Stable order: smallest declared muscle-group set first, ties broken
      // by original list position (List.sort isn't guaranteed stable).
      // Reused both to decide which day "claims" an exercise first when two
      // days' sets overlap, and to give each day a fixed, deterministic
      // weekday offset so multiple same-week synthetic entries don't all
      // collapse onto Monday.
      final orderedIndices = List<int>.generate(workoutDays.length, (i) => i)
        ..sort((a, b) {
          final byCount = workoutDays[a].muscleGroups.length.compareTo(
            workoutDays[b].muscleGroups.length,
          );
          return byCount != 0 ? byCount : a.compareTo(b);
        });

      for (final week in year.weekColumns.keys) {
        final col = year.weekColumns[week]!;
        if (weeksWithExplicitRealVisit.contains(week)) continue;

        // Per-week claim tracking: which muscle-group set + sheetRows each
        // already-emitted day this week used, so a broader day (e.g. the
        // seeded "Full Body", a superset of every other day) doesn't
        // re-include exercises a more specific day already accounted for.
        // Only excludes when one day's set fully contains another's — two
        // merely-overlapping peer sets (e.g. Push and Legs both including
        // Abdominals) are not subset-related, so nothing is excluded
        // between them and both keep showing the shared exercise, exactly
        // as before.
        final claimedGroups = <Set<MuscleGroup>>[];
        final claimedRows = <Set<int>>[];

        for (var rank = 0; rank < orderedIndices.length; rank++) {
          final day = workoutDays[orderedIndices[rank]];
          if (loggedCurrentDayWeeks.contains('$week::${day.id}')) continue;

          final rawExercisesThisDay = [
            for (final g in day.muscleGroups)
              for (final e in year.muscleGroupSections[g] ?? const <Exercise>[])
                if (e.sheetRow != null &&
                    year.cellValues[CellKey(e.sheetRow!, col)] != null)
                  e,
          ];
          if (rawExercisesThisDay.isEmpty) continue;

          final dayGroups = day.muscleGroups.toSet();
          final excludedRows = <int>{
            for (var i = 0; i < claimedGroups.length; i++)
              if (dayGroups.containsAll(claimedGroups[i])) ...claimedRows[i],
          };
          final exercisesThisDay = [
            for (final e in rawExercisesThisDay)
              if (!excludedRows.contains(e.sheetRow)) e,
          ];
          // Fully covered by a more specific day already processed this week.
          if (exercisesThisDay.isEmpty) continue;

          claimedGroups.add(dayGroups);
          claimedRows.add({for (final e in exercisesThisDay) e.sheetRow!});

          // No fixed weekday convention for an arbitrary custom day (unlike
          // legacy's hardcoded Push=Sunday/Pull=Tuesday/Legs=Thursday) — a
          // fixed rank-based offset from Monday keeps different days that
          // share a week from colliding on the same displayed date, while
          // staying deterministic and consistent with exactDateKnown: false.
          final offsetDays = rank > 6 ? 6 : rank;
          entries.add(
            HistoryEntry(
              date: approximateDateForIsoWeek(
                year.year,
                week,
              ).add(Duration(days: offsetDays)),
              isoWeek: week,
              isoYear: year.year,
              exerciseNames: [for (final e in exercisesThisDay) e.name],
              muscleGroups: {
                for (final e in exercisesThisDay) e.muscleGroup.sheetHeader,
              }.toList(),
              exactDateKnown: false,
            ),
          );
        }
      }
      continue;
    }

    // A (week, day) pair already has a real visit — don't also synthesize
    // it. Tracked per day (not just per week), so e.g. an app-logged Push
    // visit this week doesn't suppress reconstructing a hand-typed Legs
    // entry for the same week.
    final loggedDayWeeks = <String>{
      for (final visit in year.metaRows)
        if (_workoutDayForVisit(visit) != null)
          '${visit.isoWeek}::${_workoutDayForVisit(visit)}',
    };

    for (final week in year.weekColumns.keys) {
      final col = year.weekColumns[week]!;
      for (final day in WorkoutDay.values) {
        if (loggedDayWeeks.contains('$week::$day')) continue;

        final exercisesThisDay = _exercisesForDayInColumn(year, day, col);
        if (exercisesThisDay.isEmpty) continue;

        entries.add(
          HistoryEntry(
            date: approximateDateForWorkoutDay(year.year, week, day),
            isoWeek: week,
            isoYear: year.year,
            exerciseNames: [for (final e in exercisesThisDay) e.name],
            muscleGroups: {
              for (final e in exercisesThisDay) e.muscleGroup.sheetHeader,
            }.toList(),
            exactDateKnown: false,
          ),
        );
      }
    }
  }

  entries.sort((a, b) => b.date.compareTo(a.date));
  return entries;
}

/// Exercises belonging to [day]'s muscle groups that have a logged weight
/// in column [col] (a specific week) of [year].
List<Exercise> _exercisesForDayInColumn(
  YearSheetData year,
  WorkoutDay day,
  int col,
) {
  final groups = kMuscleGroupsByWorkoutDay[day]!;
  return [
    for (final g in groups)
      for (final e in year.muscleGroupSections[g] ?? const <Exercise>[])
        if (e.sheetRow != null &&
            year.cellValues[CellKey(e.sheetRow!, col)] != null)
          e,
  ];
}

WorkoutDay? _workoutDayForVisit(MetaRow visit) =>
    workoutDayForGroupLabels(visit.muscleGroups);

Set<MuscleGroup> _currentMuscleGroupsForVisit(MetaRow visit) => {
  for (final label in visit.muscleGroups)
    if (currentMuscleFromSheetHeader(label) case final g?) g,
};

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

/// Whether [entry] belongs to [day]. Two rules are tried and OR'd together:
///  - Legacy rule: [entry]'s labels resolve to the exact same legacy
///    [WorkoutDay] as [day.legacyDay] — matches pre-2026 history exactly as
///    before.
///  - Current rule: every muscle group [entry] trained (resolved via the
///    current taxonomy) is within [day]'s declared set (subset match) —
///    avoids e.g. a Push visit's incidental triceps work leaking into an
///    unrelated "Triceps only" custom day.
/// A fully custom day (no [WorkoutDayDef.legacyDay]) only ever uses the
/// current rule. A legacy-linked day (the seeded Push/Pull/Legs) uses both,
/// so a current-format (2026+) visit is recognized on its real current
/// muscle groups instead of only when it happens to include an exercise
/// whose current tag collides textually with a legacy header (e.g.
/// "biceps"/"triceps") — that incidental collision used to be the only
/// thing making some current-format visits "count" for these days.
bool historyEntryBelongsToDay(HistoryEntry entry, WorkoutDayDef day) {
  // An explicit tag (real visits logged after workoutDayId was added) is
  // authoritative — skip muscle-based inference entirely so a shared
  // muscle group can never misattribute a real visit to the wrong day.
  final explicitId = entry.metaRow?.workoutDayId;
  if (explicitId != null) return explicitId == day.id;

  final resolved = <MuscleGroup>{
    for (final label in entry.muscleGroups)
      if (currentMuscleFromSheetHeader(label) case final g?) g,
  };
  final currentMatch =
      resolved.isNotEmpty && resolved.every(day.muscleGroups.contains);

  if (day.legacyDay == null) return currentMatch;
  return workoutDayForGroupLabels(entry.muscleGroups) == day.legacyDay ||
      currentMatch;
}

/// The most recent real (app-logged, [HistoryEntry.metaRow]-backed) visit
/// belonging to [day] — skips synthetic/reconstructed entries (hand-typed
/// sheet data), which carry no per-set reps/weights/rating/note detail to
/// preview. Null if [day] has no real visit yet.
HistoryEntry? mostRecentRealVisitForDay(
  List<HistoryEntry> historyEntries,
  WorkoutDayDef day,
) {
  for (final entry in historyEntries) {
    if (entry.metaRow != null && historyEntryBelongsToDay(entry, day)) {
      return entry;
    }
  }
  return null;
}

/// Findings for every exercise trained in the last [AnalysisEngine
/// .proactiveScanWindowWeeks] weeks, most urgent first.
final proactiveFindingsProvider = Provider<List<AnalysisFinding>>((ref) {
  final snapshotState = ref.watch(snapshotProvider).value;
  if (snapshotState == null) return const [];
  final yearsAscending = snapshotState.snapshot.yearData.values.toList()
    ..sort((a, b) => a.year.compareTo(b.year));
  if (yearsAscending.isEmpty) return const [];

  final latestYear = yearsAscending.last;
  final cutoff = DateTime.now().subtract(
    Duration(days: 7 * AnalysisEngine.proactiveScanWindowWeeks),
  );

  // Uses the same reconciled real-visit + hand-typed-in-the-sheet data as
  // History/Home (buildHistoryEntries), not just real app-logged visits —
  // otherwise this only ever finds something "recent" for users who log
  // through the app's Log Workout screen, staying permanently empty for
  // anyone who (like most usage so far) types weights directly into the
  // sheet instead.
  final workoutDays = ref.watch(workoutDayDefsProvider);
  final recentExerciseNames = <String>{
    for (final entry in buildHistoryEntries(
      yearsAscending,
      workoutDays: workoutDays,
    ))
      if (entry.date.isAfter(cutoff)) ...entry.exerciseNames,
  };

  final altMap = AlternativeExerciseMap(latestYear);
  final dismissed = ref
      .watch(appSettingsServiceProvider)
      .dismissedFindingSignatures;
  final bwTrend = bodyWeightTrend(ref.watch(bodyWeightEntriesProvider));

  final findings = <AnalysisFinding>[];
  for (final name in recentExerciseNames) {
    final exercise = latestYear.findExercise(name);
    if (exercise == null) continue;
    final history = buildExerciseHistory(
      yearsAscending: yearsAscending,
      exerciseName: name,
    );
    final finding = _engine.analyze(
      subjectName: name,
      history: history,
      alternativeExerciseNames: altMap.alternativesFor(exercise),
      recentlySuggestedAlternatives: const {},
      bodyWeightTrend: bwTrend,
    );
    if (finding == null) continue;
    final signature = '$name::${finding.isPlateaued}';
    if (dismissed.contains(signature)) continue;
    findings.add(finding);
  }

  findings.sort((a, b) => b.priority.compareTo(a.priority));
  return findings;
});

/// Analysis scoped to exactly the exercises in [exerciseNames] (used right
/// after logging a workout).
List<AnalysisFinding> analyzeExercises({
  required List<YearSheetData> yearsAscending,
  required List<String> exerciseNames,
  List<BodyWeightEntry> bodyWeightEntries = const [],
}) {
  if (yearsAscending.isEmpty) return const [];
  final latestYear = yearsAscending.last;
  final altMap = AlternativeExerciseMap(latestYear);
  final bwTrend = bodyWeightTrend(bodyWeightEntries);

  final findings = <AnalysisFinding>[];
  for (final name in exerciseNames) {
    final exercise = latestYear.findExercise(name);
    if (exercise == null) continue;
    final history = buildExerciseHistory(
      yearsAscending: yearsAscending,
      exerciseName: name,
    );
    final finding = _engine.analyze(
      subjectName: name,
      history: history,
      alternativeExerciseNames: altMap.alternativesFor(exercise),
      recentlySuggestedAlternatives: const {},
      bodyWeightTrend: bwTrend,
    );
    if (finding != null) findings.add(finding);
  }
  return findings;
}
