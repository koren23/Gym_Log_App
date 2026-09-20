import 'analysis_result.dart';

/// A record of a suggestion that was actually shown to the user (recorded
/// at display time, not whenever the engine happens to compute one) — used
/// to compute a per-kind cooldown so the same suggestion doesn't repeat
/// every single session. See `AppSettingsService.recentSuggestions`/
/// `recordSuggestionShown`.
class RecentSuggestionRecord {
  const RecentSuggestionRecord({
    required this.kind,
    required this.subjectName,
    this.detail,
    required this.shownAt,
  });

  final SuggestionKind kind;
  final String subjectName;

  /// Extra disambiguating detail — e.g. the replacement exercise name for
  /// [SuggestionKind.changeExercise]. Null for exercise-wide kinds.
  final String? detail;
  final DateTime shownAt;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'subjectName': subjectName,
    'detail': detail,
    'shownAt': shownAt.toIso8601String(),
  };

  factory RecentSuggestionRecord.fromJson(Map<String, dynamic> json) =>
      RecentSuggestionRecord(
        kind: SuggestionKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => SuggestionKind.none,
        ),
        subjectName: json['subjectName'] as String,
        detail: json['detail'] as String?,
        shownAt: DateTime.parse(json['shownAt'] as String),
      );
}
