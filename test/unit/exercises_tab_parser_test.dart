import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/models/exercise_unit.dart';
import 'package:gym_tracker/services/sheets/sheet_parser.dart';

void main() {
  const parser = SheetParser();

  test(
    'parses one column per current muscle group into exercise->muscle rows',
    () {
      final rows = [
        ['upper chest', 'lower chest', 'triceps', 'upper back', 'lats', 'quads'],
        [
          'Incline barbell bench press',
          'Barbell bench press',
          'EZ bar skull crushers',
          'Barbell bent over rows',
          'Lat pulldown',
          'Barbell squats',
        ],
        [
          'Incline dumbbell bench press',
          '',
          '',
          '',
          'Cable seated rows',
          'Leg extension',
        ],
      ];

      final result = parser.parseExercisesTab(rows);

      expect(
        result,
        containsAll([
          predicate<dynamic>(
            (e) =>
                e.exerciseName == 'Incline barbell bench press' &&
                e.muscleGroup == MuscleGroup.upperChest,
          ),
          predicate<dynamic>(
            (e) =>
                e.exerciseName == 'Incline dumbbell bench press' &&
                e.muscleGroup == MuscleGroup.upperChest,
          ),
          predicate<dynamic>(
            (e) =>
                e.exerciseName == 'Barbell bench press' &&
                e.muscleGroup == MuscleGroup.lowerChest,
          ),
          predicate<dynamic>(
            (e) =>
                e.exerciseName == 'Barbell bent over rows' &&
                e.muscleGroup == MuscleGroup.upperBack,
          ),
          predicate<dynamic>(
            (e) =>
                e.exerciseName == 'Cable seated rows' &&
                e.muscleGroup == MuscleGroup.lats,
          ),
          predicate<dynamic>(
            (e) =>
                e.exerciseName == 'Barbell squats' &&
                e.muscleGroup == MuscleGroup.quads,
          ),
          predicate<dynamic>(
            (e) =>
                e.exerciseName == 'Leg extension' &&
                e.muscleGroup == MuscleGroup.quads,
          ),
        ]),
      );

      // Blank cells produce no entries.
      expect(result.where((e) => e.exerciseName.trim().isEmpty), isEmpty);
    },
  );

  test('returns nothing for an empty sheet', () {
    expect(parser.parseExercisesTab([]), isEmpty);
  });

  test('ignores a header cell that matches no current muscle group', () {
    final rows = [
      ['stray header', 'quads'],
      ['should be ignored', 'Barbell squats'],
    ];
    final result = parser.parseExercisesTab(rows);
    expect(result, hasLength(1));
    expect(result.first.exerciseName, 'Barbell squats');
    expect(result.first.muscleGroup, MuscleGroup.quads);
  });

  test('a legacy section-header word (e.g. "Push") does not match', () {
    // "Push" is a legacy matrix-tab section header, not a current muscle —
    // must not be picked up by the Exercises-tab parser.
    final rows = [
      ['Push', 'quads'],
      ['should be ignored', 'Barbell squats'],
    ];
    final result = parser.parseExercisesTab(rows);
    expect(result, hasLength(1));
    expect(result.first.exerciseName, 'Barbell squats');
  });

  group('parseExerciseUnitsTab', () {
    test('returns an empty table for an empty sheet', () {
      final table = parser.parseExerciseUnitsTab([]);
      expect(table.assignments, isEmpty);
      expect(table.exerciseColumnIndex, isNull);
      expect(table.unitColumnIndex, isNull);
    });

    test(
      'returns an empty table (with headerRowLength) when the header pair is missing',
      () {
        final rows = [
          ['upper chest', 'quads'],
          ['Incline bench press', 'Barbell squats'],
        ];
        final table = parser.parseExerciseUnitsTab(rows);
        expect(table.assignments, isEmpty);
        expect(table.exerciseColumnIndex, isNull);
        expect(table.unitColumnIndex, isNull);
        expect(table.headerRowLength, 2);
      },
    );

    test('finds the header pair by case-insensitive text, not position', () {
      final rows = [
        ['upper chest', 'Exercise', 'Unit'],
        ['Incline bench press', 'Pull-ups', 'bw'],
        ['', 'Plank', 'time'],
        ['', 'Stairmaster', 'custom:floors'],
      ];
      final table = parser.parseExerciseUnitsTab(rows);
      expect(table.exerciseColumnIndex, 1);
      expect(table.unitColumnIndex, 2);
      expect(table.assignments['pull-ups']!.unit, ExerciseUnit.bodyweight);
      expect(table.assignments['pull-ups']!.customLabel, isNull);
      expect(table.assignments['pull-ups']!.rowIndex, 1);
      expect(table.assignments['plank']!.unit, ExerciseUnit.time);
      expect(table.assignments['stairmaster']!.unit, ExerciseUnit.custom);
      expect(table.assignments['stairmaster']!.customLabel, 'floors');
    });

    test('a blank/unrecognized unit cell defaults to kg', () {
      final rows = [
        ['Exercise', 'Unit'],
        ['Barbell squats', ''],
        ['Deadlift', 'nonsense'],
      ];
      final table = parser.parseExerciseUnitsTab(rows);
      expect(table.assignments['barbell squats']!.unit, ExerciseUnit.kg);
      expect(table.assignments['deadlift']!.unit, ExerciseUnit.kg);
    });
  });
}
