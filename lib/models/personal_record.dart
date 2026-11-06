/// A personal record the user manually logs — intentionally never
/// auto-detected from logged sets (unlike `PrsByExercise` in
/// `stats_engine.dart`, which still backs the all-time XP total): whether
/// something counts as a PR is the user's call, not a weight/volume
/// comparison.
class PersonalRecord {
  const PersonalRecord({
    required this.id,
    required this.exerciseName,
    required this.date,
    this.weightKg,
    this.volume,
    this.note,
  });

  final String id;
  final String exerciseName;
  final DateTime date;
  final double? weightKg;
  final double? volume;
  final String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseName': exerciseName,
    'date': date.toIso8601String(),
    if (weightKg != null) 'weightKg': weightKg,
    if (volume != null) 'volume': volume,
    if (note != null) 'note': note,
  };

  factory PersonalRecord.fromJson(Map<String, dynamic> json) => PersonalRecord(
    id: json['id'] as String,
    exerciseName: json['exerciseName'] as String,
    date: DateTime.parse(json['date'] as String),
    weightKg: (json['weightKg'] as num?)?.toDouble(),
    volume: (json['volume'] as num?)?.toDouble(),
    note: json['note'] as String?,
  );
}
