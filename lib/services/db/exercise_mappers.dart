import '../../core/constants/muscle_groups.dart';
import '../../models/exercise.dart';
import '../../models/exercise_unit.dart';

Exercise exerciseFromRow(Map<String, Object?> row) => Exercise(
  name: row['name'] as String,
  muscleGroup: MuscleGroup.values.byName(row['muscle_group'] as String),
  muscleGroupKnown: (row['muscle_group_known'] as int) == 1,
  unit: ExerciseUnit.values.byName(row['unit'] as String),
  customUnitLabel: row['custom_unit_label'] as String?,
  secondaryMuscleGroups: _parseMuscleList(
    row['secondary_muscle_groups'] as String? ?? '',
  ),
  notes: row['notes'] as String?,
  photoAssetKey: row['photo_asset_key'] as String?,
);

Map<String, Object?> exerciseToRow(Exercise exercise) => {
  'name': exercise.name,
  'name_lower': exercise.name.toLowerCase(),
  'muscle_group': exercise.muscleGroup.name,
  'muscle_group_known': exercise.muscleGroupKnown ? 1 : 0,
  'unit': exercise.unit.name,
  'custom_unit_label': exercise.customUnitLabel,
  'secondary_muscle_groups': exercise.secondaryMuscleGroups
      .map((g) => g.name)
      .join(','),
  'notes': exercise.notes,
  'photo_asset_key': exercise.photoAssetKey,
};

List<MuscleGroup> _parseMuscleList(String raw) {
  if (raw.trim().isEmpty) return const [];
  return [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) MuscleGroup.values.byName(part.trim()),
  ];
}
