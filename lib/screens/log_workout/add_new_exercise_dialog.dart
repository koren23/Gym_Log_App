import 'package:flutter/material.dart';

import '../../core/constants/muscle_groups.dart';
import '../../core/utils/text.dart';
import '../../models/exercise.dart';
import '../../models/exercise_muscle_info.dart';

/// Result of the add-exercise dialog: the new [Exercise] plus, if an
/// existing "Exercises" tab column for its muscle is known, the column
/// index it should be appended to.
typedef NewExerciseResult = ({Exercise exercise, int? muscleColumnIndex});

Future<NewExerciseResult?> showAddNewExerciseDialog(
  BuildContext context, {
  required List<MuscleGroup> muscleGroupOptions,
  required List<ExerciseMuscleInfo> allMuscleInfo,
}) {
  final controller = TextEditingController();
  // Always ask which muscle a new exercise belongs to — a day can span
  // several muscle groups (e.g. a custom "Push" day spans chest/shoulders/
  // triceps), so silently filing everything under the first one is wrong.
  var selectedGroup = muscleGroupOptions.first;
  return showDialog<NewExerciseResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text('New exercise'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Exercise name'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<MuscleGroup>(
                initialValue: selectedGroup,
                decoration: const InputDecoration(labelText: 'Muscle'),
                items: [
                  for (final group in muscleGroupOptions)
                    DropdownMenuItem(
                      value: group,
                      child: Text(titleCase(group.sheetHeader)),
                    ),
                ],
                onChanged: (v) => setState(() => selectedGroup = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () {
                      final name = controller.text.trim();
                      int? columnIndex;
                      for (final info in allMuscleInfo) {
                        if (info.muscleGroup == selectedGroup) {
                          columnIndex = info.columnIndex;
                          break;
                        }
                      }
                      Navigator.of(context).pop((
                        exercise: Exercise(
                          name: name,
                          muscleGroup: selectedGroup,
                        ),
                        muscleColumnIndex: columnIndex,
                      ));
                    },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ),
  );
}
