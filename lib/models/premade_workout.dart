/// A user-editable exercise-list template for a workout day (see
/// `WorkoutDayDef`), used to pre-fill the log page's checklist/order for
/// that day and to remember planned changes even before they're logged.
/// At most one per [dayId] — [dayId] is this template's key, mirroring how
/// `WorkoutDayDef.id` keys a day.
class PremadeWorkout {
  const PremadeWorkout({
    required this.dayId,
    required this.name,
    required this.exerciseNames,
    this.sheetRowIndex,
  });

  /// The [WorkoutDayDef.id] this template belongs to.
  final String dayId;

  /// User-facing name for this template (free text, e.g. "Legs — Heavy").
  final String name;

  /// Ordered exercise names making up this template.
  final List<String> exerciseNames;

  /// 0-based row index within the `PremadeWorkouts` sheet tab this was
  /// parsed from — null if not yet confirmed synced to the sheet (a
  /// locally pending add).
  final int? sheetRowIndex;

  PremadeWorkout copyWith({
    String? name,
    List<String>? exerciseNames,
    int? sheetRowIndex,
  }) => PremadeWorkout(
    dayId: dayId,
    name: name ?? this.name,
    exerciseNames: exerciseNames ?? this.exerciseNames,
    sheetRowIndex: sheetRowIndex ?? this.sheetRowIndex,
  );

  Map<String, dynamic> toJson() => {
    'dayId': dayId,
    'name': name,
    'exerciseNames': exerciseNames,
  };

  factory PremadeWorkout.fromJson(Map<String, dynamic> json) => PremadeWorkout(
    dayId: json['dayId'] as String,
    name: json['name'] as String,
    exerciseNames: (json['exerciseNames'] as List).cast<String>(),
  );
}
