import '../../models/exercise.dart';
import '../../models/rating_relevance.dart';
import '../../models/set_feedback.dart';
import '../../models/workout_visit.dart';
import '../../models/year_sheet_data.dart';

/// Row for `workout_visits`, excluding `id` (autoincrement).
Map<String, Object?> workoutVisitRow(
  WorkoutVisit visit, {
  bool isSynthetic = false,
  bool exactDateKnown = true,
  int? sheetMetaRowIndex,
  bool needsSheetPush = false,
}) => {
  'visit_id': visit.visitId,
  'date': visit.date.toIso8601String(),
  'iso_week': visit.isoWeek,
  'iso_year': visit.isoYear,
  'rating': visit.rating,
  'rating_relevance': visit.ratingRelevance.name,
  'note': visit.note,
  'workout_day_id': visit.workoutDayId,
  'is_synthetic': isSynthetic ? 1 : 0,
  'exact_date_known': exactDateKnown ? 1 : 0,
  'source_tab': visit.sourceTab,
  'sheet_meta_row_index': sheetMetaRowIndex,
  'needs_sheet_push': needsSheetPush ? 1 : 0,
};

/// Row for `exercise_entries`, excluding `id`.
Map<String, Object?> exerciseEntryRow({
  required ExerciseEntry entry,
  required int localVisitId,
  required int position,
}) => {
  'visit_id': localVisitId,
  'exercise_name': entry.exercise.name,
  'position': position,
  'target_rep_range_low': entry.targetRepRangeLow,
  'target_rep_range_high': entry.targetRepRangeHigh,
};

/// Row for `exercise_sets`, excluding `id`.
Map<String, Object?> exerciseSetRow({
  required SetEntry set,
  required int entryId,
  required int setIndex,
  int? targetLow,
  int? targetHigh,
  double? targetWeight,
}) => {
  'entry_id': entryId,
  'set_index': setIndex,
  'weight': set.weight,
  'reps': set.reps,
  'approx_reps': set.approxReps ? 1 : 0,
  'feedback': set.feedback.name,
  'target_low': targetLow,
  'target_high': targetHigh,
  'target_weight': targetWeight,
};

/// Reconstructs one [LoggedExerciseRepRange] from an `exercise_entries` row
/// plus its ordered `exercise_sets` rows.
LoggedExerciseRepRange loggedExerciseRepRangeFromRows({
  required Map<String, Object?> entryRow,
  required List<Map<String, Object?>> setRows,
}) {
  final actualReps = <int>[];
  final approxReps = <bool>[];
  final actualWeights = <double>[];
  final setFeedback = <SetFeedback>[];
  final targetLowPerSet = <int?>[];
  final targetHighPerSet = <int?>[];
  final targetWeightPerSet = <double?>[];

  for (final row in setRows) {
    actualReps.add(row['reps'] as int);
    approxReps.add((row['approx_reps'] as int) == 1);
    actualWeights.add((row['weight'] as num).toDouble());
    setFeedback.add(SetFeedback.values.byName(row['feedback'] as String));
    targetLowPerSet.add(row['target_low'] as int?);
    targetHighPerSet.add(row['target_high'] as int?);
    targetWeightPerSet.add((row['target_weight'] as num?)?.toDouble());
  }

  return LoggedExerciseRepRange(
    exerciseName: entryRow['exercise_name'] as String,
    repRangeLow: entryRow['target_rep_range_low'] as int,
    repRangeHigh: entryRow['target_rep_range_high'] as int,
    actualReps: actualReps,
    approxReps: approxReps,
    actualWeights: actualWeights,
    setFeedback: setFeedback,
    targetLowPerSet: targetLowPerSet,
    targetHighPerSet: targetHighPerSet,
    targetWeightPerSet: targetWeightPerSet,
  );
}

/// Converts a freshly-edited [ExerciseEntry] into the [LoggedExerciseRepRange]
/// shape the sheet-push path expects — the in-memory-UI-state counterpart to
/// [loggedExerciseRepRangeFromRows], which instead reconstructs one from
/// already-stored DB rows.
LoggedExerciseRepRange loggedExerciseRepRangeFromEntry(ExerciseEntry entry) =>
    LoggedExerciseRepRange(
      exerciseName: entry.exercise.name,
      repRangeLow: entry.targetRepRangeLow,
      repRangeHigh: entry.targetRepRangeHigh,
      actualReps: entry.sets.map((s) => s.reps).toList(),
      approxReps: entry.sets.map((s) => s.approxReps).toList(),
      actualWeights: entry.sets.map((s) => s.weight).toList(),
      setFeedback: entry.sets.map((s) => s.feedback).toList(),
      targetLowPerSet: entry.targetRepRangeLowPerSet,
      targetHighPerSet: entry.targetRepRangeHighPerSet,
      targetWeightPerSet: entry.targetWeightPerSet,
    );

/// Reconstructs one [ExerciseEntry] from an `exercise_entries` row plus its
/// ordered `exercise_sets` rows, resolving the entry's [Exercise] via
/// [exercise] rather than carrying only the bare name — the full-model
/// counterpart to [loggedExerciseRepRangeFromRows], used wherever a replay
/// or reconciliation step needs a real [WorkoutVisit] rather than the
/// analysis layer's flattened [LoggedExerciseRepRange] view.
ExerciseEntry exerciseEntryFromRows({
  required Map<String, Object?> entryRow,
  required List<Map<String, Object?>> setRows,
  required Exercise exercise,
}) {
  final sets = <SetEntry>[];
  final targetLowPerSet = <int?>[];
  final targetHighPerSet = <int?>[];
  final targetWeightPerSet = <double?>[];

  for (final row in setRows) {
    sets.add(
      SetEntry(
        weight: (row['weight'] as num).toDouble(),
        reps: row['reps'] as int,
        approxReps: (row['approx_reps'] as int) == 1,
        feedback: SetFeedback.values.byName(row['feedback'] as String),
      ),
    );
    targetLowPerSet.add(row['target_low'] as int?);
    targetHighPerSet.add(row['target_high'] as int?);
    targetWeightPerSet.add((row['target_weight'] as num?)?.toDouble());
  }

  return ExerciseEntry(
    exercise: exercise,
    sets: sets,
    targetRepRangeLow: entryRow['target_rep_range_low'] as int,
    targetRepRangeHigh: entryRow['target_rep_range_high'] as int,
    targetRepRangeLowPerSet: targetLowPerSet,
    targetRepRangeHighPerSet: targetHighPerSet,
    targetWeightPerSet: targetWeightPerSet,
  );
}

/// Reconstructs a full [WorkoutVisit] from a `workout_visits` row and its
/// already-built [ExerciseEntry]s (see [exerciseEntryFromRows]) — used by
/// `WorkoutDao.getVisitByVisitId` to re-read the current row at sheet-push
/// replay time instead of replaying a stale captured snapshot.
WorkoutVisit workoutVisitFromRow({
  required Map<String, Object?> visitRow,
  required List<ExerciseEntry> entries,
}) => WorkoutVisit(
  visitId: visitRow['visit_id'] as String,
  date: DateTime.parse(visitRow['date'] as String),
  isoWeek: visitRow['iso_week'] as int,
  isoYear: visitRow['iso_year'] as int,
  entries: entries,
  rating: (visitRow['rating'] as num?)?.toDouble(),
  ratingRelevance: RatingRelevance.values.byName(
    visitRow['rating_relevance'] as String,
  ),
  sourceTab: visitRow['source_tab'] as String?,
  note: visitRow['note'] as String?,
  workoutDayId: visitRow['workout_day_id'] as String?,
);

/// Assembles a [MetaRow] from a `workout_visits` row, its already-built
/// [LoggedExerciseRepRange]s (see [loggedExerciseRepRangeFromRows]), and the
/// deduplicated muscle-group `sheetHeader` strings for the visit (see
/// `WorkoutDao._muscleGroupHeadersForEntries` — derived from each entry's
/// resolved [Exercise.muscleGroup], replicating `sheet_writer.dart`'s
/// `buildMetaAppendRow` formula).
MetaRow metaRowFromVisitRow({
  required Map<String, Object?> visitRow,
  required List<LoggedExerciseRepRange> exercises,
  required List<String> muscleGroupSheetHeaders,
}) => MetaRow(
  rowIndex: visitRow['sheet_meta_row_index'] as int? ?? -1,
  visitId: visitRow['visit_id'] as String,
  date: DateTime.parse(visitRow['date'] as String),
  isoWeek: visitRow['iso_week'] as int,
  isoYear: visitRow['iso_year'] as int,
  muscleGroups: muscleGroupSheetHeaders,
  exercises: exercises,
  sourceTab: visitRow['source_tab'] as String? ?? '',
  rating: (visitRow['rating'] as num?)?.toDouble(),
  ratingRelevance: RatingRelevance.values.byName(
    visitRow['rating_relevance'] as String,
  ),
  note: visitRow['note'] as String?,
  workoutDayId: visitRow['workout_day_id'] as String?,
  isSynthetic: (visitRow['is_synthetic'] as int? ?? 0) == 1,
  exactDateKnown: (visitRow['exact_date_known'] as int? ?? 1) == 1,
);
