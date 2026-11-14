import '../../core/constants/muscle_groups.dart';
import '../../models/workout_day_def.dart';

WorkoutDayDef workoutDayDefFromRow(Map<String, Object?> row) => WorkoutDayDef(
  id: row['id'] as String,
  label: row['label'] as String,
  muscleGroups: _parseMuscleList(row['muscle_groups'] as String? ?? ''),
  legacyDay: _parseLegacyDay(row['legacy_day'] as String?),
  sheetRowIndex: row['sheet_row_index'] as int?,
);

Map<String, Object?> workoutDayDefToRow(WorkoutDayDef day) => {
  'id': day.id,
  'label': day.label,
  'muscle_groups': day.muscleGroups.map((g) => g.name).join(','),
  'legacy_day': day.legacyDay?.name,
  'sheet_row_index': day.sheetRowIndex,
};

List<MuscleGroup> _parseMuscleList(String raw) {
  if (raw.trim().isEmpty) return const [];
  return [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) MuscleGroup.values.byName(part.trim()),
  ];
}

WorkoutDay? _parseLegacyDay(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return WorkoutDay.values.byName(raw);
}
