import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/muscle_groups.dart';
import '../../core/utils/iso_week.dart';
import '../../core/utils/text.dart';
import '../../models/exercise.dart';
import '../../models/exercise_muscle_info.dart';
import '../../models/rating_relevance.dart';
import '../../models/set_feedback.dart';
import '../../models/workout_visit.dart';
import '../../models/year_sheet_data.dart';
import '../../providers/sheet_data_providers.dart';
import '../../widgets/exercise_tile.dart';
import '../../widgets/star_rating_input.dart';
import '../log_workout/post_save_insight_screen.dart';

class EditVisitScreen extends ConsumerStatefulWidget {
  const EditVisitScreen({super.key, required this.metaRow, this.initialNote});

  final MetaRow metaRow;

  /// Current note for this visit's day/week, if any — looked up by the
  /// caller (History already has the year data loaded).
  final String? initialNote;

  @override
  ConsumerState<EditVisitScreen> createState() => _EditVisitScreenState();
}

class _EditVisitScreenState extends ConsumerState<EditVisitScreen> {
  final Map<String, ExerciseDraft> _drafts = {};
  late final TextEditingController _noteController;
  late double _rating;
  late RatingRelevance _ratingRelevance;
  late DateTime _date;
  late List<String> _exerciseOrder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.metaRow.rating ?? 0;
    _ratingRelevance = widget.metaRow.ratingRelevance;
    _date = widget.metaRow.date;
    _noteController = TextEditingController(text: widget.initialNote ?? '');
    _exerciseOrder = [for (final e in widget.metaRow.exercises) e.exerciseName];

    final yearData = ref
        .read(snapshotProvider)
        .value
        ?.snapshot
        .yearData[widget.metaRow.isoYear];
    final muscleGroupByName = {
      for (final e in yearData?.allExercises ?? const <Exercise>[])
        e.name.toLowerCase(): e.muscleGroup,
    };

    final weekColumn = yearData?.weekColumns[widget.metaRow.isoWeek];
    for (final logged in widget.metaRow.exercises) {
      final exercise = yearData?.findExercise(logged.exerciseName);
      final matrixWeight =
          (yearData != null && exercise?.sheetRow != null && weekColumn != null)
          ? yearData.cellValues[CellKey(exercise!.sheetRow!, weekColumn)]
          : null;

      final draft = ExerciseDraft(
        Exercise(
          name: logged.exerciseName,
          muscleGroup:
              muscleGroupByName[logged.exerciseName.toLowerCase()] ??
              kCurrentMuscleGroups.first,
          muscleGroupKnown: muscleGroupByName.containsKey(
            logged.exerciseName.toLowerCase(),
          ),
        ),
      );

      if (logged.actualReps.isNotEmpty) {
        final setCount = logged.actualReps.length;
        draft.loadSets(
          weights: [
            for (var i = 0; i < setCount; i++)
              i < logged.actualWeights.length
                  ? logged.actualWeights[i]
                  : matrixWeight,
          ],
          reps: logged.actualReps,
          approxReps: logged.approxReps.length == setCount
              ? logged.approxReps
              : List<bool>.filled(setCount, false),
          setFeedback: logged.setFeedback.length == setCount
              ? logged.setFeedback
              : List<SetFeedback>.filled(setCount, SetFeedback.none),
        );
      } else {
        // Legacy visit with no per-set data on record — start from a
        // single set seeded with the averaged weight already on the
        // matrix tab.
        draft.loadSets(weights: [matrixWeight], reps: const [null]);
      }

      _drafts[logged.exerciseName] = draft;
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    _noteController.dispose();
    super.dispose();
  }

  void _reorderExercises(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _exerciseOrder.removeAt(oldIndex);
      _exerciseOrder.insert(newIndex, item);
    });
  }

  void _addExercise(Exercise exercise) {
    if (_exerciseOrder.contains(exercise.name)) return;
    setState(() {
      _exerciseOrder.add(exercise.name);
      _drafts[exercise.name] = ExerciseDraft(exercise)
        ..loadSets(weights: <double?>[null], reps: <int?>[null]);
    });
  }

  void _removeExercise(String name) {
    setState(() {
      _exerciseOrder.remove(name);
      _drafts.remove(name)?.dispose();
    });
  }

  /// Exercises this visit's year already has a matrix-tab row for, minus
  /// ones already in this visit — only these are safely addable without a
  /// heavier structural sheet write (see [_showAddExerciseSheet]).
  List<Exercise> _addableExercises() {
    final yearData = ref
        .read(snapshotProvider)
        .value
        ?.snapshot
        .yearData[widget.metaRow.isoYear];
    if (yearData == null) return const [];
    final already = _exerciseOrder.toSet();
    return [
      for (final e in yearData.allExercises)
        if (e.sheetRow != null && !already.contains(e.name)) e,
    ];
  }

  Future<void> _showAddExerciseSheet() async {
    final muscleByName = ref.read(exerciseMuscleByNameProvider);
    final candidates = _addableExercises();
    final selected = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddExerciseSheet(
        candidates: candidates,
        muscleByName: muscleByName,
      ),
    );
    if (selected != null) _addExercise(selected);
  }

  LoggedExerciseRepRange _toLoggedRange(ExerciseEntry entry) =>
      LoggedExerciseRepRange(
        exerciseName: entry.exercise.name,
        repRangeLow: entry.targetRepRangeLow,
        repRangeHigh: entry.targetRepRangeHigh,
        actualReps: entry.sets.map((s) => s.reps).toList(),
        approxReps: entry.sets.map((s) => s.approxReps).toList(),
        actualWeights: entry.sets.map((s) => s.weight).toList(),
        setFeedback: entry.sets.map((s) => s.feedback).toList(),
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    final notifier = ref.read(snapshotProvider.notifier);

    // The date change spans potentially multiple tabs and must land before
    // anything else touches this visit's row — it's the only save step
    // that requires a live connection (not offline-queueable).
    var metaRow = widget.metaRow;
    if (!DateUtils.isSameDay(_date, metaRow.date)) {
      final dateOk = await notifier.updateVisitDate(metaRow, _date);
      if (!dateOk) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't change the date — check your connection and try again.",
            ),
          ),
        );
        return;
      }
      // Re-locate the row after the move: it may have a new rowIndex, and
      // if it moved to a different year, a different meta tab entirely.
      final refreshed = ref.read(snapshotProvider).value?.snapshot;
      final newYearData = refreshed?.yearData[isoWeekYear(_date)];
      MetaRow? located;
      for (final m in newYearData?.metaRows ?? const <MetaRow>[]) {
        if (m.visitId == metaRow.visitId) {
          located = m;
          break;
        }
      }
      if (located == null) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Date changed, but the rest of this edit could not be '
              'located afterward — please reopen it from History.',
            ),
          ),
        );
        return;
      }
      metaRow = located;
    }

    final entries = <ExerciseEntry>[];
    for (final name in _exerciseOrder) {
      final entry = _drafts[name]?.toEntry();
      if (entry == null) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fill in all set weights for $name.')),
        );
        return;
      }
      entries.add(entry);
    }

    final newWeights = {
      for (final entry in entries) entry.exercise.name: entry.averageWeight,
    };
    final weightsOk = await notifier.updateVisitWeights(metaRow, newWeights);

    final setsOk = await notifier.updateVisitExerciseOrder(metaRow, [
      for (final entry in entries) _toLoggedRange(entry),
    ]);

    var ratingOk = true;
    final ratingChanged = _rating != (metaRow.rating ?? 0);
    final relevanceChanged = _ratingRelevance != metaRow.ratingRelevance;
    if (ratingChanged || relevanceChanged) {
      final outcome = await notifier.saveRating(
        isoYear: metaRow.isoYear,
        metaRowIndex: metaRow.rowIndex,
        rating: _rating,
        ratingRelevance: relevanceChanged ? _ratingRelevance : null,
      );
      ratingOk = outcome == SaveOutcome.synced;
    }

    var noteOk = true;
    final newNote = _noteController.text.trim();
    if (newNote != (widget.initialNote ?? '').trim()) {
      noteOk = await notifier.saveVisitNote(metaRow, newNote);
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (!(weightsOk && setsOk && ratingOk && noteOk)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some changes failed to save — check your connection.'),
        ),
      );
      return;
    }

    // Show the same "just logged" summary as a fresh log-workout session,
    // built from the edited values.
    final visit = WorkoutVisit(
      visitId: metaRow.visitId,
      date: metaRow.date,
      isoWeek: metaRow.isoWeek,
      isoYear: metaRow.isoYear,
      rating: _rating,
      ratingRelevance: _ratingRelevance,
      entries: entries,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PostSaveInsightScreen(visit: visit)),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this workout?'),
        content: const Text(
          'This clears its logged weights and removes it from your history. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    final ok = await ref
        .read(snapshotProvider.notifier)
        .deleteVisit(widget.metaRow);
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not delete — check your connection and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit workout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2015),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, size: 14),
                ],
              ),
            ),
          ),
          if (_exerciseOrder.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Drag to reorder',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add exercise'),
                onPressed: _showAddExerciseSheet,
              ),
            ),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: _reorderExercises,
            children: [
              for (var i = 0; i < _exerciseOrder.length; i++)
                Card(
                  key: ValueKey(_exerciseOrder[i]),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.drag_handle,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _exerciseOrder[i],
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Remove exercise',
                              onPressed: _exerciseOrder.length <= 1
                                  ? null
                                  : () => _removeExercise(_exerciseOrder[i]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SetsEditor(
                          draft: _drafts[_exerciseOrder[i]]!,
                          onChanged: () => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          const Text('Rating'),
          StarRatingInput(
            value: _rating,
            onChanged: (v) => setState(() => _rating = v),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Feeling sick / not 100%?'),
            subtitle: const Text("Won't count against your progress trends."),
            value: _ratingRelevance == RatingRelevance.unrelated,
            onChanged: (checked) => setState(() {
              _ratingRelevance = (checked ?? false)
                  ? RatingRelevance.unrelated
                  : RatingRelevance.normal;
            }),
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
                : const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for picking an exercise to add to the visit being edited —
/// tapping a row immediately adds it and closes the sheet, so no separate
/// confirm step is needed (only one exercise is added per open).
class _AddExerciseSheet extends StatefulWidget {
  const _AddExerciseSheet({required this.candidates, required this.muscleByName});

  final List<Exercise> candidates;
  final Map<String, ExerciseMuscleInfo> muscleByName;

  @override
  State<_AddExerciseSheet> createState() => _AddExerciseSheetState();
}

class _AddExerciseSheetState extends State<_AddExerciseSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.candidates.where(
      (e) => _search.isEmpty || e.name.toLowerCase().contains(_search),
    );
    final byMuscle = <String, List<Exercise>>{};
    for (final exercise in filtered) {
      final muscle =
          widget.muscleByName[exercise.name.toLowerCase()]?.muscleGroup.sheetHeader ??
          exercise.muscleGroup.sheetHeader;
      byMuscle.putIfAbsent(muscle, () => []).add(exercise);
    }
    final muscleNames = byMuscle.keys.toList()..sort();

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
                    labelText: 'Search exercises',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) =>
                      setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
              Expanded(
                child: muscleNames.isEmpty
                    ? const Center(child: Text('No exercises to add.'))
                    : ListView(
                        controller: scrollController,
                        children: [
                          for (final muscle in muscleNames) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Text(
                                titleCase(muscle),
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                            ),
                            for (final e in byMuscle[muscle]!)
                              ListTile(
                                dense: true,
                                title: Text(e.name),
                                onTap: () => Navigator.of(context).pop(e),
                              ),
                          ],
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
