import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/sheets/v4.dart';

import '../core/constants/muscle_groups.dart';
import '../core/constants/sheet_layout.dart';
import '../core/utils/iso_week.dart';
import '../core/utils/result.dart';
import '../models/body_weight_entry.dart';
import '../models/exercise.dart';
import '../models/exercise_muscle_info.dart';
import '../models/rating_relevance.dart';
import '../models/workout_day_def.dart';
import '../models/workout_visit.dart';
import '../models/year_sheet_data.dart';
import '../services/sheets/sheet_writer.dart';
import '../services/sheets/sheets_repository.dart';
import '../services/sync/pending_sync_queue.dart';
import 'auth_providers.dart';
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

  /// Logs a completed workout visit. Ensures the target year/overflow tab
  /// exists, writes the matrix + metadata rows, and returns the metadata
  /// row index (needed for the follow-up rating write) alongside whether
  /// it synced live or was queued for later.
  Future<(SaveOutcome, int?)> logVisit(WorkoutVisit visit) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final queue = ref.read(pendingSyncQueueProvider);
    final current = state.value;
    if (current == null) {
      await queue.enqueueWorkoutVisit(visit);
      return (SaveOutcome.queuedOffline, null);
    }

    final contextResult = await _resolveOrCreateYearContext(
      repository: repository,
      snapshot: current.snapshot,
      year: visit.isoYear,
      week: visit.isoWeek,
    );

    if (contextResult.isErr) {
      await queue.enqueueWorkoutVisit(visit);
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
      await queue.enqueueWorkoutVisit(visit);
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
    return (SaveOutcome.synced, metaRowIndex);
  }

  Future<SaveOutcome> saveRating({
    required int isoYear,
    required int metaRowIndex,
    required double rating,
    RatingRelevance? ratingRelevance,
  }) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final queue = ref.read(pendingSyncQueueProvider);
    final current = state.value;
    final metaTabName = current?.snapshot.classifiedTabs.metaTabByYear[isoYear];

    if (metaTabName == null) {
      await queue.enqueueRating(
        metaTabName: '${isoYear}_meta',
        metaRowIndex: metaRowIndex,
        rating: rating,
        ratingRelevance: ratingRelevance,
      );
      return SaveOutcome.queuedOffline;
    }

    final result = await repository.updateRating(
      metaTabName: metaTabName,
      metaRowIndex: metaRowIndex,
      rating: rating,
    );
    if (result.isErr) {
      await queue.enqueueRating(
        metaTabName: metaTabName,
        metaRowIndex: metaRowIndex,
        rating: rating,
        ratingRelevance: ratingRelevance,
      );
      return SaveOutcome.queuedOffline;
    }
    if (ratingRelevance != null) {
      final relResult = await repository.updateRatingRelevance(
        metaTabName: metaTabName,
        metaRowIndex: metaRowIndex,
        value: ratingRelevance,
      );
      if (relResult.isErr) {
        await queue.enqueueRating(
          metaTabName: metaTabName,
          metaRowIndex: metaRowIndex,
          rating: rating,
          ratingRelevance: ratingRelevance,
        );
        return SaveOutcome.queuedOffline;
      }
    }
    return SaveOutcome.synced;
  }

  Future<SaveOutcome> addBodyWeight({
    required DateTime date,
    required double weightKg,
  }) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final queue = ref.read(pendingSyncQueueProvider);
    final current = state.value;

    if (current == null || !current.snapshot.classifiedTabs.hasBodyWeightTab) {
      final ensured = await repository.ensureBodyWeightTab();
      if (ensured.isErr) {
        await queue.enqueueBodyWeight(date: date, weightKg: weightKg);
        return SaveOutcome.queuedOffline;
      }
    }

    final result = await repository.appendBodyWeight(
      date: date,
      weightKg: weightKg,
    );
    if (result.isErr) {
      await queue.enqueueBodyWeight(date: date, weightKg: weightKg);
      return SaveOutcome.queuedOffline;
    }
    await refresh();
    return SaveOutcome.synced;
  }

  /// Deletes a previously logged visit: clears its matrix cells and
  /// removes its metadata row. Returns true on success.
  Future<bool> deleteVisit(MetaRow metaRow) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final current = state.value;
    if (current == null) return false;

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
      return false;
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
    if (result.isErr) return false;
    await refresh();
    return true;
  }

  /// Updates the weights for some/all exercises in a previously logged
  /// visit. [newWeightByExerciseName] only needs entries for exercises
  /// whose weight actually changed.
  Future<bool> updateVisitWeights(
    MetaRow metaRow,
    Map<String, double> newWeightByExerciseName,
  ) async {
    if (newWeightByExerciseName.isEmpty) return true;
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final current = state.value;
    if (current == null) return false;

    final yearData = current.snapshot.yearData[metaRow.isoYear];
    final weekColumn = yearData?.weekColumns[metaRow.isoWeek];
    if (yearData == null || weekColumn == null) return false;

    final weightByRow = <int, double>{};
    for (final entry in newWeightByExerciseName.entries) {
      final row = yearData.findExercise(entry.key)?.sheetRow;
      if (row != null) weightByRow[row] = entry.value;
    }

    final result = await repository.updateVisitWeights(
      matrixTabName: yearData.tabName,
      weekColumnIndex: weekColumn,
      weightByExerciseRow: weightByRow,
    );
    if (result.isErr) return false;
    await refresh();
    return true;
  }

  /// Edits the note for a previously logged visit — writes to the
  /// canonical per-visit note column (meta tab column J), and, for a
  /// legacyGrouped year, best-effort mirrors it into the header-row cell
  /// too (matching the older hand-reading convention on those tabs).
  Future<bool> saveVisitNote(MetaRow metaRow, String note) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final current = state.value;
    if (current == null) return false;

    final metaTabName =
        current.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
    if (metaTabName == null) return false;

    final result = await repository.updateVisitNote(
      metaTabName: metaTabName,
      metaRowIndex: metaRow.rowIndex,
      note: note,
    );
    if (result.isErr) return false;

    final yearData = current.snapshot.yearData[metaRow.isoYear];
    if (yearData != null &&
        (yearData.format == MatrixTabFormat.legacyGrouped ||
            yearData.format == MatrixTabFormat.currentGrouped)) {
      int? headerRow;
      for (final label in metaRow.muscleGroups) {
        final group = sheetHeaderMuscleGroupForFormat(label, yearData.format);
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

    await refresh();
    return true;
  }

  /// Edits a previously logged visit's rating-relevance flag alone (rating
  /// itself unchanged) — used from Edit Visit when only the "feeling sick"
  /// state changes.
  Future<bool> saveRatingRelevance(
    MetaRow metaRow,
    RatingRelevance value,
  ) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final current = state.value;
    final metaTabName =
        current?.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
    if (metaTabName == null) return false;

    final result = await repository.updateRatingRelevance(
      metaTabName: metaTabName,
      metaRowIndex: metaRow.rowIndex,
      value: value,
    );
    if (result.isErr) return false;
    await refresh();
    return true;
  }

  /// Rewrites the exercise order of a previously logged visit (e.g. after
  /// the user drags them into a different order in the edit screen).
  Future<bool> updateVisitExerciseOrder(
    MetaRow metaRow,
    List<LoggedExerciseRepRange> newOrder,
  ) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final current = state.value;
    final metaTabName =
        current?.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
    if (metaTabName == null) return false;

    final result = await repository.updateVisitExerciseOrder(
      metaTabName: metaTabName,
      metaRowIndex: metaRow.rowIndex,
      exercises: newOrder,
    );
    if (result.isErr) return false;
    await refresh();
    return true;
  }

  Future<bool> updateBodyWeightEntry(
    BodyWeightEntry entry, {
    required DateTime date,
    required double weightKg,
  }) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final result = await repository.updateBodyWeightEntry(
      rowIndex: entry.rowIndex,
      date: date,
      weightKg: weightKg,
    );
    if (result.isErr) return false;
    await refresh();
    return true;
  }

  Future<bool> deleteBodyWeightEntry(BodyWeightEntry entry) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final current = state.value;
    final gridId = current?.snapshot.gridIdsByTabName[kBodyWeightTabName];
    if (gridId == null) return false;

    final result = await repository.deleteBodyWeightEntry(
      rowIndex: entry.rowIndex,
      bodyWeightGridId: gridId,
    );
    if (result.isErr) return false;
    await refresh();
    return true;
  }

  /// Persists a newly-added exercise's stated muscle back to the
  /// "Exercises" reference tab (appended to that muscle's existing
  /// column), so it sticks across app restarts and immediately affects
  /// muscle-based grouping/graphs.
  Future<bool> addExerciseMuscle({
    required String exerciseName,
    required int columnIndex,
  }) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final result = await repository.appendExerciseToMuscleColumn(
      columnIndex: columnIndex,
      exerciseName: exerciseName,
    );
    if (result.isErr) return false;
    await refresh();
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
    await refresh();
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
    await refresh();
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
    await refresh();
    return true;
  }

  /// Changes a previously logged visit's date, including moving it to a
  /// different ISO week and/or year — re-filing its matrix-cell data
  /// (recomputing/blanking the cell it leaves, writing/merging the cell it
  /// joins) and its meta row (in-place update if the year is unchanged,
  /// append-then-delete across meta tabs otherwise). Requires a live
  /// connection — not offline-queueable, since it depends on freshly-read
  /// state across potentially multiple tabs that a delayed retry can't
  /// safely recompute. Returns false on any failure; the caller should ask
  /// the user to retry while online rather than silently queuing.
  Future<bool> updateVisitDate(MetaRow metaRow, DateTime newDate) async {
    final repository = await ref.read(sheetsRepositoryProvider.future);
    final current = state.value;
    if (current == null) return false;

    final newIsoWeek = isoWeekNumber(newDate);
    final newIsoYear = isoWeekYear(newDate);

    final oldYearData = current.snapshot.yearData[metaRow.isoYear];
    final oldMetaTabName =
        current.snapshot.classifiedTabs.metaTabByYear[metaRow.isoYear];
    final oldWeekColumn = oldYearData?.weekColumns[metaRow.isoWeek];
    if (oldYearData == null || oldMetaTabName == null) return false;

    if (newIsoWeek == metaRow.isoWeek && newIsoYear == metaRow.isoYear) {
      final result = await repository.updateVisitDateInPlace(
        metaTabName: oldMetaTabName,
        metaRowIndex: metaRow.rowIndex,
        date: newDate,
        isoWeek: newIsoWeek,
        isoYear: newIsoYear,
      );
      if (result.isErr) return false;
      await refresh();
      return true;
    }
    if (oldWeekColumn == null) return false;

    final contextResult = await _resolveOrCreateYearContext(
      repository: repository,
      snapshot: current.snapshot,
      year: newIsoYear,
      week: newIsoWeek,
    );
    if (contextResult.isErr) return false;
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
      if (cellResult.isErr) return false;
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
    if (applyResult.isErr) return false;

    if (newIsoYear == metaRow.isoYear) {
      final result = await repository.updateVisitDateInPlace(
        metaTabName: oldMetaTabName,
        metaRowIndex: metaRow.rowIndex,
        date: newDate,
        isoWeek: newIsoWeek,
        isoYear: newIsoYear,
      );
      if (result.isErr) return false;
    } else {
      // Append-before-delete: a failure partway leaves a harmless
      // duplicate rather than a lost visit.
      final appendResult = await repository.appendMetaRow(
        metaTabName: newContext.metaTabName,
        visit: movedVisit,
      );
      if (appendResult.isErr) return false;
      final oldMetaGridId = current.snapshot.gridIdsByTabName[oldMetaTabName];
      if (oldMetaGridId != null) {
        await repository.deleteMetaRow(
          metaTabGridId: oldMetaGridId,
          metaRowIndex: metaRow.rowIndex,
        );
      }
    }

    await refresh();
    return true;
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
    );
    await refresh();
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
  final snapshot = ref.watch(snapshotProvider).value;
  return snapshot?.snapshot.bodyWeightEntries ?? const [];
});

final currentYearDataProvider = Provider<YearSheetData?>((ref) {
  final snapshot = ref.watch(snapshotProvider).value;
  if (snapshot == null) return null;
  final currentYear = isoWeekYear(DateTime.now());
  return snapshot.snapshot.yearData[currentYear];
});

final exerciseMuscleInfoProvider = Provider<List<ExerciseMuscleInfo>>((ref) {
  final snapshot = ref.watch(snapshotProvider).value;
  return snapshot?.snapshot.exerciseMuscleInfo ?? const [];
});

/// Workout days confirmed synced to the sheet-backed `WorkoutDays` tab (see
/// `workoutDayDefsProvider` in settings_providers.dart, which layers in any
/// still-pending local ones on top of this).
final sheetWorkoutDayDefsProvider = Provider<List<WorkoutDayDef>>((ref) {
  final snapshot = ref.watch(snapshotProvider).value;
  return snapshot?.snapshot.workoutDayDefs ?? const [];
});

/// Exercise name (lowercased) -> its muscle/workout info, for O(1) lookups
/// when grouping the log-workout exercise list by muscle.
final exerciseMuscleByNameProvider = Provider<Map<String, ExerciseMuscleInfo>>((
  ref,
) {
  final info = ref.watch(exerciseMuscleInfoProvider);
  return {for (final e in info) e.exerciseName.toLowerCase(): e};
});
