import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/models/workout_day_def.dart';

void main() {
  group('mergeDuplicateWorkoutDays', () {
    test('passes through a list with no duplicate ids unchanged', () {
      final a = WorkoutDayDef(
        id: 'a',
        label: 'Push',
        muscleGroups: const [MuscleGroup.triceps],
        sheetRowIndex: 0,
      );
      final b = WorkoutDayDef(
        id: 'b',
        label: 'Pull',
        muscleGroups: const [MuscleGroup.lats],
        sheetRowIndex: 1,
      );
      expect(mergeDuplicateWorkoutDays([a, b]), [a, b]);
    });

    test('unions muscle groups across duplicate rows', () {
      final first = WorkoutDayDef(
        id: 'pull',
        label: 'Pull',
        muscleGroups: const [MuscleGroup.lats, MuscleGroup.upperBack],
        sheetRowIndex: 2,
      );
      final second = WorkoutDayDef(
        id: 'pull',
        label: 'Pull',
        muscleGroups: const [MuscleGroup.rearDelt, MuscleGroup.upperBack],
        sheetRowIndex: 5,
      );

      final merged = mergeDuplicateWorkoutDays([first, second]);

      expect(merged, hasLength(1));
      expect(merged.single.muscleGroups, [
        MuscleGroup.lats,
        MuscleGroup.upperBack,
        MuscleGroup.rearDelt,
      ]);
    });

    test('label comes from the entry with the highest sheetRowIndex', () {
      final older = WorkoutDayDef(
        id: 'pull',
        label: 'Pull (old)',
        muscleGroups: const [MuscleGroup.lats],
        sheetRowIndex: 2,
      );
      final newer = WorkoutDayDef(
        id: 'pull',
        label: 'Pull (new)',
        muscleGroups: const [MuscleGroup.rearDelt],
        sheetRowIndex: 9,
      );

      final merged = mergeDuplicateWorkoutDays([older, newer]);

      expect(merged.single.label, 'Pull (new)');
    });

    test('a pending (null sheetRowIndex) entry outranks every synced row', () {
      final synced = WorkoutDayDef(
        id: 'pull',
        label: 'Pull (synced)',
        muscleGroups: const [MuscleGroup.lats],
        sheetRowIndex: 9,
      );
      final pending = WorkoutDayDef(
        id: 'pull',
        label: 'Pull (pending edit)',
        muscleGroups: const [MuscleGroup.rearDelt],
      );

      final merged = mergeDuplicateWorkoutDays([synced, pending]);

      expect(merged.single.label, 'Pull (pending edit)');
    });

    test('merged sheetRowIndex is the lowest of the group', () {
      final rows = [
        WorkoutDayDef(
          id: 'pull',
          label: 'Pull',
          muscleGroups: const [MuscleGroup.lats],
          sheetRowIndex: 7,
        ),
        WorkoutDayDef(
          id: 'pull',
          label: 'Pull',
          muscleGroups: const [MuscleGroup.rearDelt],
          sheetRowIndex: 2,
        ),
        WorkoutDayDef(
          id: 'pull',
          label: 'Pull',
          muscleGroups: const [MuscleGroup.upperBack],
          sheetRowIndex: 5,
        ),
      ];

      final merged = mergeDuplicateWorkoutDays(rows);

      expect(merged.single.sheetRowIndex, 2);
    });

    test('preserves a legacyDay link from any duplicate in the group', () {
      final withoutLegacy = WorkoutDayDef(
        id: WorkoutDay.pull.name,
        label: 'Pull',
        muscleGroups: const [MuscleGroup.rearDelt],
        sheetRowIndex: 5,
      );
      final withLegacy = WorkoutDayDef(
        id: WorkoutDay.pull.name,
        label: 'Pull',
        muscleGroups: const [MuscleGroup.lats],
        legacyDay: WorkoutDay.pull,
        sheetRowIndex: 1,
      );

      final merged = mergeDuplicateWorkoutDays([withoutLegacy, withLegacy]);

      expect(merged.single.legacyDay, WorkoutDay.pull);
    });

    test('preserves relative order of distinct ids', () {
      final a = WorkoutDayDef(
        id: 'a',
        label: 'A',
        muscleGroups: const [MuscleGroup.lats],
      );
      final b1 = WorkoutDayDef(
        id: 'b',
        label: 'B1',
        muscleGroups: const [MuscleGroup.lats],
        sheetRowIndex: 1,
      );
      final c = WorkoutDayDef(
        id: 'c',
        label: 'C',
        muscleGroups: const [MuscleGroup.lats],
      );
      final b2 = WorkoutDayDef(
        id: 'b',
        label: 'B2',
        muscleGroups: const [MuscleGroup.rearDelt],
        sheetRowIndex: 3,
      );

      final merged = mergeDuplicateWorkoutDays([a, b1, c, b2]);

      expect(merged.map((d) => d.id).toList(), ['a', 'b', 'c']);
    });
  });
}
