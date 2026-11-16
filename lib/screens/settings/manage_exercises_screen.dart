import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/muscle_groups.dart';
import '../../core/utils/exercise_muscle_resolution.dart';
import '../../core/utils/text.dart';
import '../../models/exercise.dart';
import '../../providers/sheet_data_providers.dart';
import '../../widgets/app_snack_bar.dart';
import '../log_workout/add_new_exercise_dialog.dart';

/// Full list of every exercise known across all loaded years (deduped by
/// name), with tap-to-edit — the only place, going forward, where an
/// exercise's name/muscle/unit/secondary muscles can be changed or the
/// exercise deleted entirely. Replaces the inline edit affordance that used
/// to live on the log page.
class ManageExercisesScreen extends ConsumerWidget {
  const ManageExercisesScreen({super.key});

  Future<void> _editExercise(
    BuildContext context,
    WidgetRef ref,
    Exercise existing,
  ) async {
    final result = await showAddNewExerciseDialog(
      context,
      muscleGroupOptions: kCurrentMuscleGroups,
      existing: existing,
    );
    if (result == null) return;

    if (result.deleted) {
      final ok = await ref
          .read(snapshotProvider.notifier)
          .deleteExercise(existing);
      if (!ok && context.mounted) {
        showAppSnackBar(
          context,
          "Couldn't delete the exercise — check your connection and try again.",
          isError: true,
        );
      }
      return;
    }

    final newExercise = result.exercise!;
    final updateResult = await ref
        .read(snapshotProvider.notifier)
        .updateExercise(oldExercise: existing, newExercise: newExercise);
    if (!updateResult.success && context.mounted) {
      showAppSnackBar(
        context,
        "Couldn't save: ${updateResult.failedSteps.join(', ')} — check your connection and try again.",
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(allKnownExercisesProvider);
    ref.watch(snapshotProvider); // rebuild this screen when a sync completes.

    // Keyed by resolveMuscleGroup's result, not the raw exercise.muscleGroup
    // field — the raw field can hold a pre-2026 legacy value (e.g. "Push",
    // "Pull", "Legs") or be unset, and those aren't real muscle categories.
    // Null means "no resolved muscle" and is grouped under "Uncategorized"
    // instead, where the user can tap in and assign a real one.
    final byMuscle = <MuscleGroup?, List<Exercise>>{};
    for (final exercise in exercises) {
      byMuscle.putIfAbsent(resolveMuscleGroup(exercise), () => []).add(exercise);
    }
    final sortedGroups = byMuscle.keys.toList()
      ..sort((a, b) {
        if (a == null) return b == null ? 0 : 1;
        if (b == null) return -1;
        return a.sheetHeader.compareTo(b.sheetHeader);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Manage exercises')),
      body: SafeArea(
        top: false,
        child: exercises.isEmpty
            ? const Center(child: Text('No exercises yet'))
            : ListView.builder(
                itemCount: sortedGroups.length,
                itemBuilder: (context, i) {
                  final muscle = sortedGroups[i];
                  final groupExercises = byMuscle[muscle]!
                    ..sort((a, b) => a.name.compareTo(b.name));
                  return ExpansionTile(
                    key: PageStorageKey(muscle?.name ?? '_uncategorized'),
                    initiallyExpanded: false,
                    title: Text(
                      muscle == null
                          ? 'Uncategorized'
                          : titleCase(muscle.sheetHeader),
                    ),
                    subtitle: Text(
                      '${groupExercises.length} exercise${groupExercises.length == 1 ? '' : 's'}',
                    ),
                    children: [
                      for (final exercise in groupExercises)
                        ListTile(
                          title: Text(exercise.name),
                          subtitle: exercise.secondaryMuscleGroups.isEmpty
                              ? null
                              : Text(
                                  '+ ${exercise.secondaryMuscleGroups.map((g) => titleCase(g.sheetHeader)).join(', ')}',
                                ),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _editExercise(context, ref, exercise),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
