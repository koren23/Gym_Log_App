import 'package:flutter/material.dart';

import '../../core/constants/muscle_groups.dart';
import '../../core/utils/text.dart';
import '../../models/workout_day_def.dart';

/// Result of the add-workout-day dialog: a label plus the muscle groups the
/// user picked for it.
typedef NewWorkoutDayResult = ({String label, List<MuscleGroup> muscleGroups});

/// Shows the add/edit workout-day dialog. Pass [existing] to edit an
/// already-defined day (prefills its label/muscles, retitles to "Edit") —
/// omit it to create a new one. Either way the caller decides what to do
/// with the returned label/muscles (append vs. update in place).
Future<NewWorkoutDayResult?> showAddWorkoutDayDialog(
  BuildContext context, {
  WorkoutDayDef? existing,
}) {
  final controller = TextEditingController(text: existing?.label ?? '');
  final selected = <MuscleGroup>{...?existing?.muscleGroups};
  return showDialog<NewWorkoutDayResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text(existing == null ? 'New workout day' : 'Edit workout day'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Day name',
                    hintText: 'e.g. Legs_A, Chest+Back',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                for (final group in kCurrentMuscleGroups)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(titleCase(group.sheetHeader)),
                    value: selected.contains(group),
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        selected.add(group);
                      } else {
                        selected.remove(group);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty || selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop((
                      label: controller.text.trim(),
                      muscleGroups: selected.toList(),
                    )),
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    ),
  );
}
