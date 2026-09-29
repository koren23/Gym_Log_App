import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/exercise.dart';
import '../../models/workout_day_def.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';

/// Full-screen editor for [day]'s premade workout template — an ordered
/// exercise-name list that seeds the log page's checklist/order for this
/// day and can be edited any time to "remember" a planned change, even
/// before it's ever logged. Full screen (not an `AlertDialog`) since
/// ordered multi-item editing needs room, mirroring `EditVisitScreen`'s
/// `ReorderableListView` + searchable add-sheet pattern.
class EditPremadeWorkoutScreen extends ConsumerStatefulWidget {
  const EditPremadeWorkoutScreen({super.key, required this.day});

  final WorkoutDayDef day;

  @override
  ConsumerState<EditPremadeWorkoutScreen> createState() =>
      _EditPremadeWorkoutScreenState();
}

class _EditPremadeWorkoutScreenState
    extends ConsumerState<EditPremadeWorkoutScreen> {
  late final TextEditingController _nameController;
  late List<String> _exerciseNames;
  bool _saving = false;
  bool _hadExisting = false;

  @override
  void initState() {
    super.initState();
    final existing = ref
        .read(premadeWorkoutsProvider.notifier)
        .forDay(widget.day.id);
    _hadExisting = existing != null;
    _nameController = TextEditingController(
      text: existing?.name ?? '${widget.day.label} template',
    );
    _exerciseNames = [...?existing?.exerciseNames];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _exerciseNames.removeAt(oldIndex);
      _exerciseNames.insert(newIndex, item);
    });
  }

  void _removeAt(int index) {
    setState(() => _exerciseNames.removeAt(index));
  }

  Future<void> _showAddExerciseSheet() async {
    final allExercises = ref.read(allKnownExercisesProvider);
    final candidates = [
      for (final e in allExercises)
        if (!_exerciseNames.contains(e.name)) e,
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddExerciseNameSheet(candidates: candidates),
    );
    if (selected != null && selected.trim().isNotEmpty) {
      setState(() => _exerciseNames.add(selected.trim()));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(premadeWorkoutsProvider.notifier)
        .setTemplateForDay(
          widget.day.id,
          _nameController.text.trim().isEmpty
              ? '${widget.day.label} template'
              : _nameController.text.trim(),
          _exerciseNames,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    await ref
        .read(premadeWorkoutsProvider.notifier)
        .removeTemplateForDay(widget.day.id);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.day.label} premade workout'),
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
            'Once set, this template drives the suggested order and '
            'checklist for this day — even ahead of your logged history. '
            'Edit it any time your usual routine changes.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Template name',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_exerciseNames.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Drag to reorder',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          if (_exerciseNames.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No exercises yet — add some below.'),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: _reorder,
              children: [
                for (var i = 0; i < _exerciseNames.length; i++)
                  ListTile(
                    key: ValueKey(_exerciseNames[i]),
                    dense: true,
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(_exerciseNames[i]),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _removeAt(i),
                    ),
                  ),
              ],
            ),
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
                : const Text('Save template'),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for picking an exercise name to add to the template —
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
