import 'package:flutter/material.dart';

import '../core/constants/sheet_layout.dart';
import '../models/exercise.dart';
import '../models/workout_visit.dart';

/// Mutable per-exercise editing state used while building up a workout
/// visit in the log-workout flow. Owns the [TextEditingController]s for
/// its own set fields so the same draft can be edited from more than one
/// place on screen (the checklist tile and the "Workout so far" summary)
/// and stay in sync, and so a value the user already typed survives
/// unrelated rebuilds instead of appearing blank.
class ExerciseDraft {
  ExerciseDraft(
    this.exercise, {
    int setCount = kDefaultSetCount,
    int repRangeLow = kDefaultRepRangeLow,
    int repRangeHigh = kDefaultRepRangeHigh,
  }) : _repsMid = (repRangeLow + repRangeHigh) ~/ 2,
       setWeights = List<double?>.filled(setCount, null, growable: true),
       setReps = List<int?>.filled(setCount, null, growable: true),
       setApproxReps = List<bool>.filled(setCount, false, growable: true),
       weightControllers = List.generate(
         setCount,
         (_) => TextEditingController(),
         growable: true,
       ),
       repsControllers = List.generate(
         setCount,
         (_) => TextEditingController(),
         growable: true,
       );

  final Exercise exercise;
  final int _repsMid;
  List<double?> setWeights;
  List<int?> setReps;
  List<bool> setApproxReps;
  final List<TextEditingController> weightControllers;
  final List<TextEditingController> repsControllers;

  bool get isComplete => setWeights.every((w) => w != null && w > 0);

  int repsFor(int index) => setReps[index] ?? _repsMid;

  void addSet() {
    setWeights.add(null);
    setReps.add(null);
    setApproxReps.add(false);
    weightControllers.add(TextEditingController());
    repsControllers.add(TextEditingController());
  }

  void removeLastSet() {
    if (setWeights.length <= 1) return;
    setWeights.removeLast();
    setReps.removeLast();
    setApproxReps.removeLast();
    weightControllers.removeLast().dispose();
    repsControllers.removeLast().dispose();
  }

  /// Replaces all set data (used when applying a persisted/restored draft),
  /// rebuilding the controllers so their displayed text matches.
  void loadSets({
    required List<double?> weights,
    required List<int?> reps,
    List<bool>? approxReps,
  }) {
    for (final c in weightControllers) {
      c.dispose();
    }
    for (final c in repsControllers) {
      c.dispose();
    }
    setWeights = weights;
    setReps = reps;
    setApproxReps =
        approxReps ?? List<bool>.filled(weights.length, false, growable: true);
    weightControllers
      ..clear()
      ..addAll([
        for (final w in weights)
          TextEditingController(text: w?.toString() ?? ''),
      ]);
    repsControllers
      ..clear()
      ..addAll([
        for (final r in reps) TextEditingController(text: r?.toString() ?? ''),
      ]);
  }

  void dispose() {
    for (final c in weightControllers) {
      c.dispose();
    }
    for (final c in repsControllers) {
      c.dispose();
    }
  }

  ExerciseEntry? toEntry() {
    if (!isComplete) return null;
    final sets = [
      for (var i = 0; i < setWeights.length; i++)
        SetEntry(
          weight: setWeights[i]!,
          reps: repsFor(i),
          approxReps: setApproxReps[i],
        ),
    ];
    final repsUsed = sets.map((s) => s.reps).toList();
    return ExerciseEntry(
      exercise: exercise,
      sets: sets,
      targetRepRangeLow: repsUsed.reduce((a, b) => a < b ? a : b),
      targetRepRangeHigh: repsUsed.reduce((a, b) => a > b ? a : b),
    );
  }
}

/// A checkable exercise row that expands into a set-entry editor when
/// selected.
class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    super.key,
    required this.draft,
    required this.selected,
    required this.onToggle,
    required this.onChanged,
    this.previousWeight,
  });

  final ExerciseDraft draft;
  final bool selected;
  final ValueChanged<bool> onToggle;
  final VoidCallback onChanged;

  /// Most recently logged average weight for this exercise, if any —
  /// shown as a subtitle so the user can tell what they lifted last time
  /// before entering today's weights.
  final double? previousWeight;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          CheckboxListTile(
            title: Text(draft.exercise.name),
            subtitle: previousWeight == null
                ? null
                : Text('Last time: ${previousWeight!.toStringAsFixed(1)} kg'),
            value: selected,
            onChanged: (v) => onToggle(v ?? false),
          ),
          if (selected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SetsEditor(draft: draft, onChanged: onChanged),
            ),
        ],
      ),
    );
  }
}

/// The add/remove-set controls plus the per-set weight/reps/approx field
/// grid for [draft] — shared by the log-workout exercise editor, the
/// "Workout so far" inline editor, and the edit-visit screen.
class SetsEditor extends StatelessWidget {
  const SetsEditor({super.key, required this.draft, required this.onChanged});

  final ExerciseDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Sets: ${draft.setWeights.length}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove set',
              onPressed: draft.setWeights.length <= 1
                  ? null
                  : () {
                      draft.removeLastSet();
                      onChanged();
                    },
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add set',
              onPressed: () {
                draft.addSet();
                onChanged();
              },
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < draft.setWeights.length; i++)
              _SetEditorRow(
                key: ValueKey('${draft.exercise.name}_set_$i'),
                setIndex: i,
                draft: draft,
                onChanged: onChanged,
              ),
          ],
        ),
        if (draft.isComplete)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Average: ${draft.toEntry()!.averageWeight.toStringAsFixed(1)} kg',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _SetEditorRow extends StatefulWidget {
  const _SetEditorRow({
    super.key,
    required this.setIndex,
    required this.draft,
    required this.onChanged,
  });

  final int setIndex;
  final ExerciseDraft draft;
  final VoidCallback onChanged;

  @override
  State<_SetEditorRow> createState() => _SetEditorRowState();
}

class _SetEditorRowState extends State<_SetEditorRow> {
  final _weightFocus = FocusNode();
  final _repsFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _weightFocus.addListener(_scrollIntoViewOnFocus);
    _repsFocus.addListener(_scrollIntoViewOnFocus);
  }

  void _scrollIntoViewOnFocus() {
    if (!_weightFocus.hasFocus && !_repsFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.3,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  @override
  void dispose() {
    _weightFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final i = widget.setIndex;
    // Sets can be removed via the "Remove set" button while this row's
    // element is still around for one frame; guard against a stale index.
    if (i >= draft.setWeights.length) return const SizedBox.shrink();
    final approx = draft.setApproxReps[i];
    final theme = Theme.of(context);
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: draft.weightControllers[i],
              focusNode: _weightFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Set ${i + 1} (kg)',
                isDense: true,
              ),
              onChanged: (text) {
                draft.setWeights[i] = double.tryParse(text);
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextFormField(
              controller: draft.repsControllers[i],
              focusNode: _repsFocus,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Reps',
                isDense: true,
                hintText: '${draft.repsFor(i)}',
              ),
              onChanged: (text) {
                draft.setReps[i] = int.tryParse(text);
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: approx ? 'Marked approximate' : 'Mark reps as approximate',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                draft.setApproxReps[i] = !approx;
                widget.onChanged();
              },
              child: CircleAvatar(
                radius: 14,
                backgroundColor: approx
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  '~',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: approx
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
