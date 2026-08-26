import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/services/sheets/sheet_parser.dart';

void main() {
  const parser = SheetParser();

  List<List<Object?>> rowsWithExercisesCell(String exercisesCell) => [
    [
      'visitId',
      'date',
      'isoWeek',
      'isoYear',
      'muscleGroups',
      'exercises',
      'sourceTab',
      'rating',
    ],
    ['v1', '2026-08-14', '33', '2026', 'Push', exercisesCell, '2026', '4'],
  ];

  test(
    'parses legacy 2-segment cells (name:low-high) with no per-set data',
    () {
      final rows = rowsWithExercisesCell('Bench press:6-8');
      final meta = parser.parseMetaTab(rows);
      final exercise = meta.single.exercises.single;
      expect(exercise.exerciseName, 'Bench press');
      expect(exercise.repRangeLow, 6);
      expect(exercise.repRangeHigh, 8);
      expect(exercise.actualReps, isEmpty);
      expect(exercise.actualWeights, isEmpty);
      expect(exercise.setCount, isNull);
    },
  );

  test(
    'parses 3-segment cells (name:low-high:reps) from before per-set weight tracking',
    () {
      final rows = rowsWithExercisesCell('Bench press:6-8:8,7,6');
      final exercise = parser.parseMetaTab(rows).single.exercises.single;
      expect(exercise.actualReps, [8, 7, 6]);
      expect(exercise.approxReps, [false, false, false]);
      expect(exercise.actualWeights, isEmpty);
      expect(exercise.setCount, 3);
    },
  );

  test(
    'parses 4-segment cells (name:low-high:reps:weights), the current format',
    () {
      final rows = rowsWithExercisesCell('Bench press:6-8:8,7,6:60,60,62.5');
      final exercise = parser.parseMetaTab(rows).single.exercises.single;
      expect(exercise.actualReps, [8, 7, 6]);
      expect(exercise.actualWeights, [60.0, 60.0, 62.5]);
      expect(exercise.setCount, 3);
    },
  );

  test(
    'a leading ~ on a rep token marks that set approximate without breaking parsing',
    () {
      final rows = rowsWithExercisesCell('Bench press:6-8:8,~7,6:60,60,62.5');
      final exercise = parser.parseMetaTab(rows).single.exercises.single;
      expect(exercise.actualReps, [8, 7, 6]);
      expect(exercise.approxReps, [false, true, false]);
      expect(exercise.isApprox(1), isTrue);
      expect(exercise.isApprox(0), isFalse);
    },
  );

  test(
    'multiple pipe-separated exercises with different formats parse independently',
    () {
      final rows = rowsWithExercisesCell(
        'Bench press:6-8:8,7,6:60,60,62.5|Squat:8-10',
      );
      final exercises = parser.parseMetaTab(rows).single.exercises;
      expect(exercises, hasLength(2));
      expect(exercises[0].exerciseName, 'Bench press');
      expect(exercises[0].actualWeights, [60.0, 60.0, 62.5]);
      expect(exercises[1].exerciseName, 'Squat');
      expect(exercises[1].actualReps, isEmpty);
    },
  );
}
