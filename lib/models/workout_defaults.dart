/// User-configurable rep-range/set-count default applied when starting a
/// brand-new exercise entry in the log-workout flow, for any exercise that
/// has no per-exercise override of its own (see Settings > Default rep
/// range & set count).
class WorkoutDefaults {
  const WorkoutDefaults({
    required this.repRangeLow,
    required this.repRangeHigh,
    required this.setCount,
  });

  final int repRangeLow;
  final int repRangeHigh;
  final int setCount;

  WorkoutDefaults copyWith({int? repRangeLow, int? repRangeHigh, int? setCount}) {
    return WorkoutDefaults(
      repRangeLow: repRangeLow ?? this.repRangeLow,
      repRangeHigh: repRangeHigh ?? this.repRangeHigh,
      setCount: setCount ?? this.setCount,
    );
  }
}
