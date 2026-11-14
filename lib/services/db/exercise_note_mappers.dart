import '../../models/exercise_note.dart';

/// Expects a row joined against `workout_visits` so the stable string
/// `visit_id` (UUID) is available as `visit_uuid` — `exercise_notes.visit_id`
/// itself is an INTEGER FK to `workout_visits.id`, not the UUID.
ExerciseNote exerciseNoteFromJoinedRow(Map<String, Object?> row) =>
    ExerciseNote(
      visitId: row['visit_uuid'] as String,
      exerciseName: row['exercise_name'] as String,
      setIndex: row['set_index'] as int?,
      text: row['text'] as String,
      rowIndex: row['sheet_row_index'] as int?,
    );

Map<String, Object?> exerciseNoteToRow(ExerciseNote note, int localVisitId) => {
  'visit_id': localVisitId,
  'exercise_name': note.exerciseName,
  'set_index': note.setIndex,
  'text': note.text,
  'sheet_row_index': note.rowIndex,
};
