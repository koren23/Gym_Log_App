import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/models/exercise.dart';
import 'package:gym_tracker/models/set_feedback.dart';
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

  test('setFeedback defaults to none for every set, and toEntry carries it through', () {
    final draft = ExerciseDraft(
      Exercise(name: 'Bench press', muscleGroup: MuscleGroup.upperChest),
    );
    draft.setWeights = [60, 60, 62.5];
    draft.setReps = [8, 6, 10];

    expect(draft.setFeedback, [
      SetFeedback.none,
      SetFeedback.none,
      SetFeedback.none,
    ]);

    draft.setFeedback[1] = SetFeedback.up;
    final entry = draft.toEntry();

    expect(entry!.sets.map((s) => s.feedback), [
      SetFeedback.none,
      SetFeedback.up,
      SetFeedback.none,
    ]);
  });

  test('addSet/removeLastSet keep setFeedback in sync with setWeights', () {
    final draft = ExerciseDraft(
      Exercise(name: 'Bench press', muscleGroup: MuscleGroup.upperChest),
    );
    final initialLength = draft.setWeights.length;

    draft.addSet();
    expect(draft.setFeedback.length, initialLength + 1);
    expect(draft.setFeedback.last, SetFeedback.none);

    draft.removeLastSet();
    expect(draft.setFeedback.length, initialLength);
  });

  test('loadSets restores setFeedback, defaulting to none when omitted', () {
    final draft = ExerciseDraft(
      Exercise(name: 'Bench press', muscleGroup: MuscleGroup.upperChest),
    );
    draft.loadSets(
      weights: [60.0, 62.5],
      reps: [8, 6],
      setFeedback: [SetFeedback.down, SetFeedback.none],
    );
    expect(draft.setFeedback, [SetFeedback.down, SetFeedback.none]);

    draft.loadSets(weights: [60.0], reps: [8]);
    expect(draft.setFeedback, [SetFeedback.none]);
  });

  group('ExerciseDraft.completedNamesFrom', () {
    ExerciseDraft completeDraft() {
      final draft = ExerciseDraft(
        Exercise(name: 'Bench press', muscleGroup: MuscleGroup.upperChest),
      );
      draft.setWeights = [60];
      return draft;
    }

    ExerciseDraft incompleteDraft() {
      final draft = ExerciseDraft(
        Exercise(name: 'Squat', muscleGroup: MuscleGroup.quads),
      );
      draft.setWeights = [null];
      return draft;
    }

    test('preserves the order of names from checked', () {
      final drafts = {'Squat': completeDraft(), 'Bench press': completeDraft()};
      final result = ExerciseDraft.completedNamesFrom(
        ['Bench press', 'Squat'],
        drafts,
      );
      expect(result, ['Bench press', 'Squat']);
    });

    test('excludes names with no draft entry', () {
      final drafts = {'Bench press': completeDraft()};
      final result = ExerciseDraft.completedNamesFrom(
        ['Bench press', 'Ghost exercise'],
        drafts,
      );
      expect(result, ['Bench press']);
    });

    test('excludes checked names whose draft is not complete', () {
      final drafts = {
        'Bench press': completeDraft(),
        'Squat': incompleteDraft(),
      };
      final result = ExerciseDraft.completedNamesFrom(
        ['Bench press', 'Squat'],
        drafts,
      );
      expect(result, ['Bench press']);
    });

    test('a weight-only-filled draft counts as complete', () {
      final drafts = {'Bench press': completeDraft()};
      final result = ExerciseDraft.completedNamesFrom(['Bench press'], drafts);
      expect(result, ['Bench press']);
    });
  });
}
