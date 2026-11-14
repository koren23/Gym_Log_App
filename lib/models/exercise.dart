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
    this.secondaryMuscleGroups = const [],
    this.notes,
    this.photoAssetKey,
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

  /// Additional muscles this exercise also works, beyond [muscleGroup]
  /// (the primary) — each counts at half weight toward muscle-balance
  /// aggregation. Empty for most exercises.
  final List<MuscleGroup> secondaryMuscleGroups;

  /// Free-form user- or seed-provided notes about this exercise (form cues,
  /// machine settings, etc.) — editable from Settings, shown read-only in
  /// the log-workout screen. Null for most exercises until set.
  final String? notes;

  /// Either a bundled asset path under `assets/exercise_photos/` (seeded
  /// starter exercises) or an on-device file path (user-picked via
  /// Settings) — the display widget tells which by checking whether the
  /// file exists on disk, falling back to asset lookup otherwise. Null if
  /// no photo has been set.
  final String? photoAssetKey;

  Exercise copyWith({
    int? sheetRow,
    ExerciseUnit? unit,
    String? customUnitLabel,
    List<MuscleGroup>? secondaryMuscleGroups,
    String? notes,
    bool clearNotes = false,
    String? photoAssetKey,
    bool clearPhotoAssetKey = false,
  }) => Exercise(
    name: name,
    muscleGroup: muscleGroup,
    sheetRow: sheetRow ?? this.sheetRow,
    muscleGroupKnown: muscleGroupKnown,
    unit: unit ?? this.unit,
    customUnitLabel: customUnitLabel ?? this.customUnitLabel,
    secondaryMuscleGroups: secondaryMuscleGroups ?? this.secondaryMuscleGroups,
    notes: clearNotes ? null : (notes ?? this.notes),
    photoAssetKey: clearPhotoAssetKey
        ? null
        : (photoAssetKey ?? this.photoAssetKey),
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
