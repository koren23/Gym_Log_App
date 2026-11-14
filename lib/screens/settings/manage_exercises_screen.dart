import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/muscle_groups.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Manage exercises')),
      body: exercises.isEmpty
          ? const Center(child: Text('No exercises yet'))
          : ListView.builder(
              itemCount: exercises.length,
              itemBuilder: (context, i) {
                final exercise = exercises[i];
                final subtitleParts = [
                  titleCase(exercise.muscleGroup.sheetHeader),
                  if (exercise.secondaryMuscleGroups.isNotEmpty)
                    '+ ${exercise.secondaryMuscleGroups.map((g) => titleCase(g.sheetHeader)).join(', ')}',
                ];
                return ListTile(
                  title: Text(exercise.name),
                  subtitle: Text(subtitleParts.join('  ')),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editExercise(context, ref, exercise),
                );
              },
            ),
    );
  }
}
