import 'package:sqflite/sqflite.dart';

import '../../models/workout_day_def.dart';
import 'app_database.dart';
import 'workout_day_mappers.dart';

class WorkoutDayDao {
  WorkoutDayDao(this._db);

  final AppDatabase _db;

  Future<List<WorkoutDayDef>> getAll() async {
    final rows = await _db.db.query(
      'workout_day_defs',
      where: 'deleted_at IS NULL',
    );
    return rows.map(workoutDayDefFromRow).toList();
  }

  Future<void> upsert(WorkoutDayDef day) async {
    await _db.db.insert(
      'workout_day_defs',
      workoutDayDefToRow(day),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertAll(List<WorkoutDayDef> days) async {
    final batch = _db.db.batch();
    for (final day in days) {
      batch.insert(
        'workout_day_defs',
        workoutDayDefToRow(day),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> softDelete(String id) async {
    await _db.db.update(
      'workout_day_defs',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
