import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/sheets/v4.dart';

import '../core/constants/muscle_groups.dart';
import '../core/constants/sheet_layout.dart';
import '../core/utils/iso_week.dart';
import '../core/utils/result.dart';
import '../models/body_weight_entry.dart';
import '../models/exercise.dart';
import '../models/exercise_muscle_info.dart';
import '../models/exercise_note.dart';
import '../models/exercise_unit.dart';
import '../models/rating_relevance.dart';
import '../models/workout_day_def.dart';
import '../models/workout_visit.dart';
import '../models/year_sheet_data.dart';
import '../services/db/workout_mappers.dart';
import '../services/sheets/sheet_writer.dart';
import '../services/sheets/sheets_repository.dart';
import '../services/sync/pending_sync_queue.dart';
import 'auth_providers.dart';
import 'db_providers.dart';
import 'local_history_providers.dart';
import 'settings_providers.dart';

final sheetsApiProvider = FutureProvider<SheetsApi>((ref) async {
  final auth = ref.watch(googleAuthServiceProvider);
  ref.watch(authStateProvider); // rebuild when sign-in state changes.
  return auth.buildSheetsApi();
});

final sheetsRepositoryProvider = FutureProvider<SheetsRepository>((ref) async {
  final api = await ref.watch(sheetsApiProvider.future);
  final spreadsheetId = ref.watch(spreadsheetIdProvider);
  if (spreadsheetId == null) {
    throw StateError('No spreadsheet configured yet.');
  }
  return SheetsRepository(api: api, spreadsheetId: spreadsheetId);
});

/// Outcome of a save attempt from the UI's point of view: either it made
/// it to the sheet, or it's safely queued locally to retry later.
enum SaveOutcome { synced, queuedOffline }

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class SnapshotState {
  const SnapshotState({required this.snapshot, this.pendingCount = 0});

  final SpreadsheetSnapshot snapshot;
  final int pendingCount;
}

class SnapshotNotifier extends AsyncNotifier<SnapshotState> {
  @override
  Future<SnapshotState> build() async {
    final repository = await ref.watch(sheetsRepositoryProvider.future);
    final queue = ref.watch(pendingSyncQueueProvider);

    // Load every year found in the spreadsheet so graphs show full history.
    final result = await repository.loadSnapshot();
    return result.when(
      ok: (snapshot) => SnapshotState(
        snapshot: snapshot,
        pendingCount: queue.getAll().length,
      ),
      err: (e, st) => Error.throwWithStackTrace(e, st ?? StackTrace.current),
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Applies a same-year [YearSheetData] edit directly to the snapshot
  /// already held in memory, without a network round trip. Google Sheets'
  /// read-after-write consistency isn't instant (confirmed live via adb
  /// logcat: a write can report success while the very next read still
  /// returns the pre-write value for a second or more), and every mutator
  /// here used to end with a full `refresh()` — a network re-fetch that,
  /// if it lands inside that window for *any* row recently written by this
  /// notifier (not just the one the current call is touching), silently
  /// reverts that other row's already-applied change in the UI. Since each
  /// mutator already knows exactly which fields it just wrote, patching
  /// them locally is both correct and race-free.
  void _patchYearData(int isoYear, YearSheetData Function(YearSheetData) edit) {
    final current = state.value;
    final yearData = current?.snapshot.yearData[isoYear];
    if (current == null || yearData == null) return;
    state = AsyncData(
      SnapshotState(
        snapshot: current.snapshot.copyWith(
          yearData: Map<int, YearSheetData>.from(current.snapshot.yearData)
            ..[isoYear] = edit(yearData),
        ),
        pendingCount: current.pendingCount,
      ),
    );
  }

  /// Same idea as [_patchYearData], for the sheet-backed `WorkoutDays` tab:
  /// patches `snapshot.workoutDayDefs` directly in memory instead of
  /// `refresh()`-ing, so an add/update/delete can never visibly flicker or
  /// revert due to Sheets' read-after-write consistency lag.
  void _patchWorkoutDayDefs(
    List<WorkoutDayDef> Function(List<WorkoutDayDef> current) edit,
  ) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      SnapshotState(
        snapshot: current.snapshot.copyWith(
          workoutDayDefs: edit(current.snapshot.workoutDayDefs),
        ),
        pendingCount: current.pendingCount,
      ),
    );
  }

  /// Logs a completed workout visit. Ensures the target year/overflow tab
  /// exists, writes the matrix + metadata rows, and returns the metadata
  /// row index (needed for the follow-up rating write) alongside whether
  /// it synced live or was queued for later.
  Future<(SaveOutcome, int?)> logVisit(WorkoutVisit visit) async {
    // Local DB is the source of truth — this always succeeds, regardless
    // of whether a sheet is connected or reachable.
    await ref.read(workoutDaoProvider).insertVisit(visit);
    ref.invalidate(localVisitsProvider);

    final queue = ref.read(pendingSyncQueueProvider);
    final current = state.value;
    if (current == null) {
      await queue.enqueueWorkoutVisit(visit.visitId);
      return (SaveOutcome.queuedOffline, null);
    }
    final repository = await ref.read(sheetsRepositoryProvider.future);

    final contextResult = await _resolveOrCreateYearContext(
      repository: repository,
      snapshot: current.snapshot,
      year: visit.isoYear,
      week: visit.isoWeek,
    );

    if (contextResult.isErr) {
      await queue.enqueueWorkoutVisit(visit.visitId);
      state = AsyncData(
        SnapshotState(
          snapshot: current.snapshot,
          pendingCount: queue.getAll().length,
        ),
      );
      return (SaveOutcome.queuedOffline, null);
    }

    final context = (contextResult as Ok<YearWriteContext>).value;
    final writeResult = await repository.writeVisit(
      yearData: context.yearData,
      sheetGridId: context.sheetGridId,
      visit: visit,
      metaTabName: context.metaTabName,
    );

    if (writeResult.isErr) {
      await queue.enqueueWorkoutVisit(visit.visitId);
      state = AsyncData(
        SnapshotState(
          snapshot: current.snapshot,
          pendingCount: queue.getAll().length,
        ),
      );
      return (SaveOutcome.queuedOffline, null);
    }

    // The note itself is already part of the appended meta row (column J,
    // see buildMetaAppendRow) — this only additionally mirrors it into a
    // header-row cell, matching how the user already reads notes by hand on
    // grouped-format tabs. legacyGrouped blends the note into the day's
    // primary section (e.g. the "Push" row, not "Chest"/"Shoulders");
    // currentGrouped writes it directly onto the specific muscle's own
    // header row, since there's no day-level super-section any more —
    // strictly more precise, a deliberate improvement over the legacy
    // convention. flatV2 has no header row to write into at all.
    final note = visit.note?.trim();
    if (note != null && note.isNotEmpty && visit.entries.isNotEmpty) {
      int? headerRow;
      if (context.yearData.format == MatrixTabFormat.legacyGrouped) {
        final day = workoutDayForMuscleGroup(
          visit.entries.first.exercise.muscleGroup,
        );
        headerRow = day == null
            ? null
            : context.yearData.primaryGroupHeaderRow[primaryGroupForDay(day)];
      } else if (context.yearData.format == MatrixTabFormat.currentGrouped) {
        headerRow = context
            .yearData
            .primaryGroupHeaderRow[visit.entries.first.exercise.muscleGroup];
      }
      if (headerRow != null) {
        // Best-effort: the visit itself already succeeded, so a note
        // failure shouldn't undo that or get separately queued.
        await repository.writeNote(
          matrixTabName: context.yearData.tabName,
          headerRow: headerRow,
          weekColumnIndex: context.yearData.weekColumns[visit.isoWeek]!,
          note: note,
        );
      }
    }

    await refresh();
    final metaRowIndex = (writeResult as Ok<int>).value;
    await ref
        .read(workoutDaoProvider)
        .markSheetPushed(visit.visitId, sheetMetaRowIndex: metaRowIndex);
    return (SaveOutcome.synced, metaRowIndex);
  }

  /// Replaces every per-exercise/per-set note for [visitId] with [notes] —
  /// called after a successful [logVisit] (fresh visit) or whenever an
  /// existing visit's notes are edited. Best-effort: the visit's core data
  /// (weights/reps/rating) is already saved by the time this runs, so a
  /// failure here doesn't undo that, matching how the visit-level note's
  /// header-row mirror is treated in [logVisit].
  Future<bool> saveNotesForVisit(String visitId, List<ExerciseNote> notes) async {
    // Local DB first — always succeeds, with no sheet dependency.
    final noteDao = ref.read(exerciseNoteDaoProvider);
    final existing = await noteDao.getForVisit(visitId);
    for (final n in existing) {
      final stillPresent = notes.any(
        (nn) => nn.exerciseName == n.exerciseName && nn.setIndex == n.setIndex,
      );
      if (!stillPresent) {
        await noteDao.deleteForVisitAndExercise(
          visitId,
          n.exerciseName,
          setIndex: n.setIndex,
        );
      }
    }
    for (final n in notes) {
      await noteDao.upsert(n);
    }
    ref.invalidate(localNotesProvider);

    final current = state.value;
    if (current == null) return true;
    try {
      final repository = await ref.read(sheetsRepositoryProvider.future);
      if (!current.snapshot.classifiedTabs.hasNotesTab && notes.isNotEmpty) {
        final ensured = await repository.ensureNotesTab();
        if (ensured.isErr) return true;
      }
      final staleRowIndexes = [
        for (final n in current.snapshot.notes)
          if (n.visitId == visitId && n.rowIndex != null) n.rowIndex!,
      ];
      if (staleRowIndexes.isNotEmpty || notes.isNotEmpty) {
        final result = await repository.replaceNotesForVisit(
          visitId: visitId,
          staleRowIndexes: staleRowIndexes,
          notesGridId: current.snapshot.gridIdsByTabName[kNotesTabName],
          newNotes: notes,
        );
        if (result.isOk) await refresh();
      }
    } catch (_) {
      // Best-effort sheet mirror — the local save above already succeeded.
    }
    return true;
  }

  /// Edits a previously logged visit's rating (and, optionally,
  /// rating-relevance). Keyed by the visit's stable [MetaRow.visitId] —
  /// never the sheet-only `rowIndex`, which is meaningless offline.
  Future<SaveOutcome> saveRating({
    required MetaRow metaRow,
    required double rating,
    RatingRelevance? ratingRelevance,
  }) async {
    await ref
        .read(workoutDaoProvider)
        .updateRatingFields(
          metaRow.visitId,
          rating: rating,
          ratingRelevance: ratingRelevance,
        );
    ref.invalidate(localVisitsProvider);

    final current = state.value;
    if (current == null) return SaveOutcome.queuedOffline;
    try {
      final repository = await ref.read(sheetsRepositoryProvider.future);
      final metaTabName =
          current.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
      if (metaTabName == null) return SaveOutcome.queuedOffline;

      final result = await repository.updateRating(
        metaTabName: metaTabName,
        metaRowIndex: metaRow.rowIndex,
        rating: rating,
      );
      if (result.isErr) return SaveOutcome.queuedOffline;
      if (ratingRelevance != null) {
        final relResult = await repository.updateRatingRelevance(
          metaTabName: metaTabName,
          metaRowIndex: metaRow.rowIndex,
          value: ratingRelevance,
        );
        if (relResult.isErr) return SaveOutcome.queuedOffline;
      }
      // See _patchYearData: no refresh() here, this only ever touches one
      // row's rating/ratingRelevance, so patch it in place instead of
      // racing a network reload against Sheets' read-after-write
      // consistency window.
      _patchYearData(
        metaRow.isoYear,
        (yearData) => yearData.copyWith(
          metaRows: [
            for (final m in yearData.metaRows)
              if (m.rowIndex == metaRow.rowIndex)
                m.copyWith(
                  rating: rating,
                  ratingRelevance: ratingRelevance ?? m.ratingRelevance,
                )
              else
                m,
          ],
        ),
      );
      await ref.read(workoutDaoProvider).markSheetPushed(metaRow.visitId);
    } catch (_) {
      // Best-effort sheet mirror — the local save above already succeeded.
    }
    return SaveOutcome.synced;
  }

  Future<SaveOutcome> addBodyWeight({
    required DateTime date,
    required double weightKg,
  }) async {
    // Local DB first — always succeeds, with no sheet dependency.
    await ref
        .read(bodyWeightDaoProvider)
        .upsert(BodyWeightEntry(date: date, weightKg: weightKg, rowIndex: -1));
    ref.invalidate(localBodyWeightProvider);

    final current = state.value;
    if (current == null) return SaveOutcome.queuedOffline;
    try {
      final repository = await ref.read(sheetsRepositoryProvider.future);
      if (!current.snapshot.classifiedTabs.hasBodyWeightTab) {
        final ensured = await repository.ensureBodyWeightTab();
        if (ensured.isErr) return SaveOutcome.queuedOffline;
      }
      final result = await repository.appendBodyWeight(
        date: date,
        weightKg: weightKg,
      );
      if (result.isErr) return SaveOutcome.queuedOffline;
      await refresh();
    } catch (_) {
      // Best-effort sheet mirror — the local save above already succeeded.
    }
    return SaveOutcome.synced;
  }

  /// Deletes a previously logged visit from the local DB (always succeeds),
  /// then best-effort mirrors the delete to the sheet if one is connected.
  Future<bool> deleteVisit(MetaRow metaRow) async {
    await ref.read(workoutDaoProvider).softDelete(metaRow.visitId);
    ref.invalidate(localVisitsProvider);

    final current = state.value;
    if (current == null) return true;
    try {
      final repository = await ref.read(sheetsRepositoryProvider.future);
      final yearData = current.snapshot.yearData[metaRow.isoYear];
      final metaTabName =
          current.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
      final weekColumn = yearData?.weekColumns[metaRow.isoWeek];
      final metaTabGridId = metaTabName == null
          ? null
          : current.snapshot.gridIdsByTabName[metaTabName];
      if (yearData == null ||
          metaTabName == null ||
          weekColumn == null ||
          metaTabGridId == null) {
        return true;
      }

      final rowsToClear = metaRow.exercises
          .map((e) => yearData.findExercise(e.exerciseName)?.sheetRow)
          .whereType<int>()
          .toList();

      final result = await repository.deleteVisit(
        matrixTabName: yearData.tabName,
        weekColumnIndex: weekColumn,
        exerciseRowsToClear: rowsToClear,
        metaTabName: metaTabName,
        metaTabGridId: metaTabGridId,
        metaRowIndex: metaRow.rowIndex,
      );
      if (result.isOk) await refresh();
    } catch (_) {
      // Best-effort sheet mirror — the local delete above already succeeded.
    }
    return true;
  }

  /// Edits the note for a previously logged visit — writes to the
  /// canonical per-visit note column (meta tab column J), and, for a
  /// legacyGrouped year, best-effort mirrors it into the header-row cell
  /// too (matching the older hand-reading convention on those tabs).
  Future<bool> saveVisitNote(MetaRow metaRow, String note) async {
    // Local DB first — always succeeds, with no sheet dependency.
    await ref.read(workoutDaoProvider).updateNote(metaRow.visitId, note);
    ref.invalidate(localVisitsProvider);

    final current = state.value;
    if (current == null) return true;
    try {
      final repository = await ref.read(sheetsRepositoryProvider.future);
      final metaTabName =
          current.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
      if (metaTabName == null) return true;

      final result = await repository.updateVisitNote(
        metaTabName: metaTabName,
        metaRowIndex: metaRow.rowIndex,
        note: note,
      );
      if (result.isErr) return true;

      final yearData = current.snapshot.yearData[metaRow.isoYear];
      if (yearData != null &&
          (yearData.format == MatrixTabFormat.legacyGrouped ||
              yearData.format == MatrixTabFormat.currentGrouped)) {
        int? headerRow;
        for (final label in metaRow.muscleGroups) {
          final group = sheetHeaderMuscleGroupForFormat(
            label,
            yearData.format,
          );
          if (group == null) continue;
          if (group.legacy) {
            final day = workoutDayForMuscleGroup(group);
            headerRow = day == null
                ? null
                : yearData.primaryGroupHeaderRow[primaryGroupForDay(day)];
          } else {
            headerRow = yearData.primaryGroupHeaderRow[group];
          }
          if (headerRow != null) break;
        }
        final weekColumn = yearData.weekColumns[metaRow.isoWeek];
        if (headerRow != null && weekColumn != null) {
          await repository.writeNote(
            matrixTabName: yearData.tabName,
            headerRow: headerRow,
            weekColumnIndex: weekColumn,
            note: note,
          );
        }
      }

      // See _patchYearData: no refresh() here, same race as saveRating —
      // this only ever touches one row's note, so patch it in place. The
      // legacyGrouped/currentGrouped header-row mirror write above is
      // best-effort and deliberately not reflected into weekNotes/
      // weekNotesByGroup in memory (it'll show correctly after the next
      // full refresh) — not worth replicating the parser's cross-header-row
      // merge logic for this legacy-format-only display detail.
      _patchYearData(
        metaRow.isoYear,
        (yd) => yd.copyWith(
          metaRows: [
            for (final m in yd.metaRows)
              if (m.rowIndex == metaRow.rowIndex)
                m.copyWith(note: note)
              else
                m,
          ],
        ),
      );
      await ref.read(workoutDaoProvider).markSheetPushed(metaRow.visitId);
    } catch (_) {
      // Best-effort sheet mirror — the local save above already succeeded.
    }
    return true;
  }

  /// Edits a previously logged visit's rating-relevance flag alone (rating
  /// itself unchanged) — used from Edit Visit when only the "feeling sick"
  /// state changes.
  Future<bool> saveRatingRelevance(
    MetaRow metaRow,
    RatingRelevance value,
  ) async {
    await ref
        .read(workoutDaoProvider)
        .updateRatingRelevance(metaRow.visitId, value);
    ref.invalidate(localVisitsProvider);

    final current = state.value;
    if (current == null) return true;
    try {
      final repository = await ref.read(sheetsRepositoryProvider.future);
      final metaTabName =
          current.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
      if (metaTabName == null) return true;

      final result = await repository.updateRatingRelevance(
        metaTabName: metaTabName,
        metaRowIndex: metaRow.rowIndex,
        value: value,
      );
      if (result.isOk) {
        await refresh();
        await ref.read(workoutDaoProvider).markSheetPushed(metaRow.visitId);
      }
    } catch (_) {
      // Best-effort sheet mirror — the local save above already succeeded.
    }
    return true;
  }

  /// Saves an edited visit's exercise entries (weights, reps, order,
  /// per-set target overrides) — local DB first, always succeeds, then a
  /// best-effort sheet mirror. Takes [ExerciseEntry]s (the edit screen's
  /// own live draft shape) rather than [LoggedExerciseRepRange] so the
  /// local write via [WorkoutDao.replaceEntries] gets the real edited set
  /// data, not just a reordering of names.
  Future<bool> updateVisitEntries(
    MetaRow metaRow,
    List<ExerciseEntry> entries,
  ) async {
    // Local DB first — always succeeds, with no sheet dependency.
    await ref.read(workoutDaoProvider).replaceEntries(metaRow.visitId, entries);
    ref.invalidate(localVisitsProvider);

    final newOrder = [
      for (final e in entries) loggedExerciseRepRangeFromEntry(e),
    ];

    final current = state.value;
    if (current == null) return true;
    try {
      final repository = await ref.read(sheetsRepositoryProvider.future);
      final metaTabName =
          current.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
      if (metaTabName == null) return true;

      final result = await repository.updateVisitExerciseOrder(
        metaTabName: metaTabName,
        metaRowIndex: metaRow.rowIndex,
        exercises: newOrder,
      );
      if (result.isErr) return true;
      // See _patchYearData: patch this row's exercises in place instead of
      // a network refresh(), for the same read-after-write race reason as
      // other patch-in-place mutators above.
      _patchYearData(
        metaRow.isoYear,
        (yearData) => yearData.copyWith(
          metaRows: [
            for (final m in yearData.metaRows)
              if (m.rowIndex == metaRow.rowIndex)
                m.copyWith(exercises: newOrder)
              else
                m,
          ],
        ),
      );
      await ref.read(workoutDaoProvider).markSheetPushed(metaRow.visitId);
    } catch (_) {
      // Best-effort sheet mirror — the local save above already succeeded.
    }
    return true;
  }

  /// Updates a logged body-weight entry, keyed by its (unique-per-day)
  /// [oldDate] rather than the sheet-only `rowIndex`, which is meaningless
  /// offline.
  Future<bool> updateBodyWeightEntry(
    DateTime oldDate, {
    required DateTime date,
    required double weightKg,
  }) async {
    final dao = ref.read(bodyWeightDaoProvider);
    if (!_isSameDay(oldDate, date)) {
      await dao.deleteByDate(oldDate);
    }
    await dao.upsert(BodyWeightEntry(date: date, weightKg: weightKg, rowIndex: -1));
    ref.invalidate(localBodyWeightProvider);

    final current = state.value;
    if (current == null) return true;
    try {
      final repository = await ref.read(sheetsRepositoryProvider.future);
      BodyWeightEntry? entry;
      for (final e in current.snapshot.bodyWeightEntries) {
        if (_isSameDay(e.date, oldDate)) {
          entry = e;
          break;
        }
      }
      if (entry == null || entry.rowIndex < 0) return true;
      final result = await repository.updateBodyWeightEntry(
        rowIndex: entry.rowIndex,
        date: date,
        weightKg: weightKg,
      );
      if (result.isOk) await refresh();
    } catch (_) {
      // Best-effort sheet mirror — the local save above already succeeded.
    }
    return true;
  }

  /// Deletes a logged body-weight entry, keyed by its date.
  Future<bool> deleteBodyWeightEntry(BodyWeightEntry entry) async {
    await ref.read(bodyWeightDaoProvider).deleteByDate(entry.date);
    ref.invalidate(localBodyWeightProvider);

    final current = state.value;
    if (current == null) return true;
    try {
      if (entry.rowIndex < 0) return true;
      final repository = await ref.read(sheetsRepositoryProvider.future);
      final gridId = current.snapshot.gridIdsByTabName[kBodyWeightTabName];
      if (gridId == null) return true;

      final result = await repository.deleteBodyWeightEntry(
        rowIndex: entry.rowIndex,
        bodyWeightGridId: gridId,
      );
      if (result.isOk) await refresh();
    } catch (_) {
      // Best-effort sheet mirror — the local delete above already succeeded.
    }
    return true;
  }

  /// Adds a brand-new exercise. Local DB first — always succeeds, with no
  /// sheet dependency (this is the direct fix for "adding an exercise and
  /// assigning its muscle group" previously requiring a live sheet). If a
  /// sheet is connected, best-effort mirrors the muscle + unit into the
  /// "Exercises" reference tab.
  Future<void> addExercise(Exercise exercise) async {
    await ref.read(exerciseDaoProvider).insert(exercise);
    ref.invalidate(localExercisesProvider);

    try {
      await _pushExerciseMuscle(
        exerciseName: exercise.name,
        muscleGroup: exercise.muscleGroup,
      );
      await _pushExerciseUnit(
        exerciseName: exercise.name,
        unit: exercise.unit,
        customLabel: exercise.customUnitLabel,
      );
    } catch (_) {
      // Best-effort sheet mirror — the local add above already succeeded.
    }
  }

  /// Persists a newly-added exercise's stated muscle back to the
  /// "Exercises" reference tab (appended to that muscle's existing
  /// column), so it sticks across app restarts and immediately affects
  /// muscle-based grouping/graphs.
  Future<bool> _pushExerciseMuscle({
    required String exerciseName,
    required MuscleGroup muscleGroup,
  }) async {
    final current = state.value;
    int? columnIndex;
    if (current != null) {
      for (final info in current.snapshot.exerciseMuscleInfo) {
        if (info.muscleGroup == muscleGroup) {
          columnIndex = info.columnIndex;
          break;
        }
      }
    }
    if (columnIndex == null) return true;

    final repository = await ref.read(sheetsRepositoryProvider.future);
    final queue = ref.read(pendingSyncQueueProvider);
    final result = await repository.appendExerciseToMuscleColumn(
      columnIndex: columnIndex,
      exerciseName: exerciseName,
    );
    if (result.isErr) {
      await queue.enqueueExerciseMuscle(
        exerciseName: exerciseName,
        columnIndex: columnIndex,
      );
      return false;
    }
    await refresh();
    return true;
  }

  /// Persists an exercise's unit to the "Exercises" tab's `Exercise`/`Unit`
  /// side-table — called whenever a new exercise is added with a non-kg
  /// unit, or an existing exercise's unit is edited from Settings. Every
  /// unit is written explicitly (`kg`, `bw`, `time`, `custom:<label>`),
  /// and any other known exercise that has no row yet is filled in as `kg`
  /// in the same write, so the sheet ends up holding a unit for each one.
  Future<bool> _pushExerciseUnit({
    required String exerciseName,
    required ExerciseUnit unit,
    String? customLabel,
  }) async {
    final current = state.value;
    final table = current?.snapshot.exerciseUnitsTable;
    final queue = ref.read(pendingSyncQueueProvider);
    if (current == null || table == null) {
      await queue.enqueueExerciseUnit(
        exerciseName: exerciseName,
        unit: unit,
        customLabel: customLabel,
      );
      return false;
    }

    final knownNames = <String>{
      for (final y in current.snapshot.yearData.values)
        for (final e in y.allExercises) e.name,
    }.toList();

    final repository = await ref.read(sheetsRepositoryProvider.future);

    if (!current.snapshot.classifiedTabs.hasExercisesTab) {
      final ensured = await repository.ensureExercisesTab();
      if (ensured.isErr) {
        ensured.when(
          ok: (_) {},
          err: (e, st) =>
              debugPrint('ensureExercisesTab failed for $exerciseName: $e\n$st'),
        );
        await queue.enqueueExerciseUnit(
          exerciseName: exerciseName,
          unit: unit,
          customLabel: customLabel,
        );
        return false;
      }
    }

    final result = await repository.setExerciseUnit(
      exerciseName: exerciseName,
      unit: unit,
      customLabel: customLabel,
      currentTable: table,
      backfillNames: knownNames,
    );
    if (result.isErr) {
      result.when(
        ok: (_) {},
        err: (e, st) => debugPrint('addExerciseUnit failed for $exerciseName: $e\n$st'),
      );
      await queue.enqueueExerciseUnit(
        exerciseName: exerciseName,
        unit: unit,
        customLabel: customLabel,
      );
      return false;
    }
    await refresh();
    return true;
  }

  /// One-time Settings action: fills in a missing unit and/or missing
  /// muscle-column entry in the "Exercises" reference tab for every exercise
  /// that's ever appeared in logged history, without touching anything
  /// that's already set. Units default to `kg` (matching [setExerciseUnit]'s
  /// existing backfill semantics); muscles are inferred from each exercise's
  /// own [Exercise.muscleGroup] (known from where it lives in the matrix
  /// tab), skipping any muscle group that has no known column yet (i.e. one
  /// with zero exercises currently listed in the reference tab).
  Future<({int unitsFilled, int musclesFilled})> backfillMissingExerciseInfo() async {
    final current = state.value;
    if (current == null) return (unitsFilled: 0, musclesFilled: 0);
    final repository = await ref.read(sheetsRepositoryProvider.future);

    final knownExercises = <String, Exercise>{};
    for (final y in current.snapshot.yearData.values) {
      for (final e in y.allExercises) {
        knownExercises[e.name.toLowerCase()] = e;
      }
    }

    var unitsFilled = 0;
    final table = current.snapshot.exerciseUnitsTable;
    final missingUnitNames = [
      for (final e in knownExercises.values)
        if (!table.assignments.containsKey(e.name.toLowerCase())) e.name,
    ];
    if (missingUnitNames.isNotEmpty) {
      final result = await repository.setExerciseUnit(
        exerciseName: missingUnitNames.first,
        unit: ExerciseUnit.kg,
        currentTable: table,
        backfillNames: missingUnitNames.skip(1).toList(),
      );
      if (result.isOk) unitsFilled = missingUnitNames.length;
    }

    var musclesFilled = 0;
    final knownMuscleNames = {
      for (final info in current.snapshot.exerciseMuscleInfo)
        info.exerciseName.toLowerCase(),
    };
    final columnByMuscle = <MuscleGroup, int>{};
    for (final info in current.snapshot.exerciseMuscleInfo) {
      columnByMuscle.putIfAbsent(info.muscleGroup, () => info.columnIndex);
    }
    for (final e in knownExercises.values) {
      if (knownMuscleNames.contains(e.name.toLowerCase())) continue;
      final columnIndex = columnByMuscle[e.muscleGroup];
      if (columnIndex == null) continue;
      final result = await repository.appendExerciseToMuscleColumn(
        columnIndex: columnIndex,
        exerciseName: e.name,
      );
      if (result.isOk) musclesFilled++;
    }

    if (unitsFilled > 0 || musclesFilled > 0) {
      await refresh();
    }
    return (unitsFilled: unitsFilled, musclesFilled: musclesFilled);
  }

  /// Result of [updateExercise]: overall success plus which sub-steps (if
  /// any) failed, so the caller's SnackBar can name exactly what didn't
  /// save.
  ///
  /// Renames/changes the muscle group/changes the unit of an exercise, and
  /// makes it stick for future logs (unlike [addExerciseUnit] alone). For a
  /// muscle change this actually relocates the exercise's row to the new
  /// muscle's section (grouped-format years) or column (flatV2 years).
  /// Scoped to the current year only, same as [deleteExercise] — past
  /// years' historical tabs are untouched (a rename's old rows simply keep
  /// their old name text). Runs whichever of the three sub-steps actually
  /// changed, keeps going even if one fails (so e.g. a working unit change
  /// isn't lost just because the muscle move failed), and always refreshes
  /// at the end so every `Exercise.sheetRow` is rebuilt fresh regardless of
  /// partial failure.
  Future<({bool success, List<String> failedSteps})> updateExercise({
    required Exercise oldExercise,
    required Exercise newExercise,
  }) async {
    final dao = ref.read(exerciseDaoProvider);
    if (oldExercise.name != newExercise.name) {
      await dao.rename(oldExercise.name, newExercise.name);
    }
    await dao.update(newExercise);
    ref.invalidate(localExercisesProvider);
    ref.invalidate(localVisitsProvider);

    final current = state.value;
    if (current == null) return (success: true, failedSteps: const <String>[]);

    final nameChanged = oldExercise.name != newExercise.name;
    final muscleChanged = oldExercise.muscleGroup != newExercise.muscleGroup;
    int? newMuscleColumnIndex;
    if (muscleChanged) {
      for (final info in current.snapshot.exerciseMuscleInfo) {
        if (info.muscleGroup == newExercise.muscleGroup) {
          newMuscleColumnIndex = info.columnIndex;
          break;
        }
      }
    }
    final unitChanged =
        oldExercise.unit != newExercise.unit ||
        oldExercise.customUnitLabel != newExercise.customUnitLabel;
    final secondaryMusclesChanged =
        oldExercise.secondaryMuscleGroups.toSet() !=
        newExercise.secondaryMuscleGroups.toSet();
    if (!nameChanged &&
        !muscleChanged &&
        !unitChanged &&
        !secondaryMusclesChanged) {
      return (success: true, failedSteps: const <String>[]);
    }

    final failedSteps = <String>[];
    final currentYear = isoWeekYear(DateTime.now());
    try {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final queue = ref.read(pendingSyncQueueProvider);
    final yearData = current.snapshot.yearData[currentYear];

    ExerciseMuscleInfo? muscleEntryFor(String name) {
      for (final info in current.snapshot.exerciseMuscleInfo) {
        if (info.exerciseName.toLowerCase() == name.toLowerCase()) {
          return info;
        }
      }
      return null;
    }

    if (nameChanged) {
      if (yearData != null && oldExercise.sheetRow != null) {
        final r = await repository.writeMatrixCell(
          matrixTabName: yearData.tabName,
          rowIndex: oldExercise.sheetRow!,
          columnIndex: 0,
          value: newExercise.name,
        );
        if (r.isErr) failedSteps.add("rename (this year's sheet)");
      }
      final r2 = await repository.renameExerciseInExercisesTab(
        oldName: oldExercise.name,
        newName: newExercise.name,
        currentTable: current.snapshot.exerciseUnitsTable,
        muscleColumnEntry: muscleEntryFor(oldExercise.name),
      );
      if (r2.isErr) failedSteps.add('rename (Exercises tab)');
    }

    if (muscleChanged && yearData != null) {
      var muscleOk = true;
      if (yearData.format == MatrixTabFormat.flatV2) {
        final oldEntry = muscleEntryFor(oldExercise.name);
        if (oldEntry != null && newMuscleColumnIndex != null) {
          final r = await repository.moveExerciseMuscleColumn(
            oldColumnIndex: oldEntry.columnIndex,
            oldRowIndex: oldEntry.rowIndex,
            newColumnIndex: newMuscleColumnIndex,
            exerciseName: newExercise.name,
          );
          muscleOk = r.isOk;
        } else if (newMuscleColumnIndex != null) {
          // The exercise has never been logged, so there's no existing
          // muscle-column entry to move — append a fresh one instead
          // (same fallback `addExerciseMuscle` uses for a brand-new
          // exercise), otherwise this silently no-ops.
          final r = await repository.appendExerciseToMuscleColumn(
            columnIndex: newMuscleColumnIndex,
            exerciseName: newExercise.name,
          );
          muscleOk = r.isOk;
        }
      } else if (oldExercise.sheetRow != null) {
        final gridId = current.snapshot.gridIdsByTabName[yearData.tabName];
        if (gridId != null) {
          final r = await repository.moveExerciseRowToMuscleSection(
            sheetGridId: gridId,
            yearData: yearData,
            currentRow: oldExercise.sheetRow!,
            newGroup: newExercise.muscleGroup,
          );
          muscleOk = r.isOk;
        }
      } else if (newMuscleColumnIndex != null) {
        // Never-logged exercise on a grouped-format year: no row to move,
        // so persist the muscle change to the Exercises reference tab
        // instead (same fallback as the flatV2 branch above).
        final r = await repository.appendExerciseToMuscleColumn(
          columnIndex: newMuscleColumnIndex,
          exerciseName: newExercise.name,
        );
        muscleOk = r.isOk;
      }
      if (!muscleOk) {
        failedSteps.add('muscle');
        if (newMuscleColumnIndex != null) {
          await queue.enqueueExerciseMuscle(
            exerciseName: newExercise.name,
            columnIndex: newMuscleColumnIndex,
          );
        }
      }
    }

    if (unitChanged) {
      var ok = true;
      if (!current.snapshot.classifiedTabs.hasExercisesTab) {
        final ensured = await repository.ensureExercisesTab();
        ok = ensured.isOk;
      }
      if (ok) {
        final r = await repository.setExerciseUnit(
          exerciseName: newExercise.name,
          unit: newExercise.unit,
          customLabel: newExercise.customUnitLabel,
          currentTable: current.snapshot.exerciseUnitsTable,
        );
        ok = r.isOk;
      }
      if (!ok) {
        await queue.enqueueExerciseUnit(
          exerciseName: newExercise.name,
          unit: newExercise.unit,
          customLabel: newExercise.customUnitLabel,
        );
        failedSteps.add('unit');
      }
    }

    if (secondaryMusclesChanged) {
      var ok = true;
      if (!current.snapshot.classifiedTabs.hasExercisesTab) {
        final ensured = await repository.ensureExercisesTab();
        ok = ensured.isOk;
      }
      if (ok) {
        final r = await repository.setExerciseUnit(
          exerciseName: newExercise.name,
          unit: newExercise.unit,
          customLabel: newExercise.customUnitLabel,
          secondaryMuscles: newExercise.secondaryMuscleGroups,
          currentTable: current.snapshot.exerciseUnitsTable,
        );
        ok = r.isOk;
      }
      if (!ok) {
        await queue.enqueueExerciseSecondaryMuscles(
          exerciseName: newExercise.name,
          secondaryMuscles: newExercise.secondaryMuscleGroups,
        );
        failedSteps.add('secondary muscles');
      }
    }

    await refresh();

    // A muscle-group change can insert/move whole rows (grouped tabs) or
    // move a column (flat tabs) — unlike the other mutators here, that's
    // too structurally involved to patch in memory, so this still refreshes
    // from network. But that refresh can land inside Sheets' read-after-
    // write consistency window and come back with the pre-move data,
    // which reads as "the edit reverted" (reported on web/PWA). Rather
    // than accept whatever the first refresh returns, verify the moved
    // exercise's muscle group actually came back changed and retry the
    // fetch briefly if not, instead of showing a known-stale result.
    if (muscleChanged && !failedSteps.contains('muscle')) {
      for (var attempt = 0; attempt < 3; attempt++) {
        final updated = state.value?.snapshot.yearData[currentYear]
            ?.findExercise(newExercise.name);
        if (updated != null && updated.muscleGroup == newExercise.muscleGroup) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        await refresh();
      }
    }
    } catch (_) {
      // Best-effort sheet mirror — the local update above already succeeded.
      failedSteps.add('sheet sync');
    }

    return (success: true, failedSteps: failedSteps);
  }

  /// Deletes an exercise: removes its row from the current year's matrix
  /// tab and clears (never row-deletes) its cells in the "Exercises" tab.
  /// Scope is deliberately current-year-only, same as [updateExercise] —
  /// past years keep their historical row.
  Future<bool> deleteExercise(Exercise exercise) async {
    await ref.read(exerciseDaoProvider).softDelete(exercise.name);
    ref.invalidate(localExercisesProvider);

    final current = state.value;
    if (current == null) return true;

    try {
      final repository = await ref.read(sheetsRepositoryProvider.future);
      final currentYear = isoWeekYear(DateTime.now());
      final yearData = current.snapshot.yearData[currentYear];
      final matrixGridId = yearData == null
          ? null
          : current.snapshot.gridIdsByTabName[yearData.tabName];

      ExerciseMuscleInfo? muscleEntry;
      for (final info in current.snapshot.exerciseMuscleInfo) {
        if (info.exerciseName.toLowerCase() == exercise.name.toLowerCase()) {
          muscleEntry = info;
          break;
        }
      }

      final result = await repository.deleteExercise(
        yearData: yearData,
        matrixGridId: matrixGridId,
        exercise: exercise,
        exerciseUnitsTable: current.snapshot.exerciseUnitsTable,
        muscleColumnEntry: muscleEntry,
      );
      if (result.isOk) {
        final queue = ref.read(pendingSyncQueueProvider);
        await queue.cancelPendingExercise(exercise.name);
        await refresh();
      }
    } catch (_) {
      // Best-effort sheet mirror — the local delete above already succeeded.
    }
    return true;
  }

  /// Appends a custom workout day to the sheet-backed `WorkoutDays` tab,
  /// queuing a durable retry on failure (safe to replay later since an
  /// append doesn't depend on current row positions).
  Future<bool> addWorkoutDayToSheet(WorkoutDayDef def) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final queue = ref.read(pendingSyncQueueProvider);
    final current = state.value;

    if (current == null || !current.snapshot.classifiedTabs.hasWorkoutDaysTab) {
      final ensured = await repository.ensureWorkoutDaysTab();
      if (ensured.isErr) {
        await queue.enqueueWorkoutDay(def);
        return false;
      }
    }

    final result = await repository.appendWorkoutDay(def);
    if (result.isErr) {
      await queue.enqueueWorkoutDay(def);
      return false;
    }
    // `values.append` with an "A1" range always lands right after the
    // sheet's current last data row (Sheets API's own append semantics),
    // so the new row's index is deterministic without a re-fetch.
    final existing = state.value?.snapshot.workoutDayDefs ?? const [];
    final maxRow = existing.fold<int>(
      0,
      (max, d) => d.sheetRowIndex != null && d.sheetRowIndex! > max
          ? d.sheetRowIndex!
          : max,
    );
    _patchWorkoutDayDefs((current) {
      if (current.any((d) => d.id == def.id)) return current;
      return [
        ...current,
        WorkoutDayDef(
          id: def.id,
          label: def.label,
          muscleGroups: def.muscleGroups,
          legacyDay: def.legacyDay,
          sheetRowIndex: maxRow + 1,
        ),
      ];
    });
    return true;
  }

  /// Updates a workout day's label/muscle list in place on the sheet. If
  /// [def] hasn't been confirmed synced yet (no `sheetRowIndex`, e.g. it's
  /// still a locally-pending add), there's no row to target yet — the
  /// caller-updated local/pending state already carries the new values, so
  /// this is a no-op until the pending add itself completes.
  Future<bool> updateWorkoutDayOnSheet(WorkoutDayDef def) async {
    if (def.sheetRowIndex == null) return true;
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final result = await repository.updateWorkoutDay(def);
    if (result.isErr) return false;
    _patchWorkoutDayDefs(
      (current) => [for (final d in current) d.id == def.id ? def : d],
    );
    return true;
  }

  /// Deletes a workout day's row from the sheet — fire-and-forget (not
  /// queued, per the same reasoning as [deleteVisit]/[deleteBodyWeightEntry]:
  /// a delete replayed later against a since-shifted row layout is unsafe).
  /// Also cancels any still-pending queued add for [def.id].
  Future<bool> removeWorkoutDayFromSheet(WorkoutDayDef def) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final queue = ref.read(pendingSyncQueueProvider);
    await queue.cancelPendingWorkoutDay(def.id);

    final rowIndex = def.sheetRowIndex;
    if (rowIndex == null) return true; // never made it to the sheet yet.
    final current = state.value;
    final gridId = current?.snapshot.gridIdsByTabName[kWorkoutDaysTabName];
    if (gridId == null) return false;

    final result = await repository.deleteWorkoutDay(
      rowIndex: rowIndex,
      workoutDaysGridId: gridId,
    );
    if (result.isErr) return false;
    _patchWorkoutDayDefs((current) {
      final remaining = current.where((d) => d.id != def.id);
      // Rows after the deleted one shift up by one in the sheet.
      return [
        for (final d in remaining)
          d.sheetRowIndex != null && d.sheetRowIndex! > rowIndex
              ? WorkoutDayDef(
                  id: d.id,
                  label: d.label,
                  muscleGroups: d.muscleGroups,
                  legacyDay: d.legacyDay,
                  sheetRowIndex: d.sheetRowIndex! - 1,
                )
              : d,
      ];
    });
    return true;
  }

  /// One-time startup sweep that merges and removes any duplicate
  /// `WorkoutDays` rows left over from before the durable seed guard
  /// (`AppSettingsService.hasSeededWorkoutDays`) existed — safe to call on
  /// every launch since it's gated by its own persisted flag and no-ops
  /// once there's nothing left to merge. For each id with more than one
  /// row, unions their muscle groups and keeps the latest label (see
  /// [mergeDuplicateWorkoutDays]), overwrites the lowest-indexed row with
  /// that result, and deletes the rest (highest row index first, so
  /// earlier indices stay valid mid-sweep).
  Future<void> cleanupDuplicateWorkoutDays() async {
    final settings = ref.read(appSettingsServiceProvider);
    if (settings.hasCleanedUpDuplicateWorkoutDays) return;

    final current = state.value;
    if (current == null) return;

    final byId = <String, List<WorkoutDayDef>>{};
    for (final d in current.snapshot.workoutDayDefs) {
      if (d.sheetRowIndex == null) continue;
      byId.putIfAbsent(d.id, () => []).add(d);
    }
    final duplicateGroups = byId.values.where((g) => g.length > 1).toList();
    if (duplicateGroups.isEmpty) {
      await settings.setHasCleanedUpDuplicateWorkoutDays(true);
      return;
    }

    final gridId = current.snapshot.gridIdsByTabName[kWorkoutDaysTabName];
    if (gridId == null) return; // retry on next launch.
    final repository = await ref.read(sheetsRepositoryProvider.future);

    final merges = <WorkoutDayDef>[];
    final rowsToDelete = <int>[];
    for (final group in duplicateGroups) {
      final merged = mergeDuplicateWorkoutDays(group).single;
      merges.add(merged);
      final lowestRow = merged.sheetRowIndex!;
      for (final d in group) {
        if (d.sheetRowIndex! != lowestRow) rowsToDelete.add(d.sheetRowIndex!);
      }
    }

    for (final merged in merges) {
      final result = await repository.updateWorkoutDay(merged);
      if (result.isErr) return; // retry on next launch.
    }

    rowsToDelete.sort((a, b) => b.compareTo(a));
    for (final rowIndex in rowsToDelete) {
      final result = await repository.deleteWorkoutDay(
        rowIndex: rowIndex,
        workoutDaysGridId: gridId,
      );
      if (result.isErr) return; // retry on next launch.
    }

    await settings.setHasCleanedUpDuplicateWorkoutDays(true);
    // A one-time, infrequent sweep — unlike the interactive per-action
    // mutators above, a brief read-after-write lag here is harmless (it
    // self-heals on the next natural refresh) and not worth hand-computing
    // every surviving row's shifted index for.
    await refresh();
  }

  /// Changes a previously logged visit's date, including moving it to a
  /// different ISO week and/or year. Writes to the local DB first (always
  /// succeeds); the heavier sheet-side re-filing below — recomputing the
  /// matrix cell it leaves, writing/merging the cell it joins, and moving
  /// its meta row (in-place if the year is unchanged, append-then-delete
  /// across meta tabs otherwise) — is then attempted best-effort and never
  /// blocks or fails this call.
  Future<bool> updateVisitDate(MetaRow metaRow, DateTime newDate) async {
    final newIsoWeek = isoWeekNumber(newDate);
    final newIsoYear = isoWeekYear(newDate);

    await ref
        .read(workoutDaoProvider)
        .updateDate(
          metaRow.visitId,
          date: newDate,
          isoWeek: newIsoWeek,
          isoYear: newIsoYear,
        );
    ref.invalidate(localVisitsProvider);

    final current = state.value;
    if (current == null) return true;
    try {
      await _pushVisitDateToSheet(
        current: current,
        metaRow: metaRow,
        newDate: newDate,
        newIsoWeek: newIsoWeek,
        newIsoYear: newIsoYear,
      );
    } catch (_) {
      // Best-effort sheet mirror — the local date change above already succeeded.
    }
    return true;
  }

  Future<void> _pushVisitDateToSheet({
    required SnapshotState current,
    required MetaRow metaRow,
    required DateTime newDate,
    required int newIsoWeek,
    required int newIsoYear,
  }) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);

    final oldYearData = current.snapshot.yearData[metaRow.isoYear];
    final oldMetaTabName =
        current.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
    final oldWeekColumn = oldYearData?.weekColumns[metaRow.isoWeek];
    if (oldYearData == null || oldMetaTabName == null) return;

    if (newIsoWeek == metaRow.isoWeek && newIsoYear == metaRow.isoYear) {
      final result = await repository.updateVisitDateInPlace(
        metaTabName: oldMetaTabName,
        metaRowIndex: metaRow.rowIndex,
        date: newDate,
        isoWeek: newIsoWeek,
        isoYear: newIsoYear,
      );
      if (result.isErr) return;
      await refresh();
      return;
    }
    if (oldWeekColumn == null) return;

    final contextResult = await _resolveOrCreateYearContext(
      repository: repository,
      snapshot: current.snapshot,
      year: newIsoYear,
      week: newIsoWeek,
    );
    if (contextResult.isErr) return;
    final newContext = (contextResult as Ok<YearWriteContext>).value;

    // Recompute/blank each cell this visit is leaving, from whatever other
    // visits (if any) still share that (exercise, week) cell — same
    // pairwise-average convention new writes already use, applied in
    // original (row-index/append) order.
    final otherRowsSameWeek =
        oldYearData.metaRows
            .where(
              (m) =>
                  m.rowIndex != metaRow.rowIndex &&
                  m.isoWeek == metaRow.isoWeek,
            )
            .toList()
          ..sort((a, b) => a.rowIndex.compareTo(b.rowIndex));

    for (final logged in metaRow.exercises) {
      final exercise = oldYearData.findExercise(logged.exerciseName);
      if (exercise?.sheetRow == null) continue;
      double? acc;
      for (final other in otherRowsSameWeek) {
        LoggedExerciseRepRange? range;
        for (final e in other.exercises) {
          if (e.exerciseName.toLowerCase() ==
              logged.exerciseName.toLowerCase()) {
            range = e;
            break;
          }
        }
        if (range == null || range.actualWeights.isEmpty) continue;
        final avg =
            range.actualWeights.reduce((a, b) => a + b) /
            range.actualWeights.length;
        acc = acc == null ? avg : (acc + avg) / 2;
      }
      final cellResult = await repository.writeMatrixCell(
        matrixTabName: oldYearData.tabName,
        rowIndex: exercise!.sheetRow!,
        columnIndex: oldWeekColumn,
        value: acc ?? '',
      );
      if (cellResult.isErr) return;
    }

    // Rebuild this visit's entries from the meta row's own logged data
    // (falling back to the old matrix cell's weight for legacy rows with
    // no per-set weight on record), then write them into the new tab via
    // the exact same plan a fresh log-workout write would use.
    final entries = <ExerciseEntry>[
      for (final logged in metaRow.exercises)
        ExerciseEntry(
          exercise:
              oldYearData.findExercise(logged.exerciseName) ??
              Exercise(
                name: logged.exerciseName,
                muscleGroup: kCurrentMuscleGroups.first,
                muscleGroupKnown: false,
              ),
          sets: logged.actualReps.isNotEmpty
              ? [
                  for (var i = 0; i < logged.actualReps.length; i++)
                    SetEntry(
                      weight: i < logged.actualWeights.length
                          ? logged.actualWeights[i]
                          : (_oldCellWeight(
                                  oldYearData,
                                  logged.exerciseName,
                                  oldWeekColumn,
                                ) ??
                                0),
                      reps: logged.actualReps[i],
                      approxReps: logged.isApprox(i),
                      feedback: logged.feedbackFor(i),
                    ),
                ]
              : [
                  SetEntry(
                    weight:
                        _oldCellWeight(
                          oldYearData,
                          logged.exerciseName,
                          oldWeekColumn,
                        ) ??
                        0,
                    reps: 0,
                  ),
                ],
          targetRepRangeLow: logged.repRangeLow,
          targetRepRangeHigh: logged.repRangeHigh,
        ),
    ];

    final movedVisit = WorkoutVisit(
      visitId: metaRow.visitId,
      date: newDate,
      isoWeek: newIsoWeek,
      isoYear: newIsoYear,
      entries: entries,
      rating: metaRow.rating,
      ratingRelevance: metaRow.ratingRelevance,
      sourceTab: newContext.yearData.tabName,
      note: metaRow.note,
      workoutDayId: metaRow.workoutDayId,
    );

    final plan = const SheetWriter().planVisitWrite(
      yearData: newContext.yearData,
      visit: movedVisit,
      sheetGridId: newContext.sheetGridId,
    );
    final applyResult = await repository.applyVisitWritePlan(plan);
    if (applyResult.isErr) return;

    if (newIsoYear == metaRow.isoYear) {
      final result = await repository.updateVisitDateInPlace(
        metaTabName: oldMetaTabName,
        metaRowIndex: metaRow.rowIndex,
        date: newDate,
        isoWeek: newIsoWeek,
        isoYear: newIsoYear,
      );
      if (result.isErr) return;
    } else {
      // Append-before-delete: a failure partway leaves a harmless
      // duplicate rather than a lost visit.
      final appendResult = await repository.appendMetaRow(
        metaTabName: newContext.metaTabName,
        visit: movedVisit,
      );
      if (appendResult.isErr) return;
      final oldMetaGridId = current.snapshot.gridIdsByTabName[oldMetaTabName];
      if (oldMetaGridId != null) {
        await repository.deleteMetaRow(
          metaTabGridId: oldMetaGridId,
          metaRowIndex: metaRow.rowIndex,
        );
      }
    }

    await refresh();
  }

  double? _oldCellWeight(
    YearSheetData yearData,
    String exerciseName,
    int weekColumn,
  ) {
    final exercise = yearData.findExercise(exerciseName);
    if (exercise?.sheetRow == null) return null;
    return yearData.cellValues[CellKey(exercise!.sheetRow!, weekColumn)];
  }

  Future<void> retryPendingSyncs() async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final queue = ref.read(pendingSyncQueueProvider);
    // Refresh first so the workoutVisit dedup check in [PendingSyncQueue]
    // (matching on visitId against metaRows already on the sheet) sees an
    // up-to-date picture, not whatever was last cached in memory — a queued
    // visit may have actually landed on a previous attempt whose success
    // response was lost (more common on web/PWA), and retrying blind would
    // append it a second time.
    await refresh();
    await queue.retryAll(
      repository: repository,
      resolveYearContext: (year) async {
        final current = state.value;
        if (current == null) {
          return Result.err(StateError('No snapshot loaded yet.'));
        }
        return _resolveOrCreateYearContext(
          repository: repository,
          snapshot: current.snapshot,
          year: year,
          week: null,
        );
      },
      resolveExerciseUnitsTable: () => _resolveExerciseUnitsTable(repository),
      resolveWorkoutVisit: (visitId) => ref
          .read(workoutDaoProvider)
          .getVisitByVisitId(visitId, ref.read(exerciseDaoProvider)),
      markWorkoutVisitPushed: (visitId, sheetMetaRowIndex) => ref
          .read(workoutDaoProvider)
          .markSheetPushed(visitId, sheetMetaRowIndex: sheetMetaRowIndex),
    );
    await refresh();
  }

  /// Runs the "sheet wins" reconciliation pass (see [SheetImportService])
  /// against the just-loaded snapshot, then refreshes every local-DB-backed
  /// provider so the UI reflects whatever it imported immediately. Call
  /// this after first connecting a sheet, from a manual "Sync now", and
  /// during the v3.0.0 upgrade migration.
  Future<void> importFromSheet() async {
    final current = await future;
    await ref
        .read(sheetImportServiceProvider)
        .importAndReconcile(current.snapshot);
    ref.invalidate(localVisitsProvider);
    ref.invalidate(localExercisesProvider);
    ref.invalidate(localBodyWeightProvider);
    ref.invalidate(localNotesProvider);
    await ref.read(workoutDayDefsProvider.notifier).reloadFromDb();
  }

  /// Re-reads a fresh `Exercises` tab `Exercise`/`Unit` side-table,
  /// creating the tab first if it doesn't exist yet — needed to replay a
  /// queued exercise-unit write, since row indices may have shifted since
  /// it was queued.
  Future<Result<ExerciseUnitsTable>> _resolveExerciseUnitsTable(
    SheetsRepository repository,
  ) async {
    final snapResult = await repository.loadSnapshot(years: const []);
    if (snapResult.isErr) {
      final err = snapResult as Err<SpreadsheetSnapshot>;
      return Result.err(err.error, err.stackTrace);
    }
    var snapshot = (snapResult as Ok<SpreadsheetSnapshot>).value;
    if (!snapshot.classifiedTabs.hasExercisesTab) {
      final ensured = await repository.ensureExercisesTab();
      if (ensured.isErr) {
        final err = ensured as Err<void>;
        return Result.err(err.error, err.stackTrace);
      }
      final reloaded = await repository.loadSnapshot(years: const []);
      if (reloaded.isErr) {
        final err = reloaded as Err<SpreadsheetSnapshot>;
        return Result.err(err.error, err.stackTrace);
      }
      snapshot = (reloaded as Ok<SpreadsheetSnapshot>).value;
    }
    return Result.ok(snapshot.exerciseUnitsTable);
  }

  Future<Result<YearWriteContext>> _resolveOrCreateYearContext({
    required SheetsRepository repository,
    required SpreadsheetSnapshot snapshot,
    required int year,
    required int? week,
  }) async {
    var yearData = snapshot.yearData[year];
    var gridIdsByTabName = snapshot.gridIdsByTabName;
    var metaTabName = snapshot.classifiedTabs.metaTabByYear[year];

    final hasTab = snapshot.classifiedTabs.writableTabFor(year) != null;
    final hasMetaTab = snapshot.classifiedTabs.metaTabByYear[year] != null;
    if (!hasTab) {
      final ensured = await repository.ensureTabsForNewYear(year);
      if (ensured.isErr) {
        return Result.err((ensured as Err<void>).error, ensured.stackTrace);
      }
    } else if (!hasMetaTab) {
      // The matrix tab already existed (e.g. hand-tracked before this app
      // was used) but its metadata tab was never created — create just
      // that, without touching the user's existing matrix data.
      final ensured = await repository.ensureMetaTabForYear(year);
      if (ensured.isErr) {
        return Result.err((ensured as Err<void>).error, ensured.stackTrace);
      }
    } else if (yearData != null &&
        week != null &&
        !yearData.weekColumns.containsKey(week) &&
        yearData.isFull) {
      final currentTabIndex = _overflowIndexOf(yearData.tabName);
      final overflowResult = await repository.createOverflowTab(
        year: year,
        overflowIndex: currentTabIndex + 1,
        previousTabData: yearData,
      );
      if (overflowResult.isErr) {
        return Result.err(
          (overflowResult as Err<String>).error,
          overflowResult.stackTrace,
        );
      }
    }

    final reloaded = await repository.loadSnapshot(years: [year]);
    if (reloaded.isErr) {
      return Result.err(
        (reloaded as Err<SpreadsheetSnapshot>).error,
        reloaded.stackTrace,
      );
    }
    final reloadedSnapshot = (reloaded as Ok<SpreadsheetSnapshot>).value;
    yearData = reloadedSnapshot.yearData[year];
    gridIdsByTabName = reloadedSnapshot.gridIdsByTabName;
    metaTabName = reloadedSnapshot.classifiedTabs.metaTabByYear[year];

    if (yearData == null || metaTabName == null) {
      return Result.err(StateError('Failed to prepare tabs for year $year.'));
    }
    final gridId = gridIdsByTabName[yearData.tabName];
    if (gridId == null) {
      return Result.err(
        StateError('No grid id found for tab ${yearData.tabName}.'),
      );
    }

    return Result.ok(
      YearWriteContext(
        yearData: yearData,
        sheetGridId: gridId,
        metaTabName: metaTabName,
      ),
    );
  }

  int _overflowIndexOf(String tabName) {
    final match = RegExp(r'_(\d+)$').firstMatch(tabName);
    return match == null ? 1 : int.parse(match.group(1)!);
  }
}

final snapshotProvider = AsyncNotifierProvider<SnapshotNotifier, SnapshotState>(
  SnapshotNotifier.new,
);

final bodyWeightEntriesProvider = Provider<List<BodyWeightEntry>>((ref) {
  return ref.watch(localBodyWeightProvider).value ?? const [];
});

/// Every per-exercise/per-set note, from the local database.
final notesProvider = Provider<List<ExerciseNote>>((ref) {
  return ref.watch(localNotesProvider).value ?? const [];
});

/// Every known exercise, from the local database — available instantly
/// with zero sheet dependency. Backs the "Exercises" section in Settings
/// where a unit can be edited after the fact.
final allKnownExercisesProvider = Provider<List<Exercise>>((ref) {
  return ref.watch(localExercisesProvider).value ?? const [];
});

/// Exercise name (lowercased) -> its resolved [Exercise], for O(1) lookups
/// when grouping the log-workout exercise list by muscle.
final exerciseMuscleByNameProvider = Provider<Map<String, Exercise>>((ref) {
  final exercises = ref.watch(allKnownExercisesProvider);
  return {for (final e in exercises) e.name.toLowerCase(): e};
});
