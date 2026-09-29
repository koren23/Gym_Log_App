import 'package:flutter/material.dart';

import '../../core/constants/muscle_groups.dart';
import '../../core/utils/text.dart';
import '../../models/exercise.dart';
import '../../models/exercise_muscle_info.dart';
import '../../models/exercise_unit.dart';
import '../../widgets/delete_exercise_confirmation.dart';

/// Result of the add-exercise dialog: either an add/edit ([exercise] set) —
/// carrying the target "Exercises" tab muscle-column index, if known, for
/// wherever [exercise]'s current muscle group should live — or a delete
/// ([deleted] true, [exercise] null). Cancel resolves the whole future to
/// `null` instead.
typedef NewExerciseResult = ({
  Exercise? exercise,
  int? muscleColumnIndex,
  bool deleted,
});

/// Shows the add-exercise dialog, or — when [existing] is given — the same
/// dialog pre-filled for editing that exercise's name, muscle, and unit,
/// plus a "Delete exercise" action (gated behind
/// [showDeleteExerciseConfirmation]).
Future<NewExerciseResult?> showAddNewExerciseDialog(
  BuildContext context, {
  required List<MuscleGroup> muscleGroupOptions,
  required List<ExerciseMuscleInfo> allMuscleInfo,
  Exercise? existing,
}) {
  final isEditing = existing != null;
  final controller = TextEditingController(text: existing?.name ?? '');
  final customLabelController = TextEditingController(
    text: existing?.customUnitLabel ?? '',
  );
  // Always ask which muscle a new exercise belongs to — a day can span
  // several muscle groups (e.g. a custom "Push" day spans chest/shoulders/
  // triceps), so silently filing everything under the first one is wrong.
  var selectedGroup = existing?.muscleGroup ?? muscleGroupOptions.first;
  var selectedUnit = existing?.unit ?? ExerciseUnit.kg;
  return showDialog<NewExerciseResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final customLabelBlank =
            selectedUnit == ExerciseUnit.custom &&
            customLabelController.text.trim().isEmpty;
        return AlertDialog(
          title: Text(isEditing ? 'Edit exercise' : 'New exercise'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: !isEditing,
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
              const SizedBox(height: 16),
              SegmentedButton<ExerciseUnit>(
                segments: const [
                  ButtonSegment(value: ExerciseUnit.kg, label: Text('kg')),
                  ButtonSegment(
                    value: ExerciseUnit.bodyweight,
                    label: Text('Bodyweight'),
                  ),
                  ButtonSegment(value: ExerciseUnit.time, label: Text('Time')),
                  ButtonSegment(
                    value: ExerciseUnit.custom,
                    label: Text('Custom'),
                  ),
                ],
                selected: {selectedUnit},
                onSelectionChanged: (s) =>
                    setState(() => selectedUnit = s.first),
              ),
              if (selectedUnit == ExerciseUnit.custom) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: customLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Custom unit (e.g. floors)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
          actions: [
            if (isEditing)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () async {
                  final confirmed = await showDeleteExerciseConfirmation(
                    context,
                    existing.name,
                  );
                  if (confirmed && context.mounted) {
                    Navigator.of(context).pop((
                      exercise: null,
                      muscleColumnIndex: null,
                      deleted: true,
                    ));
                  }
                },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty || customLabelBlank
                  ? null
                  : () {
                      final name = controller.text.trim();
                      final customLabel =
                          selectedUnit == ExerciseUnit.custom
                              ? customLabelController.text.trim()
                              : null;
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
                          unit: selectedUnit,
                          customUnitLabel: customLabel,
                        ),
                        muscleColumnIndex: columnIndex,
                        deleted: false,
                      ));
                    },
              child: Text(isEditing ? 'Save' : 'Add'),
            ),
          ],
        );
      },
    ),
  );
}
