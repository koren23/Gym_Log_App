import '../core/constants/muscle_groups.dart';
import 'exercise.dart';
import 'rating_relevance.dart';

class SetEntry {
  const SetEntry({
    required this.weight,
    required this.reps,
    this.approxReps = false,
  });

  final double weight;
  final int reps;

  /// True when the user marked this set's rep count as approximate
  /// (e.g. "~8" — not precisely counted) rather than an exact number.
  final bool approxReps;

  Map<String, dynamic> toJson() => {
    'weight': weight,
    'reps': reps,
    'approxReps': approxReps,
  };

  factory SetEntry.fromJson(Map<String, dynamic> json) => SetEntry(
    weight: (json['weight'] as num).toDouble(),
    reps: json['reps'] as int,
    approxReps: json['approxReps'] as bool? ?? false,
  );
}

class ExerciseEntry {
  const ExerciseEntry({
    required this.exercise,
    required this.sets,
    required this.targetRepRangeLow,
    required this.targetRepRangeHigh,
  });

  final Exercise exercise;
  final List<SetEntry> sets;
  final int targetRepRangeLow;
  final int targetRepRangeHigh;

  double get averageWeight {
    if (sets.isEmpty) return 0;
    final total = sets.fold<double>(0, (sum, s) => sum + s.weight);
    return total / sets.length;
  }

  Map<String, dynamic> toJson() => {
    'exerciseName': exercise.name,
    'muscleGroup': exercise.muscleGroup.name,
    'sets': sets.map((s) => s.toJson()).toList(),
    'targetRepRangeLow': targetRepRangeLow,
    'targetRepRangeHigh': targetRepRangeHigh,
  };

  factory ExerciseEntry.fromJson(Map<String, dynamic> json) => ExerciseEntry(
    exercise: Exercise(
      name: json['exerciseName'] as String,
      muscleGroup: MuscleGroup.values.firstWhere(
        (g) => g.name == json['muscleGroup'],
      ),
    ),
    sets: (json['sets'] as List)
        .map((s) => SetEntry.fromJson(s as Map<String, dynamic>))
        .toList(),
    targetRepRangeLow: json['targetRepRangeLow'] as int,
    targetRepRangeHigh: json['targetRepRangeHigh'] as int,
  );
}

/// A single gym visit (e.g. one push-day session). May cover exercises from
/// multiple muscle groups if the user logs them together.
class WorkoutVisit {
  const WorkoutVisit({
    required this.visitId,
    required this.date,
    required this.isoWeek,
    required this.isoYear,
    required this.entries,
    this.rating,
    this.ratingRelevance = RatingRelevance.normal,
    this.sourceTab,
    this.note,
  });

  final String visitId;
  final DateTime date;
  final int isoWeek;
  final int isoYear;
  final List<ExerciseEntry> entries;
  final double? rating;

  /// How much [rating] should count toward trend analysis — see
  /// [RatingRelevance].
  final RatingRelevance ratingRelevance;

  /// Name of the year matrix tab this visit's cell data was written to
  /// (matters when a year has overflowed into `<year>_2`, `<year>_3`, ...).
  final String? sourceTab;

  /// Free-text note for this visit (meta-tab column J).
  final String? note;

  WorkoutVisit copyWith({
    double? rating,
    RatingRelevance? ratingRelevance,
    String? sourceTab,
    String? note,
  }) => WorkoutVisit(
    visitId: visitId,
    date: date,
    isoWeek: isoWeek,
    isoYear: isoYear,
    entries: entries,
    rating: rating ?? this.rating,
    ratingRelevance: ratingRelevance ?? this.ratingRelevance,
    sourceTab: sourceTab ?? this.sourceTab,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'visitId': visitId,
    'date': date.toIso8601String(),
    'isoWeek': isoWeek,
    'isoYear': isoYear,
    'entries': entries.map((e) => e.toJson()).toList(),
    'rating': rating,
    'ratingRelevance': ratingRelevance.name,
    'sourceTab': sourceTab,
    'note': note,
  };

  factory WorkoutVisit.fromJson(Map<String, dynamic> json) => WorkoutVisit(
    visitId: json['visitId'] as String,
    date: DateTime.parse(json['date'] as String),
    isoWeek: json['isoWeek'] as int,
    isoYear: json['isoYear'] as int,
    entries: (json['entries'] as List)
        .map((e) => ExerciseEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    rating: (json['rating'] as num?)?.toDouble(),
    ratingRelevance: RatingRelevance.values.firstWhere(
      (r) => r.name == json['ratingRelevance'],
      orElse: () => RatingRelevance.normal,
    ),
    sourceTab: json['sourceTab'] as String?,
    note: json['note'] as String?,
  );
}
