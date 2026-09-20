import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/models/analysis_result.dart';
import 'package:gym_tracker/models/exercise.dart';
import 'package:gym_tracker/models/exercise_unit.dart';
import 'package:gym_tracker/models/set_feedback.dart';
import 'package:gym_tracker/services/analysis/analysis_engine.dart';

HistoryPoint _point({
  required int week,
  required double weight,
  int repLow = 6,
  int repHigh = 8,
  double? rating,
  int thumbsUp = 0,
  int thumbsDown = 0,
  int? totalSets,
  double? avgReps,
  List<int>? actualRepsPerSet,
  List<double>? actualWeightsPerSet,
  List<SetFeedback>? perSetFeedback,
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
    totalSets: totalSets ?? actualRepsPerSet?.length,
    avgReps:
        avgReps ??
        (actualRepsPerSet == null
            ? null
            : actualRepsPerSet.reduce((a, b) => a + b) /
                  actualRepsPerSet.length),
    actualRepsPerSet: actualRepsPerSet ?? const [],
    actualWeightsPerSet: actualWeightsPerSet ?? const [],
    perSetFeedback: perSetFeedback ?? const [],
  );
}

void main() {
  const engine = AnalysisEngine();

  test('returns null with fewer than minHistoryPoints', () {
    final history = [_point(week: 1, weight: 50), _point(week: 2, weight: 52)];
    final finding = engine.analyze(
      subjectName: 'Bench press',
      history: history,
      alternativeExercises: const [],
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
      alternativeExercises: const [],
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
      alternativeExercises: const [
        Exercise(
          name: 'Dumbbell shoulder press',
          muscleGroup: MuscleGroup.frontDelt,
        ),
      ],
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
        alternativeExercises: const [],
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
        alternativeExercises: const [],
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
        alternativeExercises: const [],
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
        alternativeExercises: const [],
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
        alternativeExercises: const [],
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
        alternativeExercises: const [],
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
      alternativeExercises: const [],
      recentlySuggestedAlternatives: const {},
    );
    expect(finding, isNotNull);
    expect(finding!.suggestion, contains('deload'));
  });

  group('ExerciseUnit.bodyweight', () {
    test(
      'flat/zero added weight with climbing volume is NOT flagged as a plateau',
      () {
        final history = [
          for (var i = 1; i <= 6; i++)
            _point(week: i, weight: 0, totalSets: 3 + i, avgReps: 8),
        ];
        final finding = engine.analyze(
          subjectName: 'Pull-ups',
          history: history,
          alternativeExercises: const [],
          recentlySuggestedAlternatives: const {},
          unit: ExerciseUnit.bodyweight,
        );
        expect(finding, isNotNull);
        expect(finding!.isPlateaued, isFalse);
        expect(finding.weightTrend, TrendDirection.up);
      },
    );

    test(
      'flat added weight AND flat volume for 4+ sessions IS a plateau',
      () {
        final history = [
          _point(week: 1, weight: 0, totalSets: 3, avgReps: 8),
          _point(week: 2, weight: 0, totalSets: 3, avgReps: 9), // peak volume
          _point(week: 3, weight: 0, totalSets: 3, avgReps: 8),
          _point(week: 4, weight: 0, totalSets: 3, avgReps: 8),
          _point(week: 5, weight: 0, totalSets: 3, avgReps: 8),
          _point(week: 6, weight: 0, totalSets: 3, avgReps: 8),
        ];
        final finding = engine.analyze(
          subjectName: 'Pull-ups',
          history: history,
          alternativeExercises: const [],
          recentlySuggestedAlternatives: const {},
          unit: ExerciseUnit.bodyweight,
        );
        expect(finding, isNotNull);
        expect(finding!.isPlateaued, isTrue);
      },
    );

    test('a plain kg exercise is unaffected by the bodyweight branch', () {
      final history = [
        for (var i = 1; i <= 6; i++)
          _point(week: i, weight: 50 + i * 5.0, rating: 4),
      ];
      final finding = engine.analyze(
        subjectName: 'Squat',
        history: history,
        alternativeExercises: const [],
        recentlySuggestedAlternatives: const {},
      );
      expect(finding, isNotNull);
      expect(finding!.weightTrend, TrendDirection.up);
      expect(finding.isPlateaued, isFalse);
    });
  });

  group('per-set weak-set detection', () {
    test(
      'a set trailing below the rep-range floor suggests changeWeightForSet',
      () {
        final history = [
          for (var i = 1; i <= 6; i++)
            _point(
              week: i,
              weight: 50,
              actualRepsPerSet: const [7, 7, 3],
              actualWeightsPerSet: const [50, 50, 50],
            ),
        ];
        final finding = engine.analyze(
          subjectName: 'Bench press',
          history: history,
          alternativeExercises: const [],
          recentlySuggestedAlternatives: const {},
        );
        expect(finding, isNotNull);
        expect(finding!.kind, SuggestionKind.changeWeightForSet);
        final payload = finding.payload as WeightSuggestionPayload;
        expect(payload.setIndex, 2);
        expect(payload.newWeight, closeTo(46.0, 0.01));
      },
    );

    test(
      'a set trailing but still within range suggests changeRepRangeForSet',
      () {
        final history = [
          for (var i = 1; i <= 6; i++)
            _point(week: i, weight: 50, actualRepsPerSet: const [9, 9, 6]),
        ];
        final finding = engine.analyze(
          subjectName: 'Bench press',
          history: history,
          alternativeExercises: const [],
          recentlySuggestedAlternatives: const {},
        );
        expect(finding, isNotNull);
        expect(finding!.kind, SuggestionKind.changeRepRangeForSet);
        final payload = finding.payload as RepRangeSuggestionPayload;
        expect(payload.setIndex, 2);
        expect(payload.newLow, 5);
        expect(payload.newHigh, 7);
      },
    );

    test('fewer than 3 sessions with per-set data does not flag a weak set', () {
      final history = [
        _point(week: 1, weight: 50),
        _point(week: 2, weight: 50),
        _point(week: 3, weight: 50),
        _point(week: 4, weight: 50, actualRepsPerSet: const [7, 7, 3]),
        _point(week: 5, weight: 50, actualRepsPerSet: const [7, 7, 3]),
      ];
      final finding = engine.analyze(
        subjectName: 'Bench press',
        history: history,
        alternativeExercises: const [],
        recentlySuggestedAlternatives: const {},
      );
      expect(finding, isNotNull);
      expect(finding!.kind, isNot(SuggestionKind.changeWeightForSet));
      expect(finding.kind, isNot(SuggestionKind.changeRepRangeForSet));
    });

    test('only one set logged does not flag a weak set', () {
      final history = [
        for (var i = 1; i <= 6; i++)
          _point(week: i, weight: 50, actualRepsPerSet: const [7]),
      ];
      final finding = engine.analyze(
        subjectName: 'Bench press',
        history: history,
        alternativeExercises: const [],
        recentlySuggestedAlternatives: const {},
      );
      expect(finding, isNotNull);
      expect(finding!.kind, isNot(SuggestionKind.changeWeightForSet));
      expect(finding.kind, isNot(SuggestionKind.changeRepRangeForSet));
    });

    test(
      'bad feedback alone (no rep deficit) is enough to flag a set',
      () {
        final history = [
          for (var i = 1; i <= 6; i++)
            _point(
              week: i,
              weight: 50,
              actualRepsPerSet: const [7, 7, 7],
              perSetFeedback: i >= 3
                  ? const [SetFeedback.none, SetFeedback.none, SetFeedback.down]
                  : const [],
            ),
        ];
        final finding = engine.analyze(
          subjectName: 'Bench press',
          history: history,
          alternativeExercises: const [],
          recentlySuggestedAlternatives: const {},
        );
        expect(finding, isNotNull);
        expect(finding!.kind, SuggestionKind.changeRepRangeForSet);
        final payload = finding.payload as RepRangeSuggestionPayload;
        expect(payload.setIndex, 2);
      },
    );
  });

  group('changeTotalWeight', () {
    test(
      'every set hitting the top of its rep range suggests a weight increase',
      () {
        final history = [
          _point(week: 1, weight: 50),
          _point(week: 2, weight: 55),
          _point(week: 3, weight: 60),
          _point(week: 4, weight: 65, actualRepsPerSet: const [9, 9, 9]),
          _point(week: 5, weight: 70, actualRepsPerSet: const [9, 9, 9]),
          _point(week: 6, weight: 75, actualRepsPerSet: const [9, 9, 9]),
        ];
        final finding = engine.analyze(
          subjectName: 'Squat',
          history: history,
          alternativeExercises: const [],
          recentlySuggestedAlternatives: const {},
        );
        expect(finding, isNotNull);
        expect(finding!.kind, SuggestionKind.changeTotalWeight);
        final payload = finding.payload as WeightSuggestionPayload;
        expect(payload.newWeight, closeTo(77.5, 0.01));
      },
    );

    test('is skipped for bodyweight exercises', () {
      final history = [
        _point(week: 1, weight: 0, actualRepsPerSet: const [9, 9]),
        _point(week: 2, weight: 0, actualRepsPerSet: const [9, 9]),
        _point(week: 3, weight: 0, actualRepsPerSet: const [9, 9]),
        _point(week: 4, weight: 0, actualRepsPerSet: const [9, 9]),
        _point(week: 5, weight: 0, actualRepsPerSet: const [10, 10]),
        _point(week: 6, weight: 0, actualRepsPerSet: const [10, 10]),
      ];
      final finding = engine.analyze(
        subjectName: 'Pull-ups',
        history: history,
        alternativeExercises: const [],
        recentlySuggestedAlternatives: const {},
        unit: ExerciseUnit.bodyweight,
      );
      expect(finding, isNotNull);
      expect(finding!.kind, isNot(SuggestionKind.changeTotalWeight));
    });
  });

  group('recentlySuggestedKinds variety', () {
    List<HistoryPoint> stuckHistory() => [
      for (var i = 1; i <= 6; i++)
        _point(week: i, weight: 50, actualRepsPerSet: const [7, 7, 3]),
    ];

    test('falls through to the next kind when the first is on cooldown', () {
      final finding = engine.analyze(
        subjectName: 'Bench press',
        history: stuckHistory(),
        alternativeExercises: const [],
        recentlySuggestedAlternatives: const {},
        recentlySuggestedKinds: const {SuggestionKind.changeWeightForSet},
      );
      expect(finding, isNotNull);
      expect(finding!.kind, SuggestionKind.changeRepRangeOverall);
    });

    test('falls back to a plain message once every kind is on cooldown', () {
      final finding = engine.analyze(
        subjectName: 'Bench press',
        history: stuckHistory(),
        alternativeExercises: const [],
        recentlySuggestedAlternatives: const {},
        recentlySuggestedKinds: const {
          SuggestionKind.changeWeightForSet,
          SuggestionKind.changeRepRangeOverall,
          SuggestionKind.changeExercise,
        },
      );
      expect(finding, isNotNull);
      expect(finding!.kind, SuggestionKind.none);
      expect(finding.payload, isNull);
    });
  });
}
