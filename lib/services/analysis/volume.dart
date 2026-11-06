import '../../models/year_sheet_data.dart';

/// Total work performed in one logged instance of an exercise — prefers the
/// true per-set sum (Σ weight×reps) when both per-set arrays are populated
/// and the same length; falls back to the coarser avg-weight × avg-reps ×
/// set-count proxy (via [matrixCellWeight], the visit's averaged matrix-tab
/// cell) for a visit logged before per-set tracking existed; null when
/// neither is computable.
double? instanceVolume(
  LoggedExerciseRepRange range, {
  double? matrixCellWeight,
}) {
  if (range.actualWeights.isNotEmpty &&
      range.actualWeights.length == range.actualReps.length) {
    var total = 0.0;
    for (var i = 0; i < range.actualReps.length; i++) {
      total += range.actualWeights[i] * range.actualReps[i];
    }
    return total;
  }

  final avgReps = range.avgReps;
  final setCount = range.setCount;
  if (avgReps != null && setCount != null && matrixCellWeight != null) {
    return matrixCellWeight * avgReps * setCount;
  }
  return null;
}
