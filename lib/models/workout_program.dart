import '../core/constants/sheet_layout.dart';

/// One exercise entry within a [WorkoutProgram]: what it is, how many sets,
/// and the target rep range -- no weight (that's decided live from history
/// when logging).
class ProgramExercise {
  const ProgramExercise({
    required this.name,
    this.sets = kDefaultSetCount,
    this.repRangeLow = kDefaultRepRangeLow,
    this.repRangeHigh = kDefaultRepRangeHigh,
  });

  final String name;
  final int sets;
  final int repRangeLow;
  final int repRangeHigh;

  ProgramExercise copyWith({int? sets, int? repRangeLow, int? repRangeHigh}) =>
      ProgramExercise(
        name: name,
        sets: sets ?? this.sets,
        repRangeLow: repRangeLow ?? this.repRangeLow,
        repRangeHigh: repRangeHigh ?? this.repRangeHigh,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'sets': sets,
    'repRangeLow': repRangeLow,
    'repRangeHigh': repRangeHigh,
  };

  factory ProgramExercise.fromJson(Map<String, dynamic> json) =>
      ProgramExercise(
        name: json['name'] as String,
        sets: json['sets'] as int? ?? kDefaultSetCount,
        repRangeLow: json['repRangeLow'] as int? ?? kDefaultRepRangeLow,
        repRangeHigh: json['repRangeHigh'] as int? ?? kDefaultRepRangeHigh,
      );
}

/// The user's planned workout for a day (see `WorkoutDayDef`) -- the
/// authoritative target for which exercises, how many sets, and what rep
/// range, used to seed the log page's checklist/order/targets and combined
/// with logged history to drive suggestions. At most one per [dayId] --
/// [dayId] is this program's key, mirroring how `WorkoutDayDef.id` keys a
/// day.
class WorkoutProgram {
  const WorkoutProgram({
    required this.dayId,
    required this.name,
    required this.exercises,
    this.sheetRowIndex,
  });

  /// The [WorkoutDayDef.id] this program belongs to.
  final String dayId;

  /// User-facing name for this program (free text, e.g. "Legs -- Heavy").
  final String name;

  /// Ordered exercises making up this program.
  final List<ProgramExercise> exercises;

  /// 0-based row index within the `PremadeWorkouts` sheet tab this was
  /// parsed from -- null if not yet confirmed synced to the sheet (a
  /// locally pending add). The sheet tab itself keeps its original name so
  /// existing synced data isn't orphaned; only the Dart-side naming changed.
  final int? sheetRowIndex;

  /// Convenience for callers that only need ordered exercise names (e.g.
  /// checklist/order suggestion logic).
  List<String> get exerciseNames => exercises.map((e) => e.name).toList();

  ProgramExercise? exerciseNamed(String name) {
    for (final e in exercises) {
      if (e.name == name) return e;
    }
    return null;
  }

  WorkoutProgram copyWith({
    String? name,
    List<ProgramExercise>? exercises,
    int? sheetRowIndex,
  }) => WorkoutProgram(
    dayId: dayId,
    name: name ?? this.name,
    exercises: exercises ?? this.exercises,
    sheetRowIndex: sheetRowIndex ?? this.sheetRowIndex,
  );

  Map<String, dynamic> toJson() => {
    'dayId': dayId,
    'name': name,
    'exercises': [for (final e in exercises) e.toJson()],
  };

  /// Handles [json] from a queued offline-sync item written before this
  /// per-exercise-detail redesign (old shape: `exerciseNames: List<String>`,
  /// no `exercises` key) as a bare-name list, same defaults as the sheet
  /// parser's legacy-token fallback.
  factory WorkoutProgram.fromJson(Map<String, dynamic> json) => WorkoutProgram(
    dayId: json['dayId'] as String,
    name: json['name'] as String,
    exercises: json.containsKey('exercises')
        ? [
            for (final e in (json['exercises'] as List))
              ProgramExercise.fromJson(e as Map<String, dynamic>),
          ]
        : [
            for (final n in (json['exerciseNames'] as List).cast<String>())
              ProgramExercise(name: n),
          ],
  );
}
