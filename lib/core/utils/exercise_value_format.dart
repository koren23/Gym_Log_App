import '../../models/exercise_unit.dart';

/// Formats a logged value for display according to its exercise's [unit],
/// e.g. `80.0kg` / `BW` / `+10.0kg` / `45sec` / `12 floors`. The single
/// place every "Set N", "Average", "Last time" style label should go
/// through, so a unit only needs its display rule written once.
String formatExerciseValue(
  ExerciseUnit unit,
  double value, {
  String? customLabel,
}) {
  switch (unit) {
    case ExerciseUnit.kg:
      return '${value.toStringAsFixed(1)}kg';
    case ExerciseUnit.bodyweight:
      return value == 0 ? 'BW' : '+${value.toStringAsFixed(1)}kg';
    case ExerciseUnit.time:
      return '${_trimTrailingZero(value)}sec';
    case ExerciseUnit.custom:
      return '${_trimTrailingZero(value)} ${customLabel ?? 'unit'}';
  }
}

/// `45.0` -> `'45'`, `12.5` -> `'12.5'`.
String _trimTrailingZero(double value) =>
    value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
