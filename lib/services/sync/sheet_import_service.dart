import '../../core/constants/muscle_groups.dart';
import '../../core/constants/sheet_layout.dart';
import '../../core/utils/iso_week.dart';
import '../../models/exercise.dart';
import '../../models/exercise_muscle_info.dart';
import '../../models/workout_day_def.dart';
import '../../models/workout_visit.dart';
import '../../models/year_sheet_data.dart';
import '../db/body_weight_dao.dart';
import '../db/exercise_dao.dart';
import '../db/exercise_note_dao.dart';
import '../db/workout_dao.dart';
import '../db/workout_day_dao.dart';
import '../sheets/sheets_repository.dart';

/// One-time (idempotent) pass that reconciles a freshly-loaded
/// [SpreadsheetSnapshot] into the local database — "sheet wins" on any
/// conflict, nothing present only locally is ever deleted just because the
/// sheet doesn't mention it. Run on first sheet connection, a manual "Sync
/// now", and the v3.0.0 upgrade migration.
///
/// Also materializes the old per-render "synthetic visit" reconstruction
/// (hand-typed matrix cells with no metadata row) into real, idempotent
/// local `workout_visits` rows (`is_synthetic = 1`) — see
/// [_importCurrentGroupedSynthetic]/[_importLegacySynthetic], ported
/// verbatim from the old `buildHistoryEntries` — so the analysis layer can
/// read everything straight from the local DB with no per-render matrix
/// parsing left.
class SheetImportService {
  SheetImportService({
    required this.exerciseDao,
    required this.workoutDayDao,
    required this.workoutDao,
    required this.bodyWeightDao,
    required this.exerciseNoteDao,
  });

  final ExerciseDao exerciseDao;
  final WorkoutDayDao workoutDayDao;
  final WorkoutDao workoutDao;
  final BodyWeightDao bodyWeightDao;
  final ExerciseNoteDao exerciseNoteDao;

  Future<void> importAndReconcile(SpreadsheetSnapshot snapshot) async {
    final exerciseByNameLower = await _importExercises(snapshot);
    final workoutDays = mergeDuplicateWorkoutDays(snapshot.workoutDayDefs);
    await workoutDayDao.upsertAll(workoutDays);
    await _importVisits(snapshot, exerciseByNameLower, workoutDays);
    await _importBodyWeight(snapshot);
    await _importNotes(snapshot);
  }

  /// Upserts every exercise from every loaded year, ascending — a later
  /// year's definition overwrites an earlier year's for the same name,
  /// matching this codebase's existing "later wins" convention. Also folds
  /// in the "Exercises" reference tab's fallback muscle tag
  /// ([SpreadsheetSnapshot.exerciseMuscleInfo]) for any exercise that's
  /// legacy-tagged or has no known muscle — the same fallback
  /// `resolveMuscleGroup` (`exercise_muscle_resolution.dart`) applies live,
  /// but done once here at import time, so every persisted
  /// `Exercise.muscleGroup`/`muscleGroupKnown` is already maximally
  /// resolved and nothing downstream needs to consult that tab again. A
  /// sheet-only name (never logged, only present on the Exercises tab)
  /// inserts fresh rather than being dropped.
  Future<Map<String, Exercise>> _importExercises(
    SpreadsheetSnapshot snapshot,
  ) async {
    final byNameLower = <String, Exercise>{};
    final years = snapshot.yearData.values.toList()
      ..sort((a, b) => a.year.compareTo(b.year));
    for (final year in years) {
      for (final exercise in year.allExercises) {
        byNameLower[exercise.name.toLowerCase()] = exercise;
      }
    }

    final muscleInfoByNameLower = <String, ExerciseMuscleInfo>{
      for (final info in snapshot.exerciseMuscleInfo)
        info.exerciseName.toLowerCase(): info,
    };
    for (final entry in muscleInfoByNameLower.entries) {
      byNameLower.putIfAbsent(
        entry.key,
        () => Exercise(
          name: entry.value.exerciseName,
          muscleGroup: entry.value.muscleGroup,
        ),
      );
    }

    final resolved = <String, Exercise>{};
    for (final entry in byNameLower.entries) {
      final exercise = entry.value;
      final info = muscleInfoByNameLower[entry.key];
      resolved[entry.key] =
          (exercise.muscleGroupKnown && !exercise.muscleGroup.legacy) ||
              info == null
          ? exercise
          : Exercise(
              name: exercise.name,
              muscleGroup: info.muscleGroup,
              sheetRow: exercise.sheetRow,
              muscleGroupKnown: true,
              unit: exercise.unit,
              customUnitLabel: exercise.customUnitLabel,
              secondaryMuscleGroups: exercise.secondaryMuscleGroups,
            );
    }

    for (final exercise in resolved.values) {
      await exerciseDao.upsert(exercise);
    }
    return resolved;
  }

  Future<void> _importVisits(
    SpreadsheetSnapshot snapshot,
    Map<String, Exercise> exerciseByNameLower,
    List<WorkoutDayDef> workoutDays,
  ) async {
    final years = snapshot.yearData.values.toList()
      ..sort((a, b) => a.year.compareTo(b.year));

    for (final year in years) {
      for (final meta in year.metaRows) {
        final visit = await _visitFromMetaRow(year, meta, exerciseByNameLower);
        await workoutDao.replaceVisit(
          visit,
          needsSheetPush: false,
          exactDateKnown: true,
          sheetMetaRowIndex: meta.rowIndex,
        );
      }

      if (year.format == MatrixTabFormat.currentGrouped) {
        await _importCurrentGroupedSynthetic(year, workoutDays);
      } else {
        await _importLegacySynthetic(year);
      }
    }
  }

  /// Resolves [range]'s exercise against [byNameLower], persisting a
  /// placeholder (same "unknown, pick the first current muscle" convention
  /// `sheet_parser.dart`'s flatV2 fallback already uses) if nothing matches
  /// — so every logged exercise name ends up with a real local `exercises`
  /// row, never silently dropped.
  Future<Exercise> _resolveExercise(
    String name,
    Map<String, Exercise> byNameLower,
  ) async {
    final existing = byNameLower[name.toLowerCase()];
    if (existing != null) return existing;
    final placeholder = Exercise(
      name: name,
      muscleGroup: kCurrentMuscleGroups.first,
      muscleGroupKnown: false,
    );
    byNameLower[name.toLowerCase()] = placeholder;
    await exerciseDao.upsert(placeholder);
    return placeholder;
  }

  Future<WorkoutVisit> _visitFromMetaRow(
    YearSheetData year,
    MetaRow meta,
    Map<String, Exercise> exerciseByNameLower,
  ) async {
    final entries = <ExerciseEntry>[];
    for (final range in meta.exercises) {
      final exercise = await _resolveExercise(
        range.exerciseName,
        exerciseByNameLower,
      );
      final fallbackWeight = _matrixFallbackWeight(
        year,
        range.exerciseName,
        meta.isoWeek,
      );
      entries.add(
        ExerciseEntry(
          exercise: exercise,
          sets: _setsForRange(range, fallbackWeight),
          targetRepRangeLow: range.repRangeLow,
          targetRepRangeHigh: range.repRangeHigh,
          targetRepRangeLowPerSet: range.targetLowPerSet,
          targetRepRangeHighPerSet: range.targetHighPerSet,
          targetWeightPerSet: range.targetWeightPerSet,
        ),
      );
    }
    return WorkoutVisit(
      visitId: meta.visitId,
      date: meta.date,
      isoWeek: meta.isoWeek,
      isoYear: meta.isoYear,
      entries: entries,
      rating: meta.rating,
      ratingRelevance: meta.ratingRelevance,
      sourceTab: meta.sourceTab,
      note: meta.note,
      workoutDayId: meta.workoutDayId,
    );
  }

  double? _matrixFallbackWeight(
    YearSheetData year,
    String exerciseName,
    int isoWeek,
  ) {
    final sheetRow = year.findExercise(exerciseName)?.sheetRow;
    final col = year.weekColumns[isoWeek];
    if (sheetRow == null || col == null) return null;
    return year.cellValues[CellKey(sheetRow, col)];
  }

  List<SetEntry> _setsForRange(
    LoggedExerciseRepRange range,
    double? fallbackWeight,
  ) {
    if (range.actualReps.isNotEmpty) {
      return [
        for (var i = 0; i < range.actualReps.length; i++)
          SetEntry(
            weight: i < range.actualWeights.length
                ? range.actualWeights[i]
                : (fallbackWeight ?? 0),
            reps: range.actualReps[i],
            approxReps: range.isApprox(i),
            feedback: range.feedbackFor(i),
          ),
      ];
    }
    final weight = range.actualWeights.isNotEmpty
        ? range.actualWeights.first
        : fallbackWeight;
    if (weight == null) return const [];
    return [SetEntry(weight: weight, reps: range.repRangeLow)];
  }

  ExerciseEntry _syntheticEntry(Exercise exercise, double weight) =>
      ExerciseEntry(
        exercise: exercise,
        sets: [SetEntry(weight: weight, reps: kDefaultRepRangeLow)],
        targetRepRangeLow: kDefaultRepRangeLow,
        targetRepRangeHigh: kDefaultRepRangeHigh,
      );

  /// Ported from the old `buildHistoryEntries` (per-workout-day
  /// reconstruction for `currentGrouped` years) — see that function's
  /// comments in `analysis_providers.dart` (as of v2.5.0) for the full
  /// rationale behind claimed-groups/claimed-rows subset exclusion and the
  /// rank-based weekday offset. Materializes each reconstructed day/week as
  /// a real, idempotent local visit instead of a per-render value.
  Future<void> _importCurrentGroupedSynthetic(
    YearSheetData year,
    List<WorkoutDayDef> workoutDays,
  ) async {
    final weeksWithRealVisit = <int>{
      for (final visit in year.metaRows) visit.isoWeek,
    };

    final orderedIndices = List<int>.generate(workoutDays.length, (i) => i)
      ..sort((a, b) {
        final byCount = workoutDays[a].muscleGroups.length.compareTo(
          workoutDays[b].muscleGroups.length,
        );
        return byCount != 0 ? byCount : a.compareTo(b);
      });

    for (final week in year.weekColumns.keys) {
      final col = year.weekColumns[week]!;
      if (weeksWithRealVisit.contains(week)) continue;

      final claimedGroups = <Set<MuscleGroup>>[];
      final claimedRows = <Set<int>>[];

      for (var rank = 0; rank < orderedIndices.length; rank++) {
        final day = workoutDays[orderedIndices[rank]];

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
        if (exercisesThisDay.isEmpty) continue;

        claimedGroups.add(dayGroups);
        claimedRows.add({for (final e in exercisesThisDay) e.sheetRow!});

        final offsetDays = rank > 6 ? 6 : rank;
        final date = approximateDateForIsoWeek(
          year.year,
          week,
        ).add(Duration(days: offsetDays));
        final visitId = 'synthetic_${year.year}_w${week}_${day.id}';

        final entries = [
          for (final e in exercisesThisDay)
            _syntheticEntry(e, year.cellValues[CellKey(e.sheetRow!, col)]!),
        ];

        await workoutDao.replaceVisit(
          WorkoutVisit(
            visitId: visitId,
            date: date,
            isoWeek: week,
            isoYear: year.year,
            entries: entries,
            sourceTab: year.tabName,
            workoutDayId: day.id,
          ),
          needsSheetPush: false,
          isSynthetic: true,
          exactDateKnown: false,
        );
      }
    }
  }

  /// Ported from the old `buildHistoryEntries` (per-`WorkoutDay`
  /// reconstruction for legacy-format years).
  Future<void> _importLegacySynthetic(YearSheetData year) async {
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

        final date = approximateDateForWorkoutDay(year.year, week, day);
        final visitId = 'synthetic_${year.year}_w${week}_${day.name}';
        final entries = [
          for (final e in exercisesThisDay)
            _syntheticEntry(e, year.cellValues[CellKey(e.sheetRow!, col)]!),
        ];

        await workoutDao.replaceVisit(
          WorkoutVisit(
            visitId: visitId,
            date: date,
            isoWeek: week,
            isoYear: year.year,
            entries: entries,
            sourceTab: year.tabName,
          ),
          needsSheetPush: false,
          isSynthetic: true,
          exactDateKnown: false,
        );
      }
    }
  }

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
      _workoutDayForGroupLabels(visit.muscleGroups);

  WorkoutDay? _workoutDayForGroupLabels(List<String> labels) {
    for (final label in labels) {
      final group = muscleGroupFromSheetHeader(label);
      if (group == null) continue;
      final day = workoutDayForMuscleGroup(group);
      if (day != null) return day;
    }
    return null;
  }

  Future<void> _importBodyWeight(SpreadsheetSnapshot snapshot) async {
    for (final entry in snapshot.bodyWeightEntries) {
      await bodyWeightDao.upsert(entry);
    }
  }

  Future<void> _importNotes(SpreadsheetSnapshot snapshot) async {
    for (final note in snapshot.notes) {
      try {
        await exerciseNoteDao.upsert(note);
      } on StateError {
        // Referenced visit doesn't exist locally (e.g. a note left behind
        // for a visit that was later deleted directly in the sheet) — skip
        // it rather than failing the whole import.
      }
    }
  }
}
