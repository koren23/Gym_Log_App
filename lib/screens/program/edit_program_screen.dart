import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/text.dart';
import '../../models/exercise.dart';
import '../../models/exercise_muscle_info.dart';
import '../../models/workout_day_def.dart';
import '../../models/workout_program.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';

/// Full-screen editor for [day]'s program — the authoritative plan for that
/// day: which exercises, how many sets, and a target rep range for each,
/// grouped by muscle the same way the log page groups exercises. Drives the
/// log page's suggested order/checklist/targets, combined with logged
/// history, and can be edited any time the plan changes. Full screen (not
/// an `AlertDialog`) since editing several exercises' details needs room.
class EditProgramScreen extends ConsumerStatefulWidget {
  const EditProgramScreen({super.key, required this.day});

  final WorkoutDayDef day;

  @override
  ConsumerState<EditProgramScreen> createState() => _EditProgramScreenState();
}

class _EditProgramScreenState extends ConsumerState<EditProgramScreen> {
  late final TextEditingController _nameController;
  late List<ProgramExercise> _exercises;
  bool _saving = false;
  bool _hadExisting = false;

  @override
  void initState() {
    super.initState();
    final existing = ref
        .read(workoutProgramsProvider.notifier)
        .forDay(widget.day.id);
    _hadExisting = existing != null;
    _nameController = TextEditingController(
      text: existing?.name ?? '${widget.day.label} program',
    );
    _exercises = [...?existing?.exercises];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _updateExercise(String name, ProgramExercise Function(ProgramExercise) update) {
    setState(() {
      _exercises = [
        for (final e in _exercises) e.name == name ? update(e) : e,
      ];
    });
  }

  void _removeExercise(String name) {
    setState(() => _exercises.removeWhere((e) => e.name == name));
  }

  Future<void> _showAddExerciseSheet() async {
    final allExercises = ref.read(allKnownExercisesProvider);
    final existingNames = _exercises.map((e) => e.name).toSet();
    final candidates = [
      for (final e in allExercises)
        if (!existingNames.contains(e.name)) e,
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddExerciseNameSheet(candidates: candidates),
    );
    if (selected != null && selected.trim().isNotEmpty) {
      setState(() => _exercises.add(ProgramExercise(name: selected.trim())));
    }
  }

  /// Muscle name (from the "Exercises" reference tab when known, falling
  /// back to the matrix-tab's own [MuscleGroup]) for [exerciseName] — same
  /// precedence the log page uses to group its own checklist.
  String _muscleOf(
    String exerciseName,
    List<Exercise> allExercises,
    Map<String, ExerciseMuscleInfo> muscleByName,
  ) {
    final known = muscleByName[exerciseName.toLowerCase()];
    if (known != null) return known.muscleGroup.sheetHeader;
    for (final e in allExercises) {
      if (e.name.toLowerCase() == exerciseName.toLowerCase()) {
        return e.muscleGroup.sheetHeader;
      }
    }
    return 'unknown';
  }

  /// [_exercises] in the same muscle-alphabetical order the editor displays
  /// them (insertion order preserved within a muscle group) — this becomes
  /// the saved order, since it's also what drives suggested order on the
  /// log page and should match what was visually shown here.
  List<ProgramExercise> _flattenedByMuscle() {
    final allExercises = ref.read(allKnownExercisesProvider);
    final muscleByName = ref.read(exerciseMuscleByNameProvider);
    final byMuscle = <String, List<ProgramExercise>>{};
    for (final e in _exercises) {
      final muscle = _muscleOf(e.name, allExercises, muscleByName);
      byMuscle.putIfAbsent(muscle, () => []).add(e);
    }
    final muscleNames = byMuscle.keys.toList()..sort();
    return [for (final muscle in muscleNames) ...byMuscle[muscle]!];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(workoutProgramsProvider.notifier)
        .setProgramForDay(
          widget.day.id,
          _nameController.text.trim().isEmpty
              ? '${widget.day.label} program'
              : _nameController.text.trim(),
          _flattenedByMuscle(),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    await ref.read(workoutProgramsProvider.notifier).removeProgramForDay(widget.day.id);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final allExercises = ref.watch(allKnownExercisesProvider);
    final muscleByName = ref.watch(exerciseMuscleByNameProvider);

    final byMuscle = <String, List<ProgramExercise>>{};
    for (final e in _exercises) {
      final muscle = _muscleOf(e.name, allExercises, muscleByName);
      byMuscle.putIfAbsent(muscle, () => []).add(e);
    }
    final muscleNames = byMuscle.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.day.label} program'),
        actions: [
          if (_hadExisting)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'This is your plan for the day — exercises, sets, and a target '
            'rep range. It drives the suggested order, checklist, and '
            'targets shown while logging, combined with your real history. '
            'Edit it any time your plan changes.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Program name',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          if (_exercises.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No exercises yet — add some below.'),
            )
          else
            for (final muscle in muscleNames) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  titleCase(muscle),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              for (final exercise in byMuscle[muscle]!)
                _ProgramExerciseCard(
                  key: ValueKey(exercise.name),
                  exercise: exercise,
                  onChanged: (update) => _updateExercise(exercise.name, update),
                  onRemove: () => _removeExercise(exercise.name),
                ),
            ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
              onPressed: _showAddExerciseSheet,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save program'),
          ),
        ],
      ),
    );
  }
}

/// One exercise's set count + rep-range editor within [EditProgramScreen].
class _ProgramExerciseCard extends StatelessWidget {
  const _ProgramExerciseCard({
    super.key,
    required this.exercise,
    required this.onChanged,
    required this.onRemove,
  });

  final ProgramExercise exercise;
  final void Function(ProgramExercise Function(ProgramExercise)) onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exercise.name,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove from program',
                  onPressed: onRemove,
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  'Sets: ${exercise.sets}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Fewer sets',
                  onPressed: exercise.sets <= 1
                      ? null
                      : () => onChanged((e) => e.copyWith(sets: e.sets - 1)),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'More sets',
                  onPressed: () => onChanged((e) => e.copyWith(sets: e.sets + 1)),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: exercise.repRangeLow.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Min reps',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null) {
                        onChanged((e) => e.copyWith(repRangeLow: parsed));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: exercise.repRangeHigh.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max reps',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null) {
                        onChanged((e) => e.copyWith(repRangeHigh: parsed));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for picking an exercise name to add to the program —
/// searches known exercises, or lets a brand-new name be typed directly
/// (useful for planning an exercise not yet logged).
class _AddExerciseNameSheet extends StatefulWidget {
  const _AddExerciseNameSheet({required this.candidates});

  final List<Exercise> candidates;

  @override
  State<_AddExerciseNameSheet> createState() => _AddExerciseNameSheetState();
}

class _AddExerciseNameSheetState extends State<_AddExerciseNameSheet> {
  String _search = '';
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.candidates
        .where((e) => _search.isEmpty || e.name.toLowerCase().contains(_search))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search or type a new exercise name',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  controller: _customController,
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
              if (_customController.text.trim().isNotEmpty &&
                  !filtered.any(
                    (e) =>
                        e.name.toLowerCase() ==
                        _customController.text.trim().toLowerCase(),
                  ))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.add),
                  title: Text('Add "${_customController.text.trim()}"'),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_customController.text.trim()),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching exercises.'))
                    : ListView(
                        controller: scrollController,
                        children: [
                          for (final e in filtered)
                            ListTile(
                              dense: true,
                              title: Text(e.name),
                              onTap: () => Navigator.of(context).pop(e.name),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
