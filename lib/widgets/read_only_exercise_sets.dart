import 'package:flutter/material.dart';

import '../core/utils/exercise_value_format.dart';
import '../models/exercise_unit.dart';
import '../models/set_feedback.dart';
import '../models/year_sheet_data.dart';

/// Read-only rendering of one previously-logged exercise's sets — reused by
/// [LastWorkoutInsightScreen]'s full workout preview. Sourced directly from
/// [LoggedExerciseRepRange], which already carries per-set actual
/// reps/weights/approx/feedback. [unit]/[customUnitLabel] describe the unit
/// those weights are in (resolved by the caller, since this model only
/// carries the exercise's name, not the full [Exercise] object).
class ReadOnlyExerciseSets extends StatelessWidget {
  const ReadOnlyExerciseSets({
    super.key,
    required this.exercise,
    this.unit = ExerciseUnit.kg,
    this.customUnitLabel,
  });

  final LoggedExerciseRepRange exercise;
  final ExerciseUnit unit;
  final String? customUnitLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setCount = exercise.setCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercise.exerciseName,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (setCount == null)
            Text(
              '${exercise.repRangeLow}-${exercise.repRangeHigh} reps '
              '(no per-set detail logged)',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (var i = 0; i < setCount; i++)
                  _SetChip(
                    weight: exercise.actualWeights.length > i
                        ? exercise.actualWeights[i]
                        : null,
                    reps: exercise.actualReps[i],
                    approx: exercise.isApprox(i),
                    feedback: exercise.feedbackFor(i),
                    unit: unit,
                    customUnitLabel: customUnitLabel,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SetChip extends StatelessWidget {
  const _SetChip({
    required this.weight,
    required this.reps,
    required this.approx,
    required this.feedback,
    this.unit = ExerciseUnit.kg,
    this.customUnitLabel,
  });

  final double? weight;
  final int reps;
  final bool approx;
  final SetFeedback feedback;
  final ExerciseUnit unit;
  final String? customUnitLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weightLabel = weight == null
        ? '?'
        : formatExerciseValue(unit, weight!, customLabel: customUnitLabel);
    final label = '$weightLabel×${approx ? '~' : ''}$reps';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        if (feedback == SetFeedback.up)
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(Icons.thumb_up, size: 12, color: Colors.green),
          )
        else if (feedback == SetFeedback.down)
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(Icons.thumb_down, size: 12, color: Colors.redAccent),
          ),
      ],
    );
  }
}
