import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/models/analysis_result.dart';
import 'package:gym_tracker/models/workout_day_def.dart';
import 'package:gym_tracker/services/analysis/workout_day_analyzer.dart';

void main() {
  const analyzer = WorkoutDayAnalyzer();
  final day = WorkoutDayDef(
    id: 'push',
    label: 'Push',
    muscleGroups: const [MuscleGroup.upperChest, MuscleGroup.triceps],
  );

  AnalysisFinding stuckFinding(String name, {SuggestionKind kind = SuggestionKind.changeExercise}) =>
      AnalysisFinding(
        subjectName: name,
        weightTrend: TrendDirection.flat,
        ratingTrend: TrendDirection.flat,
        isPlateaued: true,
        repRangeChanged: true,
        message: '$name is stuck.',
        kind: kind,
      );

  AnalysisFinding healthyFinding(String name) => AnalysisFinding(
    subjectName: name,
    weightTrend: TrendDirection.up,
    ratingTrend: TrendDirection.flat,
    isPlateaued: false,
    repRangeChanged: false,
    message: '$name is improving.',
  );

  test('fires when 3+ exercises are stuck and each already has its own remedy', () {
    final finding = analyzer.analyze(
      day: day,
      exerciseFindings: [
        stuckFinding('Bench press'),
        stuckFinding('Incline press'),
        stuckFinding('Dips'),
        healthyFinding('Cable flyes'),
      ],
    );
    expect(finding, isNotNull);
    expect(finding!.kind, SuggestionKind.changeWorkoutDay);
    expect(
      (finding.payload as WorkoutDaySuggestionPayload).dayId,
      'push',
    );
  });

  test('does not fire below the stuck-count/fraction threshold', () {
    final finding = analyzer.analyze(
      day: day,
      exerciseFindings: [
        stuckFinding('Bench press'),
        healthyFinding('Incline press'),
        healthyFinding('Dips'),
      ],
    );
    expect(finding, isNull);
  });

  test(
    'does not fire if any stuck exercise has no remedy of its own yet '
    '(kind == none)',
    () {
      final finding = analyzer.analyze(
        day: day,
        exerciseFindings: [
          stuckFinding('Bench press'),
          stuckFinding('Incline press'),
          stuckFinding('Dips', kind: SuggestionKind.none),
        ],
      );
      expect(finding, isNull);
    },
  );

  test('fires on a high stuck fraction even with fewer than 3 exercises', () {
    final finding = analyzer.analyze(
      day: day,
      exerciseFindings: [stuckFinding('Bench press'), stuckFinding('Dips')],
    );
    expect(finding, isNotNull);
  });

  test('returns null for an empty findings list', () {
    expect(analyzer.analyze(day: day, exerciseFindings: const []), isNull);
  });
}
