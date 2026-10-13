import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/models/exercise.dart';
import 'package:gym_tracker/screens/log_workout/log_workout_screen.dart';
import 'package:gym_tracker/widgets/exercise_tile.dart';

void main() {
  group('completedRowSetsSummary', () {
    test('formats each set as weight×reps', () {
      final draft = ExerciseDraft(
        const Exercise(name: 'Bench', muscleGroup: MuscleGroup.upperChest),
        setCount: 2,
      );
      draft.setWeights[0] = 50;
      draft.setReps[0] = 8;
      draft.setWeights[1] = 55;
      draft.setReps[1] = 6;

      expect(completedRowSetsSummary(draft), '50.0kg×8, 55.0kg×6');
    });

    test(
      'renders a null weight as "?" instead of crashing on a mid-edit clear',
      () {
        final draft = ExerciseDraft(
          const Exercise(name: 'Bench', muscleGroup: MuscleGroup.upperChest),
          setCount: 2,
        );
        draft.setWeights[0] = 50;
        draft.setReps[0] = 8;
        // Simulates the field being cleared mid-edit, before blur refreshes
        // the "completed" snapshot that gates this row's visibility.
        draft.setWeights[1] = null;
        draft.setReps[1] = 6;

        expect(completedRowSetsSummary(draft), '50.0kg×8, ?×6');
      },
    );

    test('marks an approximate rep count with a leading ~', () {
      final draft = ExerciseDraft(
        const Exercise(name: 'Bench', muscleGroup: MuscleGroup.upperChest),
        setCount: 1,
      );
      draft.setWeights[0] = 50;
      draft.setReps[0] = 8;
      draft.setApproxReps[0] = true;

      expect(completedRowSetsSummary(draft), '50.0kg×~8');
    });
  });
}
