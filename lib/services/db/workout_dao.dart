import 'package:sqflite/sqflite.dart';

import '../../core/constants/muscle_groups.dart';
import '../../models/rating_relevance.dart';
import '../../models/workout_visit.dart';
import '../../models/year_sheet_data.dart';
import 'app_database.dart';
import 'exercise_dao.dart';
import 'workout_mappers.dart';

class WorkoutDao {
  WorkoutDao(this._db);

  final AppDatabase _db;

  Future<int?> _localVisitId(DatabaseExecutor db, String visitId) async {
    final rows = await db.query(
      'workout_visits',
      columns: ['id'],
      where: 'visit_id = ?',
      whereArgs: [visitId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int;
  }

  /// Inserts a brand-new visit (local-first write path) — always succeeds
  /// regardless of any sheet connection. Returns the new local row id.
  Future<int> insertVisit(
    WorkoutVisit visit, {
    bool needsSheetPush = true,
    bool isSynthetic = false,
    bool exactDateKnown = true,
    int? sheetMetaRowIndex,
  }) {
    return _db.db.transaction((txn) async {
      final visitLocalId = await txn.insert(
        'workout_visits',
        workoutVisitRow(
          visit,
          isSynthetic: isSynthetic,
          exactDateKnown: exactDateKnown,
          sheetMetaRowIndex: sheetMetaRowIndex,
          needsSheetPush: needsSheetPush,
        ),
      );
      await _insertEntries(txn, visitLocalId, visit.entries);
      return visitLocalId;
    });
  }

  Future<void> _insertEntries(
    DatabaseExecutor txn,
    int visitLocalId,
    List<ExerciseEntry> entries,
  ) async {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final entryId = await txn.insert(
        'exercise_entries',
        exerciseEntryRow(entry: entry, localVisitId: visitLocalId, position: i),
      );
      for (var setIndex = 0; setIndex < entry.sets.length; setIndex++) {
        await txn.insert(
          'exercise_sets',
          exerciseSetRow(
            set: entry.sets[setIndex],
            entryId: entryId,
            setIndex: setIndex,
            targetLow: setIndex < entry.targetRepRangeLowPerSet.length
                ? entry.targetRepRangeLowPerSet[setIndex]
                : null,
            targetHigh: setIndex < entry.targetRepRangeHighPerSet.length
                ? entry.targetRepRangeHighPerSet[setIndex]
                : null,
            targetWeight: setIndex < entry.targetWeightPerSet.length
                ? entry.targetWeightPerSet[setIndex]
                : null,
          ),
        );
      }
    }
  }

  /// Replaces a visit's entries/sets wholesale (used for edits and for
  /// sheet-wins reconciliation) and marks it dirty for re-push unless this
  /// write is itself the result of an import *from* the sheet.
  Future<void> replaceVisit(
    WorkoutVisit visit, {
    bool needsSheetPush = true,
    bool isSynthetic = false,
    bool exactDateKnown = true,
    int? sheetMetaRowIndex,
  }) async {
    await _db.db.transaction((txn) async {
      final visitLocalId = await _localVisitId(txn, visit.visitId);
      if (visitLocalId == null) {
        final newId = await txn.insert(
          'workout_visits',
          workoutVisitRow(
            visit,
            isSynthetic: isSynthetic,
            exactDateKnown: exactDateKnown,
            sheetMetaRowIndex: sheetMetaRowIndex,
            needsSheetPush: needsSheetPush,
          ),
        );
        await _insertEntries(txn, newId, visit.entries);
        return;
      }
      await txn.update(
        'workout_visits',
        {
          'date': visit.date.toIso8601String(),
          'iso_week': visit.isoWeek,
          'iso_year': visit.isoYear,
          'rating': visit.rating,
          'rating_relevance': visit.ratingRelevance.name,
          'note': visit.note,
          'workout_day_id': visit.workoutDayId,
          'source_tab': visit.sourceTab,
          'is_synthetic': isSynthetic ? 1 : 0,
          'exact_date_known': exactDateKnown ? 1 : 0,
          'sheet_meta_row_index': sheetMetaRowIndex,
          'needs_sheet_push': needsSheetPush ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [visitLocalId],
      );
      await txn.delete(
        'exercise_entries',
        where: 'visit_id = ?',
        whereArgs: [visitLocalId],
      );
      await _insertEntries(txn, visitLocalId, visit.entries);
    });
  }

  /// Updates just the rating (and, if given, rating-relevance) for an
  /// already-locally-known visit. Marks the row dirty for re-push.
  Future<void> updateRatingFields(
    String visitId, {
    required double rating,
    RatingRelevance? ratingRelevance,
  }) async {
    final values = <String, Object?>{'rating': rating, 'needs_sheet_push': 1};
    if (ratingRelevance != null) {
      values['rating_relevance'] = ratingRelevance.name;
    }
    await _db.db.update(
      'workout_visits',
      values,
      where: 'visit_id = ?',
      whereArgs: [visitId],
    );
  }

  /// Updates just the rating-relevance flag, rating itself unchanged.
  Future<void> updateRatingRelevance(String visitId, RatingRelevance value) async {
    await _db.db.update(
      'workout_visits',
      {'rating_relevance': value.name, 'needs_sheet_push': 1},
      where: 'visit_id = ?',
      whereArgs: [visitId],
    );
  }

  /// Updates just the per-visit note.
  Future<void> updateNote(String visitId, String note) async {
    await _db.db.update(
      'workout_visits',
      {'note': note, 'needs_sheet_push': 1},
      where: 'visit_id = ?',
      whereArgs: [visitId],
    );
  }

  /// Updates just the date/iso week/iso year of a visit.
  Future<void> updateDate(
    String visitId, {
    required DateTime date,
    required int isoWeek,
    required int isoYear,
  }) async {
    await _db.db.update(
      'workout_visits',
      {
        'date': date.toIso8601String(),
        'iso_week': isoWeek,
        'iso_year': isoYear,
        'needs_sheet_push': 1,
      },
      where: 'visit_id = ?',
      whereArgs: [visitId],
    );
  }

  /// Replaces just a visit's exercise entries/sets (weights, reps, order,
  /// per-set overrides) — the edit-screen counterpart to [replaceVisit],
  /// which also overwrites date/rating/note/workout-day columns and so
  /// can't be reused here: those are already saved independently by their
  /// own single-purpose mutators ([updateDate], [updateRatingFields],
  /// [updateNote]) in the same save flow, and reusing [replaceVisit] would
  /// stomp them with a stale in-memory copy. Marks the visit dirty for
  /// re-push.
  Future<void> replaceEntries(String visitId, List<ExerciseEntry> entries) async {
    await _db.db.transaction((txn) async {
      final visitLocalId = await _localVisitId(txn, visitId);
      if (visitLocalId == null) return;
      await txn.delete(
        'exercise_entries',
        where: 'visit_id = ?',
        whereArgs: [visitLocalId],
      );
      await _insertEntries(txn, visitLocalId, entries);
      await txn.update(
        'workout_visits',
        {'needs_sheet_push': 1},
        where: 'id = ?',
        whereArgs: [visitLocalId],
      );
    });
  }

  /// Fetches one full visit (with resolved [Exercise] objects, not just
  /// names) by its stable [visitId] — used by `PendingSyncQueue` to re-read
  /// the current row at sheet-push replay time instead of replaying a
  /// stale snapshot captured when the push was first queued. Returns null
  /// if the visit no longer exists or was soft-deleted since being queued,
  /// which callers should treat as "nothing left to push."
  Future<WorkoutVisit?> getVisitByVisitId(
    String visitId,
    ExerciseDao exerciseDao,
  ) async {
    final db = _db.db;
    final visitRows = await db.query(
      'workout_visits',
      where: 'visit_id = ? AND deleted_at IS NULL',
      whereArgs: [visitId],
      limit: 1,
    );
    if (visitRows.isEmpty) return null;
    final visitRow = visitRows.first;
    final visitLocalId = visitRow['id'] as int;

    final entryRows = await db.query(
      'exercise_entries',
      where: 'visit_id = ?',
      whereArgs: [visitLocalId],
      orderBy: 'position ASC',
    );
    final entryIds = entryRows.map((r) => r['id'] as int).toList();
    final setRows = entryIds.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query(
            'exercise_sets',
            where: 'entry_id IN (${entryIds.map((_) => '?').join(',')})',
            whereArgs: entryIds,
            orderBy: 'entry_id ASC, set_index ASC',
          );
    final setsByEntryId = <int, List<Map<String, Object?>>>{};
    for (final row in setRows) {
      setsByEntryId.putIfAbsent(row['entry_id'] as int, () => []).add(row);
    }

    final entries = <ExerciseEntry>[];
    for (final entryRow in entryRows) {
      final exercise = await exerciseDao.getByName(
        entryRow['exercise_name'] as String,
      );
      if (exercise == null) continue;
      entries.add(
        exerciseEntryFromRows(
          entryRow: entryRow,
          setRows: setsByEntryId[entryRow['id'] as int] ?? const [],
          exercise: exercise,
        ),
      );
    }

    return workoutVisitFromRow(visitRow: visitRow, entries: entries);
  }

  Future<void> softDelete(String visitId) async {
    await _db.db.update(
      'workout_visits',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'visit_id = ?',
      whereArgs: [visitId],
    );
  }

  Future<void> markSheetPushed(String visitId, {int? sheetMetaRowIndex}) {
    return _db.db.update(
      'workout_visits',
      {'needs_sheet_push': 0, 'sheet_meta_row_index': sheetMetaRowIndex},
      where: 'visit_id = ?',
      whereArgs: [visitId],
    );
  }

  Future<List<String>> visitIdsNeedingSheetPush() async {
    final rows = await _db.db.query(
      'workout_visits',
      columns: ['visit_id'],
      where: 'needs_sheet_push = 1 AND deleted_at IS NULL',
    );
    return rows.map((r) => r['visit_id'] as String).toList();
  }

  /// Every non-deleted visit, assembled into the [MetaRow] shape the
  /// analysis layer already consumes — the local-DB replacement for
  /// combining every year's sheet-parsed `metaRows`.
  Future<List<MetaRow>> getAllAsMetaRows() async {
    final db = _db.db;

    final visitRows = await db.query(
      'workout_visits',
      where: 'deleted_at IS NULL',
      orderBy: 'date ASC',
    );
    if (visitRows.isEmpty) return const [];

    final visitIds = visitRows.map((r) => r['id'] as int).toList();
    final entryRows = await db.query(
      'exercise_entries',
      where: 'visit_id IN (${visitIds.map((_) => '?').join(',')})',
      whereArgs: visitIds,
      orderBy: 'visit_id ASC, position ASC',
    );

    final entryIds = entryRows.map((r) => r['id'] as int).toList();
    final setRows = entryIds.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query(
            'exercise_sets',
            where: 'entry_id IN (${entryIds.map((_) => '?').join(',')})',
            whereArgs: entryIds,
            orderBy: 'entry_id ASC, set_index ASC',
          );

    final exerciseRows = await db.query(
      'exercises',
      columns: ['name_lower', 'muscle_group'],
    );
    final muscleHeaderByNameLower = <String, String>{
      for (final row in exerciseRows)
        row['name_lower'] as String: MuscleGroup.values
            .byName(row['muscle_group'] as String)
            .sheetHeader,
    };

    final setsByEntryId = <int, List<Map<String, Object?>>>{};
    for (final row in setRows) {
      setsByEntryId.putIfAbsent(row['entry_id'] as int, () => []).add(row);
    }

    final entriesByVisitId = <int, List<Map<String, Object?>>>{};
    for (final row in entryRows) {
      entriesByVisitId.putIfAbsent(row['visit_id'] as int, () => []).add(row);
    }

    return visitRows.map((visitRow) {
      final visitLocalId = visitRow['id'] as int;
      final entries = entriesByVisitId[visitLocalId] ?? const [];

      final loggedRanges = entries
          .map(
            (entryRow) => loggedExerciseRepRangeFromRows(
              entryRow: entryRow,
              setRows: setsByEntryId[entryRow['id'] as int] ?? const [],
            ),
          )
          .toList();

      final muscleHeaders = <String>{
        for (final entryRow in entries)
          if (muscleHeaderByNameLower.containsKey(
            (entryRow['exercise_name'] as String).toLowerCase(),
          ))
            muscleHeaderByNameLower[(entryRow['exercise_name'] as String)
                .toLowerCase()]!,
      }.toList();

      return metaRowFromVisitRow(
        visitRow: visitRow,
        exercises: loggedRanges,
        muscleGroupSheetHeaders: muscleHeaders,
      );
    }).toList();
  }
}
