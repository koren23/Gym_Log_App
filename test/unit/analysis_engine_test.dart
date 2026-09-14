import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/models/analysis_result.dart';
import 'package:gym_tracker/services/analysis/analysis_engine.dart';

HistoryPoint _point({
  required int week,
  required double weight,
  int repLow = 6,
  int repHigh = 8,
  double? rating,
  int thumbsUp = 0,
  int thumbsDown = 0,
}) {
  return HistoryPoint(
    isoYear: 2026,
    isoWeek: week,
    date: DateTime.utc(2026, 1, 1).add(Duration(days: 7 * week)),
    avgWeight: weight,
    repRangeLow: repLow,
    repRangeHigh: repHigh,
    rating: rating,
    thumbsUpCount: thumbsUp,
    thumbsDownCount: thumbsDown,
  );
}

void main() {
  const engine = AnalysisEngine();

  test('returns null with fewer than minHistoryPoints', () {
    final history = [_point(week: 1, weight: 50), _point(week: 2, weight: 52)];
    final finding = engine.analyze(
      subjectName: 'Bench press',
      history: history,
      alternativeExerciseNames: const [],
      recentlySuggestedAlternatives: const {},
    );
    expect(finding, isNull);
  });

  test('detects a clear upward trend as not plateaued', () {
    final history = [
      for (var i = 1; i <= 6; i++)
        _point(week: i, weight: 50 + i * 5.0, rating: 4),
    ];
    final finding = engine.analyze(
      subjectName: 'Squat',
      history: history,
      alternativeExerciseNames: const [],
      recentlySuggestedAlternatives: const {},
    );
    expect(finding, isNotNull);
    expect(finding!.weightTrend, TrendDirection.up);
    expect(finding.isPlateaued, isFalse);
  });

  test('flags a plateau when the last 4 sessions set no new peak', () {
    final history = [
      _point(week: 1, weight: 60),
      _point(week: 2, weight: 65),
      _point(week: 3, weight: 70, rating: 3), // peak
      _point(week: 4, weight: 68, rating: 3),
      _point(week: 5, weight: 69, rating: 2.5),
      _point(week: 6, weight: 70, rating: 2.5),
      _point(week: 7, weight: 69, rating: 2),
    ];
    final finding = engine.analyze(
      subjectName: 'Overhead press',
      history: history,
      alternativeExerciseNames: const ['Dumbbell shoulder press'],
      recentlySuggestedAlternatives: const {},
    );
    expect(finding, isNotNull);
    expect(finding!.isPlateaued, isTrue);
    expect(finding.suggestion, isNotNull);
  });

  test(
    'a plateau is still flagged as stuck even when ratings are trending up',
    () {
      // Regression case: a real plateau shouldn't be masked into a false
      // "trending up" note just because ratings happen to be improving —
      // "stuck on weight" and "ratings improving" aren't mutually exclusive.
      final history = [
        _point(week: 1, weight: 60, rating: 3),
        _point(week: 2, weight: 65, rating: 3),
        _point(week: 3, weight: 70, rating: 3), // peak
        _point(week: 4, weight: 68, rating: 4),
        _point(week: 5, weight: 69, rating: 4.5),
        _point(week: 6, weight: 70, rating: 5),
        _point(week: 7, weight: 69, rating: 5),
      ];
      final finding = engine.analyze(
        subjectName: 'Overhead press',
        history: history,
        alternativeExerciseNames: const [],
        recentlySuggestedAlternatives: const {},
      );
      expect(finding, isNotNull);
      expect(finding!.isPlateaued, isTrue);
    },
  );

  test(
    'a declining rating alone (weight still climbing) is flagged, not just weight plateaus',
    () {
      final history = [
        _point(week: 1, weight: 55, rating: 5),
        _point(week: 2, weight: 60, rating: 4.5),
        _point(week: 3, weight: 65, rating: 4),
        _point(week: 4, weight: 70, rating: 4),
        _point(week: 5, weight: 75, rating: 3),
        _point(week: 6, weight: 80, rating: 2),
      ];
      final finding = engine.analyze(
        subjectName: 'Squat',
        history: history,
        alternativeExerciseNames: const [],
        recentlySuggestedAlternatives: const {},
      );
      expect(finding, isNotNull);
      expect(finding!.weightTrend, TrendDirection.up); // weight itself is fine
      expect(finding.isPlateaued, isTrue); // but still surfaced as a concern
      expect(finding.message, contains('ratings'));
    },
  );

  test(
    'a flat/slightly-down weight is not flagged as stuck when body weight is trending down',
    () {
      final history = [
        _point(week: 1, weight: 70, rating: 4),
        _point(week: 2, weight: 70, rating: 4),
        _point(week: 3, weight: 71, rating: 4), // peak
        _point(week: 4, weight: 70, rating: 4),
        _point(week: 5, weight: 69, rating: 4),
        _point(week: 6, weight: 70, rating: 4),
        _point(week: 7, weight: 69, rating: 4),
      ];
      final finding = engine.analyze(
        subjectName: 'Bench press',
        history: history,
        alternativeExerciseNames: const [],
        recentlySuggestedAlternatives: const {},
        bodyWeightTrend: TrendDirection.down,
      );
      expect(finding, isNotNull);
      expect(finding!.isPlateaued, isFalse);
      expect(finding.message, contains('cut'));
    },
  );

  test(
    'the same plateau IS flagged when body weight is steady, not trending down',
    () {
      final history = [
        _point(week: 1, weight: 70, rating: 4),
        _point(week: 2, weight: 70, rating: 4),
        _point(week: 3, weight: 71, rating: 4), // peak
        _point(week: 4, weight: 70, rating: 4),
        _point(week: 5, weight: 69, rating: 4),
        _point(week: 6, weight: 70, rating: 4),
        _point(week: 7, weight: 69, rating: 4),
      ];
      final finding = engine.analyze(
        subjectName: 'Bench press',
        history: history,
        alternativeExerciseNames: const [],
        recentlySuggestedAlternatives: const {},
        bodyWeightTrend: TrendDirection.flat,
      );
      expect(finding, isNotNull);
      expect(finding!.isPlateaued, isTrue);
    },
  );

  test(
    'a net-positive recent thumbs signal downgrades a raw weight plateau',
    () {
      final history = [
        _point(week: 1, weight: 60),
        _point(week: 2, weight: 65),
        _point(week: 3, weight: 70), // peak
        _point(week: 4, weight: 68, thumbsUp: 1),
        _point(week: 5, weight: 69, thumbsUp: 1),
        _point(week: 6, weight: 70),
        _point(week: 7, weight: 69),
      ];
      final finding = engine.analyze(
        subjectName: 'Overhead press',
        history: history,
        alternativeExerciseNames: const [],
        recentlySuggestedAlternatives: const {},
      );
      expect(finding, isNotNull);
      expect(finding!.isPlateaued, isFalse);
      expect(finding.message, contains('felt strong'));
    },
  );

  test(
    'a cluster of recent thumbs-down sets (no ratings at all) still suggests a deload',
    () {
      final history = [
        _point(week: 1, weight: 60),
        _point(week: 2, weight: 65),
        _point(week: 3, weight: 70), // peak
        _point(week: 4, weight: 68),
        _point(week: 5, weight: 69, thumbsDown: 1),
        _point(week: 6, weight: 70, thumbsDown: 1),
        _point(week: 7, weight: 69, thumbsDown: 1),
      ];
      final finding = engine.analyze(
        subjectName: 'Deadlift',
        history: history,
        alternativeExerciseNames: const [],
        recentlySuggestedAlternatives: const {},
      );
      expect(finding, isNotNull);
      expect(finding!.isPlateaued, isTrue);
      expect(finding.suggestion, contains('deload'));
    },
  );

  test('suggests a deload when plateaued and ratings are very low', () {
    final history = [
      _point(week: 1, weight: 70, rating: 1.5),
      _point(week: 2, weight: 72, rating: 1),
      _point(week: 3, weight: 74, rating: 1.5), // peak
      _point(week: 4, weight: 73, rating: 1),
      _point(week: 5, weight: 73, rating: 1),
      _point(week: 6, weight: 73, rating: 1),
      _point(week: 7, weight: 73, rating: 1),
    ];
    final finding = engine.analyze(
      subjectName: 'Deadlift',
      history: history,
      alternativeExerciseNames: const [],
      recentlySuggestedAlternatives: const {},
    );
    expect(finding, isNotNull);
    expect(finding!.suggestion, contains('deload'));
  });
}
