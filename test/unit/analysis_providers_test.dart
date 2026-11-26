import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/models/exercise.dart';
import 'package:gym_tracker/models/history_entry.dart';
import 'package:gym_tracker/models/workout_day_def.dart';
import 'package:gym_tracker/models/workout_defaults.dart';
import 'package:gym_tracker/models/year_sheet_data.dart';
import 'package:gym_tracker/providers/analysis_providers.dart';
import 'package:gym_tracker/services/analysis/stats_engine.dart';

HistoryEntry _entry({required List<String> muscleGroups}) {
  final metaRow = MetaRow(
    rowIndex: 1,
    visitId: 'v1',
    date: DateTime(2026, 1, 1),
    isoWeek: 1,
    isoYear: 2026,
    muscleGroups: muscleGroups,
    exercises: const [],
    sourceTab: '2026',
  );
  return HistoryEntry(
    date: metaRow.date,
    isoWeek: metaRow.isoWeek,
    isoYear: metaRow.isoYear,
    exerciseNames: const [],
    muscleGroups: muscleGroups,
    metaRow: metaRow,
  );
}

void main() {
  group('resolveSetCount', () {
    const defaults = WorkoutDefaults(repRangeLow: 6, repRangeHigh: 8, setCount: 4);

    test('a per-exercise override wins over the global default', () {
      const exercise = Exercise(
        name: 'Bench press',
        muscleGroup: MuscleGroup.upperChest,
        setCount: 5,
      );

      expect(resolveSetCount(exercise: exercise, defaults: defaults), 5);
    });

    test('the global default wins when there is no per-exercise override', () {
      const exercise = Exercise(name: 'Bench press', muscleGroup: MuscleGroup.upperChest);

      expect(resolveSetCount(exercise: exercise, defaults: defaults), 4);
    });
  });

  group('bestMatchingDayForEntry', () {
    final push = WorkoutDayDef(
      id: 'push',
      label: 'Push',
      muscleGroups: const [
        MuscleGroup.triceps,
        MuscleGroup.upperChest,
        MuscleGroup.frontDelt,
      ],
      sheetRowIndex: 0,
    );
    final pull = WorkoutDayDef(
      id: 'pull',
      label: 'Pull',
      muscleGroups: const [
        MuscleGroup.lats,
        MuscleGroup.upperBack,
        MuscleGroup.biceps,
      ],
      sheetRowIndex: 1,
    );

    test('matches a day whose declared groups fully contain the entry', () {
      final entry = _entry(
        muscleGroups: [MuscleGroup.triceps.sheetHeader],
      );

      expect(bestMatchingDayForEntry(entry, [push, pull])?.id, 'push');
    });

    test(
      'still matches the best-overlapping day when one exercise muscle '
      'group is outside every day\'s declared set (overlap fix for the '
      'stale-date bug)',
      () {
        final entry = _entry(
          muscleGroups: [MuscleGroup.triceps.sheetHeader, MuscleGroup.cardio.sheetHeader],
        );

        final result = bestMatchingDayForEntry(entry, [push, pull]);

        expect(result?.id, 'push');
      },
    );

    test('picks the day with the larger overlap, not just any overlap', () {
      final entry = _entry(
        muscleGroups: [
          MuscleGroup.lats.sheetHeader,
          MuscleGroup.upperBack.sheetHeader,
          MuscleGroup.triceps.sheetHeader,
        ],
      );

      final result = bestMatchingDayForEntry(entry, [push, pull]);

      expect(result?.id, 'pull');
    });

    test('returns null when there is no overlap with any day at all', () {
      final entry = _entry(muscleGroups: [MuscleGroup.cardio.sheetHeader]);

      expect(bestMatchingDayForEntry(entry, [push, pull]), isNull);
    });

    test(
      'an exact overlap+muscle-count tie resolves the same regardless of '
      'input order (independent of the user-controlled day order)',
      () {
        final arms = WorkoutDayDef(
          id: 'arms',
          label: 'Arms',
          muscleGroups: const [MuscleGroup.triceps, MuscleGroup.biceps],
        );
        final shoulders = WorkoutDayDef(
          id: 'shoulders',
          label: 'Shoulders',
          muscleGroups: const [MuscleGroup.triceps, MuscleGroup.frontDelt],
        );
        final entry = _entry(muscleGroups: [MuscleGroup.triceps.sheetHeader]);

        final forward = bestMatchingDayForEntry(entry, [arms, shoulders]);
        final reversed = bestMatchingDayForEntry(entry, [shoulders, arms]);

        expect(forward?.id, reversed?.id);
        expect(forward?.id, 'arms');
      },
    );
  });

  group('estimatedCaloriesBurned', () {
    test('scales with totalReps and totalSets, not time', () {
      final low = estimatedCaloriesBurned(
        bodyWeightKg: 70,
        totalReps: 10,
        totalSets: 2,
      );
      final high = estimatedCaloriesBurned(
        bodyWeightKg: 70,
        totalReps: 50,
        totalSets: 10,
      );

      expect(high, greaterThan(low));
    });

    test('scales with bodyWeightKg against the 70kg reference', () {
      final reference = estimatedCaloriesBurned(
        bodyWeightKg: 70,
        totalReps: 20,
        totalSets: 4,
      );
      final heavier = estimatedCaloriesBurned(
        bodyWeightKg: 140,
        totalReps: 20,
        totalSets: 4,
      );

      expect(heavier, closeTo(reference * 2, 1e-9));
    });

    test('is zero with no reps and no sets regardless of body weight', () {
      expect(
        estimatedCaloriesBurned(
          bodyWeightKg: 90,
          totalReps: 0,
          totalSets: 0,
        ),
        0,
      );
    });
  });
}
