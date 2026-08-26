/// User-configurable rep-range default applied when starting a brand-new
/// exercise entry in the log-workout flow (see Settings > Defaults). Set
/// count is no longer a global default — it's computed per exercise from
/// its own logging history (see `historicalAverageSetCount`).
class WorkoutDefaults {
  const WorkoutDefaults({required this.repRangeLow, required this.repRangeHigh});

  final int repRangeLow;
  final int repRangeHigh;

  WorkoutDefaults copyWith({int? repRangeLow, int? repRangeHigh}) {
    return WorkoutDefaults(
      repRangeLow: repRangeLow ?? this.repRangeLow,
      repRangeHigh: repRangeHigh ?? this.repRangeHigh,
    );
  }
}
