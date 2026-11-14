import 'package:sqflite/sqflite.dart';

import '../../models/exercise.dart';
import 'app_database.dart';
import 'exercise_mappers.dart';

class ExerciseDao {
  ExerciseDao(this._db);

  final AppDatabase _db;

  Future<List<Exercise>> getAll() async {
    final rows = await _db.db.query(
      'exercises',
      where: 'deleted_at IS NULL',
      orderBy: 'name_lower ASC',
    );
    return rows.map(exerciseFromRow).toList();
  }

  Future<Exercise?> getByName(String name) async {
    final rows = await _db.db.query(
      'exercises',
      where: 'name_lower = ? AND deleted_at IS NULL',
      whereArgs: [name.toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return exerciseFromRow(rows.first);
  }

  /// Inserts a new exercise, or revives+overwrites a soft-deleted one with
  /// the same name. Throws if a non-deleted exercise with this name exists.
  Future<void> insert(Exercise exercise) async {
    await _db.db.insert(
      'exercises',
      exerciseToRow(exercise),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Upsert used by import/reconcile — sheet data always wins on conflict,
  /// except `notes`/`photoAssetKey`: the sheet has no column for either, so
  /// a sheet-derived [exercise] always carries them as null and must not be
  /// allowed to blank out values already set locally (seeded or
  /// user-entered).
  Future<void> upsert(Exercise exercise) async {
    final existing = await getByName(exercise.name);
    final toWrite = existing == null
        ? exercise
        : Exercise(
            name: exercise.name,
            muscleGroup: exercise.muscleGroup,
            sheetRow: exercise.sheetRow,
            muscleGroupKnown: exercise.muscleGroupKnown,
            unit: exercise.unit,
            customUnitLabel: exercise.customUnitLabel,
            secondaryMuscleGroups: exercise.secondaryMuscleGroups,
            notes: exercise.notes ?? existing.notes,
            photoAssetKey: exercise.photoAssetKey ?? existing.photoAssetKey,
          );
    await _db.db.insert(
      'exercises',
      exerciseToRow(toWrite),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(Exercise exercise) async {
    await _db.db.update(
      'exercises',
      exerciseToRow(exercise),
      where: 'name_lower = ?',
      whereArgs: [exercise.name.toLowerCase()],
    );
  }

  /// Renames an exercise, cascading into the denormalized text columns
  /// that reference it by name (exercise_entries, exercise_notes — these
  /// have no FK to exercises.id, by design, so the rename must be
  /// propagated manually).
  Future<void> rename(String oldName, String newName) async {
    await _db.db.transaction((txn) async {
      await txn.update(
        'exercises',
        {'name': newName, 'name_lower': newName.toLowerCase()},
        where: 'name_lower = ?',
        whereArgs: [oldName.toLowerCase()],
      );
      await txn.update(
        'exercise_entries',
        {'exercise_name': newName},
        where: 'exercise_name = ?',
        whereArgs: [oldName],
      );
      await txn.update(
        'exercise_notes',
        {'exercise_name': newName},
        where: 'exercise_name = ?',
        whereArgs: [oldName],
      );
    });
  }

  Future<void> softDelete(String name) async {
    await _db.db.update(
      'exercises',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'name_lower = ?',
      whereArgs: [name.toLowerCase()],
    );
  }
}
