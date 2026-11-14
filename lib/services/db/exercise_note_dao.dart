import '../../models/exercise_note.dart';
import 'app_database.dart';
import 'exercise_note_mappers.dart';

const String _joinedSelect = '''
  SELECT exercise_notes.*, workout_visits.visit_id AS visit_uuid
  FROM exercise_notes
  JOIN workout_visits ON workout_visits.id = exercise_notes.visit_id
''';

class ExerciseNoteDao {
  ExerciseNoteDao(this._db);

  final AppDatabase _db;

  Future<List<ExerciseNote>> getAll() async {
    final rows = await _db.db.rawQuery(_joinedSelect);
    return rows.map(exerciseNoteFromJoinedRow).toList();
  }

  Future<List<ExerciseNote>> getForVisit(String visitId) async {
    final rows = await _db.db.rawQuery(
      '$_joinedSelect WHERE workout_visits.visit_id = ?',
      [visitId],
    );
    return rows.map(exerciseNoteFromJoinedRow).toList();
  }

  Future<int?> _localVisitId(String visitId) async {
    final rows = await _db.db.query(
      'workout_visits',
      columns: ['id'],
      where: 'visit_id = ?',
      whereArgs: [visitId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int;
  }

  /// Replaces any existing note for the same (visit, exercise, set index).
  Future<void> upsert(ExerciseNote note) async {
    final localVisitId = await _localVisitId(note.visitId);
    if (localVisitId == null) {
      throw StateError('No local visit found for visitId ${note.visitId}');
    }
    await _db.db.transaction((txn) async {
      await txn.delete(
        'exercise_notes',
        where: note.setIndex == null
            ? 'visit_id = ? AND exercise_name = ? AND set_index IS NULL'
            : 'visit_id = ? AND exercise_name = ? AND set_index = ?',
        whereArgs: note.setIndex == null
            ? [localVisitId, note.exerciseName]
            : [localVisitId, note.exerciseName, note.setIndex],
      );
      await txn.insert(
        'exercise_notes',
        exerciseNoteToRow(note, localVisitId),
      );
    });
  }

  Future<void> deleteForVisitAndExercise(
    String visitId,
    String exerciseName, {
    int? setIndex,
  }) async {
    final localVisitId = await _localVisitId(visitId);
    if (localVisitId == null) return;
    await _db.db.delete(
      'exercise_notes',
      where: setIndex == null
          ? 'visit_id = ? AND exercise_name = ? AND set_index IS NULL'
          : 'visit_id = ? AND exercise_name = ? AND set_index = ?',
      whereArgs: setIndex == null
          ? [localVisitId, exerciseName]
          : [localVisitId, exerciseName, setIndex],
    );
  }
}
