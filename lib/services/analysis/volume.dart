import '../../models/year_sheet_data.dart';

/// Which of [instanceVolume]'s two computations produced a given volume —
/// the two aren't on a perfectly comparable scale (see [VolumeResult]), so
/// callers computing a %-change between two instances of the same exercise
/// should treat a [exact]-vs-[proxy] transition differently than a
/// same-method one.
enum VolumeMethod { exact, proxy }

class VolumeResult {
  const VolumeResult(this.volume, this.method);
  final double volume;
  final VolumeMethod method;
}

/// Total work performed in one logged instance of an exercise, plus which
/// method produced it — see [instanceVolume].
VolumeResult? instanceVolumeDetailed(
  LoggedExerciseRepRange range, {
  double? matrixCellWeight,
}) {
  if (range.actualWeights.isNotEmpty &&
      range.actualWeights.length == range.actualReps.length) {
    var total = 0.0;
    for (var i = 0; i < range.actualReps.length; i++) {
      total += range.actualWeights[i] * range.actualReps[i];
    }
    return VolumeResult(total, VolumeMethod.exact);
  }

  final avgReps = range.avgReps;
  final setCount = range.setCount;
  if (avgReps != null && setCount != null && matrixCellWeight != null) {
    return VolumeResult(matrixCellWeight * avgReps * setCount, VolumeMethod.proxy);
  }
  return null;
}

/// Total work performed in one logged instance of an exercise — prefers the
/// true per-set sum (Σ weight×reps) when both per-set arrays are populated
/// and the same length; falls back to the coarser avg-weight × avg-reps ×
/// set-count proxy (via [matrixCellWeight], the visit's averaged matrix-tab
/// cell) for a visit logged before per-set tracking existed; null when
/// neither is computable.
double? instanceVolume(
  LoggedExerciseRepRange range, {
  double? matrixCellWeight,
}) => instanceVolumeDetailed(range, matrixCellWeight: matrixCellWeight)?.volume;
