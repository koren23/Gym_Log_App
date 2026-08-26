import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/models/exercise.dart';
import 'package:gym_tracker/widgets/exercise_tile.dart';

void main() {
  test(
    'toEntry derives the target rep range from the min/max of actual reps entered',
    () {
      final draft = ExerciseDraft(
        Exercise(name: 'Bench press', muscleGroup: MuscleGroup.upperChest),
      );
      draft.setWeights = [60, 60, 62.5];
      draft.setReps = [8, 6, 10];
      draft.setApproxReps = [false, false, false];

      final entry = draft.toEntry();

      expect(entry, isNotNull);
      expect(entry!.targetRepRangeLow, 6);
      expect(entry.targetRepRangeHigh, 10);
      expect(entry.sets.map((s) => s.reps), [8, 6, 10]);
    },
  );

  test('a single set derives low == high', () {
    final draft = ExerciseDraft(
      Exercise(name: 'Bench press', muscleGroup: MuscleGroup.upperChest),
    );
    draft.setWeights = [60];
    draft.setReps = [8];
    draft.setApproxReps = [false];

    final entry = draft.toEntry();

    expect(entry!.targetRepRangeLow, 8);
    expect(entry.targetRepRangeHigh, 8);
  });

  test('a blank reps field falls back to the default midpoint, not null', () {
    final draft = ExerciseDraft(
      Exercise(name: 'Bench press', muscleGroup: MuscleGroup.upperChest),
    );
    draft.setWeights = [60];
    draft.setReps = [null];
    draft.setApproxReps = [false];

    final entry = draft.toEntry();

    expect(
      entry!.sets.single.reps,
      7,
    ); // (kDefaultRepRangeLow + kDefaultRepRangeHigh) ~/ 2
  });

  test('loadSets replaces set data and rebuilds controllers to match', () {
    final draft = ExerciseDraft(
      Exercise(name: 'Bench press', muscleGroup: MuscleGroup.upperChest),
    );
    draft.loadSets(
      weights: [60.0, 62.5],
      reps: [8, 6],
      approxReps: [false, true],
    );

    expect(draft.setWeights, [60.0, 62.5]);
    expect(draft.setReps, [8, 6]);
    expect(draft.setApproxReps, [false, true]);
    expect(draft.weightControllers.map((c) => c.text), ['60.0', '62.5']);
    expect(draft.repsControllers.map((c) => c.text), ['8', '6']);
  });
}
