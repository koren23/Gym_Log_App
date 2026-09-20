import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/core/constants/sheet_layout.dart';
import 'package:gym_tracker/models/exercise_unit.dart';
import 'package:gym_tracker/models/year_sheet_data.dart';
import 'package:gym_tracker/services/sheets/sheet_parser.dart';

void main() {
  const parser = SheetParser();

  group('detectMatrixFormat', () {
    test('a tab using exact current-muscle headers is currentGrouped', () {
      final rows = [
        ['exercise name', '30'],
        ['quads'],
        ['Barbell squats', '100'],
        ['hamstrings'],
        ['Barbell RDL', '80'],
      ];
      expect(parser.detectMatrixFormat(rows), MatrixTabFormat.currentGrouped);
    });

    test(
      'a tab using known alias spellings ("front delts" etc.) is still currentGrouped',
      () {
        final rows = [
          ['exercise name', '30'],
          ['front delts'],
          ['Cable front raises', '20'],
        ];
        expect(
          parser.detectMatrixFormat(rows),
          MatrixTabFormat.currentGrouped,
        );
      },
    );

    test('a tab mixing legacy and current headers stays legacyGrouped', () {
      final rows = [
        ['exercise name', '30'],
        ['Push'],
        ['Barbell bench press', '60'],
        ['quads'],
        ['Barbell squats', '100'],
      ];
      expect(parser.detectMatrixFormat(rows), MatrixTabFormat.legacyGrouped);
    });

    test('a tab with no section headers at all is flatV2', () {
      final rows = [
        ['exercise name', '30'],
        ['Barbell squats', '100'],
        ['Barbell RDL', '80'],
      ];
      expect(parser.detectMatrixFormat(rows), MatrixTabFormat.flatV2);
    });

    test(
      'a current-format tab whose headers happen to include "triceps"/'
      '"biceps" (identical to legacy header text) is still currentGrouped, '
      'not misdetected as legacyGrouped',
      () {
        final rows = [
          ['exercise name', '30'],
          ['lower chest'],
          ['Barbell bench press', '80'],
          ['triceps'],
          ['Cable tricep extension', '25'],
          ['biceps'],
          ['Dumbbell preacher curl', '15'],
        ];
        expect(
          parser.detectMatrixFormat(rows),
          MatrixTabFormat.currentGrouped,
        );
      },
    );
  });

  group('parseMatrixTab (currentGrouped)', () {
    test('files exercises under the right MuscleGroup by exact header text', () {
      final rows = [
        ['exercise name', '30'],
        ['quads'],
        ['Barbell squats', '100'],
        ['hamstrings'],
        ['Barbell RDL', '80'],
      ];
      final data = parser.parseMatrixTab(tabName: '2026', year: 2026, rows: rows);

      expect(data.format, MatrixTabFormat.currentGrouped);
      expect(
        data.muscleGroupSections[MuscleGroup.quads]!.map((e) => e.name),
        ['Barbell squats'],
      );
      expect(
        data.muscleGroupSections[MuscleGroup.hamstrings]!.map((e) => e.name),
        ['Barbell RDL'],
      );
    });

    test(
      'all 4 known alias spellings resolve to their canonical MuscleGroup',
      () {
        final rows = [
          ['exercise name', '30'],
          ['front delts'],
          ['Cable front raises', '20'],
          ['lateral delts'],
          ['Dumbbell lateral raises', '10'],
          ['abs'],
          ['Cable crunches', '30'],
          ['hams'],
          ['Barbell RDL', '80'],
        ];
        final data = parser.parseMatrixTab(
          tabName: '2026',
          year: 2026,
          rows: rows,
        );

        expect(data.format, MatrixTabFormat.currentGrouped);
        expect(
          data.muscleGroupSections[MuscleGroup.frontDelt]!.map((e) => e.name),
          ['Cable front raises'],
        );
        expect(
          data.muscleGroupSections[MuscleGroup.lateralDelt]!.map(
            (e) => e.name,
          ),
          ['Dumbbell lateral raises'],
        );
        expect(
          data.muscleGroupSections[MuscleGroup.abdominals]!.map(
            (e) => e.name,
          ),
          ['Cable crunches'],
        );
        expect(
          data.muscleGroupSections[MuscleGroup.hamstrings]!.map(
            (e) => e.name,
          ),
          ['Barbell RDL'],
        );
      },
    );

    test(
      'sectionHeaderRows/primaryGroupHeaderRow are populated for current headers',
      () {
        final rows = [
          ['exercise name', '30'],
          ['quads'],
          ['Barbell squats', '100'],
        ];
        final data = parser.parseMatrixTab(
          tabName: '2026',
          year: 2026,
          rows: rows,
        );

        expect(data.sectionHeaderRows[MuscleGroup.quads], 1);
        expect(data.primaryGroupHeaderRow[MuscleGroup.quads], 1);
      },
    );

    test(
      'files "triceps"/"biceps" sections under the current MuscleGroup, not '
      'the identically-spelled legacy one',
      () {
        final rows = [
          ['exercise name', '30'],
          ['lower chest'],
          ['Barbell bench press', '80'],
          ['triceps'],
          ['Cable tricep extension', '25'],
          ['biceps'],
          ['Dumbbell preacher curl', '15'],
        ];
        final data = parser.parseMatrixTab(
          tabName: '2026',
          year: 2026,
          rows: rows,
        );

        expect(data.format, MatrixTabFormat.currentGrouped);
        expect(
          data.muscleGroupSections[MuscleGroup.triceps]!.map((e) => e.name),
          ['Cable tricep extension'],
        );
        expect(
          data.muscleGroupSections[MuscleGroup.biceps]!.map((e) => e.name),
          ['Dumbbell preacher curl'],
        );
        expect(data.muscleGroupSections[MuscleGroup.legacyTriceps], isEmpty);
        expect(data.muscleGroupSections[MuscleGroup.legacyBiceps], isEmpty);
      },
    );
  });

  group('parseMatrixTab zero-value convention', () {
    test(
      'a "0" cell is dropped for a plain kg exercise but kept for a bodyweight one',
      () {
        final rows = [
          ['exercise name', '30'],
          ['quads'],
          ['Barbell squats', '0'],
          ['upper back'],
          ['Pull-ups', '0'],
        ];
        final data = parser.parseMatrixTab(
          tabName: '2026',
          year: 2026,
          rows: rows,
          exerciseUnitOverrides: {
            'pull-ups': (unit: ExerciseUnit.bodyweight, customLabel: null),
          },
        );

        final squats = data.muscleGroupSections[MuscleGroup.quads]!.first;
        final pullUps = data.muscleGroupSections[MuscleGroup.upperBack]!.first;
        expect(data.cellValues[CellKey(squats.sheetRow!, 1)], isNull);
        expect(data.cellValues[CellKey(pullUps.sheetRow!, 1)], 0.0);
      },
    );

    test('flatV2: same rule applies with no section headers at all', () {
      final rows = [
        ['exercise name', '30'],
        ['Barbell squats', '0'],
        ['Pull-ups', '0'],
      ];
      final data = parser.parseMatrixTab(
        tabName: '2026',
        year: 2026,
        rows: rows,
        exerciseUnitOverrides: {
          'pull-ups': (unit: ExerciseUnit.bodyweight, customLabel: null),
        },
      );

      expect(data.format, MatrixTabFormat.flatV2);
      final squats = data.allExercises.firstWhere((e) => e.name == 'Barbell squats');
      final pullUps = data.allExercises.firstWhere((e) => e.name == 'Pull-ups');
      expect(data.cellValues[CellKey(squats.sheetRow!, 1)], isNull);
      expect(data.cellValues[CellKey(pullUps.sheetRow!, 1)], 0.0);
    });
  });

  group('parseWorkoutDaysTab', () {
    test(
      'restores legacyDay for the seeded push/pull/legs ids, and leaves it '
      'null for a genuine custom id',
      () {
        final rows = [
          ['id', 'label', 'muscleGroups'],
          ['push', 'Push', 'upperChest,triceps'],
          ['pull', 'Pull', 'lats,biceps'],
          ['legs', 'Legs', 'quads,glutes'],
          ['1700000000000', 'Arms', 'biceps,triceps'],
        ];
        final defs = parser.parseWorkoutDaysTab(rows);

        expect(defs.firstWhere((d) => d.id == 'push').legacyDay, WorkoutDay.push);
        expect(defs.firstWhere((d) => d.id == 'pull').legacyDay, WorkoutDay.pull);
        expect(defs.firstWhere((d) => d.id == 'legs').legacyDay, WorkoutDay.legs);
        expect(
          defs.firstWhere((d) => d.id == '1700000000000').legacyDay,
          isNull,
        );
      },
    );
  });
}
