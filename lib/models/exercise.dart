import '../core/constants/muscle_groups.dart';

class Exercise {
  const Exercise({
    required this.name,
    required this.muscleGroup,
    this.sheetRow,
    this.muscleGroupKnown = true,
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

  Exercise copyWith({int? sheetRow}) => Exercise(
    name: name,
    muscleGroup: muscleGroup,
    sheetRow: sheetRow ?? this.sheetRow,
    muscleGroupKnown: muscleGroupKnown,
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
