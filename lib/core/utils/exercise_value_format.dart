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

/// Formats a list of per-set values as one space-joined string with the
/// unit appended once at the end, e.g. `50 70 80kg` — used for the "Last
/// time" hint, which shows what was actually done set by set rather than
/// a single pre-averaged number. Returns `''` for an empty list.
String formatExerciseValuesPerSet(
  ExerciseUnit unit,
  List<double> values, {
  String? customLabel,
}) {
  if (values.isEmpty) return '';
  switch (unit) {
    case ExerciseUnit.kg:
      return '${values.map(_trimTrailingZero).join(' ')}kg';
    case ExerciseUnit.bodyweight:
      // Each set may or may not have added weight on top of bodyweight, so
      // (unlike the other units) the sign/unit stays per-value rather than
      // collapsing to one trailing suffix, e.g. `BW +10.0kg BW`.
      return values
          .map((v) => v == 0 ? 'BW' : '+${v.toStringAsFixed(1)}kg')
          .join(' ');
    case ExerciseUnit.time:
      return '${values.map(_trimTrailingZero).join(' ')}sec';
    case ExerciseUnit.custom:
      return '${values.map(_trimTrailingZero).join(' ')} ${customLabel ?? 'unit'}';
  }
}

/// `45.0` -> `'45'`, `12.5` -> `'12.5'`.
String _trimTrailingZero(double value) =>
    value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
