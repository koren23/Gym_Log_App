import '../core/constants/muscle_groups.dart';
import 'exercise_unit.dart';

class Exercise {
  const Exercise({
    required this.name,
    required this.muscleGroup,
    this.sheetRow,
    this.muscleGroupKnown = true,
    this.unit = ExerciseUnit.kg,
    this.customUnitLabel,
  });

  final String name;
  final MuscleGroup muscleGroup;

  /// 0-based row index within the year matrix tab this exercise was parsed
  /// from. Null if this exercise hasn't been written to the sheet yet.
  final int? sheetRow;

  /// False when [muscleGroup] is only a placeholder because this exercise
  /// (from a [MatrixTabFormat.flatV2] tab) couldn't be resolved against the
  /// "Exercises" reference tab or any legacy year — e.g. it was typed
  /// directly into the sheet and never given a muscle. The UI should offer
  /// a way to set the real muscle rather than trusting [muscleGroup].
  final bool muscleGroupKnown;

  /// What a logged value for this exercise means — see [ExerciseUnit].
  /// Defaults to plain [ExerciseUnit.kg], including for every exercise that
  /// predates this feature (no sheet migration needed).
  final ExerciseUnit unit;

  /// User-chosen label when [unit] is [ExerciseUnit.custom] (e.g. "floors").
  /// Null for every other unit.
  final String? customUnitLabel;

  Exercise copyWith({
    int? sheetRow,
    ExerciseUnit? unit,
    String? customUnitLabel,
  }) => Exercise(
    name: name,
    muscleGroup: muscleGroup,
    sheetRow: sheetRow ?? this.sheetRow,
    muscleGroupKnown: muscleGroupKnown,
    unit: unit ?? this.unit,
    customUnitLabel: customUnitLabel ?? this.customUnitLabel,
  );

  @override
  bool operator ==(Object other) =>
      other is Exercise &&
      other.name == name &&
      other.muscleGroup == muscleGroup;

  @override
  int get hashCode => Object.hash(name, muscleGroup);

  @override
  String toString() => 'Exercise($name, ${muscleGroup.sheetHeader})';
}
